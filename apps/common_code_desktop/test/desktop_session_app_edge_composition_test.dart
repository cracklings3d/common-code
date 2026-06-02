import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_desktop/src/desktop_session_app_edge_composition.dart';
import 'package:common_code_desktop/src/desktop_session_runtime.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_observability/common_code_observability.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_in_memory/host_in_memory.dart';

void main() {
  group('createDesktopSessionFacade', () {
    test(
      'composes restore, submit, acknowledge, persistence, and diagnostics',
      () async {
        final diagnostics = <DurableLocalHostDiagnosticCode>[];
        final durableStorage = _MemoryDurableStorage(
          payload: jsonEncode(
            const SessionSnapshotCodec().encode(
              _completedSessionWithNotification(),
            ),
          ),
        );
        final sessionStore = DurableLocalSessionStore.fromPersistenceComponents(
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
          durableStorage: durableStorage,
        );
        final hostAdapter = InMemoryHostAdapter();
        final hostService = hostAdapter as HostService;
        final facade = createDesktopSessionFacade(
          hostService: hostService,
          bootstrapPort: CommonCodeSessionBootstrapPortAdapter(
            sessionStore: sessionStore,
            host: CommonCodeSessionBootstrapHost(
              restoreSession: hostAdapter.restoreSession,
              createSession: hostAdapter.createSession,
              attachClient: hostAdapter.attachClient,
            ),
            diagnosticsPort: DurableLocalHostDiagnosticsEmitter(
              (diagnostic) => diagnostics.add(diagnostic.code),
            ),
          ),
          persistSessionMutation: sessionStore.createPersistenceContinuation(
            attachedClientId: desktopSessionRuntimeAttachedClientId,
            onError: createDurableWriteFailureReporter(
              DurableLocalHostDiagnosticsEmitter(
                (diagnostic) => diagnostics.add(diagnostic.code),
              ),
            ),
          ),
        );

        await facade.initialize();

        expect(facade.state.status, CommonCodeSessionFacadeStatus.data);
        expect(
          facade.state.snapshot!.session.notifications.where(
            (notification) => !notification.isAcknowledged,
          ),
          hasLength(1),
        );
        expect(
          diagnostics,
          contains(DurableLocalHostDiagnosticCode.durableReadRestored),
        );

        await facade.submitTurn(submittedText: 'persist me');
        await sessionStore.waitForPendingPersistence();

        expect(
          hostService.readSession('restored-session').activeTurn?.submittedText,
          'persist me',
        );
        expect(await durableStorage.readSessionPayload(), isNotNull);
        expect(
          await durableStorage.isLegacySeedEnabled(
            desktopClientId: desktopSessionRuntimeAttachedClientId,
          ),
          isFalse,
        );

        final notificationId = facade.state.snapshot!.session.notifications
            .firstWhere((notification) => !notification.isAcknowledged)
            .id;
        await facade.acknowledgeNotification(notificationId: notificationId);

        expect(
          hostService
              .readSession('restored-session')
              .notifications
              .firstWhere((notification) => notification.id == notificationId)
              .isAcknowledged,
          isTrue,
        );

        await facade.dispose();
      },
    );

    test(
      'watch path persists host-driven transition independently of explicit submitTurn',
      () async {
        final durableStorage = _MemoryDurableStorage();
        final sessionStore = DurableLocalSessionStore.fromPersistenceComponents(
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
          durableStorage: durableStorage,
        );
        final hostAdapter = _MultiEmittingInMemoryHostAdapter();
        final hostService = hostAdapter as HostService;
        final facade = createDesktopSessionFacade(
          hostService: hostService,
          bootstrapPort: CommonCodeSessionBootstrapPortAdapter(
            sessionStore: sessionStore,
            host: CommonCodeSessionBootstrapHost(
              restoreSession: hostAdapter.restoreSession,
              createSession: hostAdapter.createSession,
              attachClient: hostAdapter.attachClient,
            ),
          ),
          persistSessionMutation: sessionStore.createPersistenceContinuation(
            attachedClientId: desktopSessionRuntimeAttachedClientId,
            onError: createDurableWriteFailureReporter(null),
          ),
        );

        await facade.initialize();
        await sessionStore.waitForPendingPersistence();

        // Emit a fresh session with known acknowledged+unacknowledged notifications
        // through the watch stream. This is the non-vacuous baseline for AC2.
        final streamedSnapshot = hostAdapter
            .emitStreamedSessionWithNotifications();
        await sessionStore.waitForPendingPersistence();

        // Capture the initial payload after the streamed emission
        final initialPayload = durableStorage.payload;
        expect(initialPayload, isNotNull);

        // Record initial notifications for preservation verification
        final initialNotificationMap = {
          for (final n in streamedSnapshot.notifications) n.id: n,
        };

        // Trigger host-driven transition WITHOUT any explicit mutation (submitTurn, etc.)
        // The _MultiEmittingInMemoryHostAdapter.advanceSessionToNextState() emits
        // directly through the watch stream, simulating a host transition that occurs
        // independently of client mutations. This proves the watch path itself,
        // not mutation handlers, triggers persistence.
        hostAdapter.advanceSessionToNextState();
        await sessionStore.waitForPendingPersistence();

        // Prove a distinct durable write occurred from the watch path
        final payloadAfter = durableStorage.payload;
        expect(payloadAfter, isNotNull);
        expect(
          payloadAfter,
          isNot(equals(initialPayload)),
          reason: 'Watch path must trigger distinct write beyond initialize()',
        );

        // Verify the persisted state reflects the host-driven advancement
        final decoded = const SessionSnapshotCodec().decode(
          jsonDecode(payloadAfter!),
          desktopClientId: desktopSessionRuntimeAttachedClientId,
        );

        // The host-driven advancement should have advanced the staged queued turn to running
        expect(decoded.promptThread.turns.last.status, TurnStatus.running);

        // Verify notifications are preserved verbatim from the streamed path
        final decodedNotifications = decoded.notifications;
        expect(
          decodedNotifications,
          isNotEmpty,
          reason: 'Notifications must be preserved through watch persistence',
        );
        for (final notification in decodedNotifications) {
          expect(
            notification.id,
            isNotEmpty,
            reason: 'Notification id must be deterministic and preserved',
          );
          expect(
            notification.turnId,
            isNotEmpty,
            reason: 'Notification turnId must be preserved',
          );
          expect(
            notification.transition,
            isNotNull,
            reason: 'Notification transition must be preserved',
          );
          // isAcknowledged flag must be verbatim from the streamed snapshot
        }

        // Verify initial notifications are preserved (not re-synthesized)
        for (final initial in initialNotificationMap.values) {
          final persisted = decoded.notifications.firstWhere(
            (n) => n.id == initial.id,
            orElse: () => throw StateError(
              'Notification ${initial.id} not found after persistence',
            ),
          );
          expect(
            persisted.isAcknowledged,
            initial.isAcknowledged,
            reason:
                'Notification ${initial.id} isAcknowledged must be preserved',
          );
          expect(
            persisted.turnId,
            initial.turnId,
            reason: 'Notification ${initial.id} turnId must be preserved',
          );
          expect(
            persisted.transition,
            initial.transition,
            reason: 'Notification ${initial.id} transition must be preserved',
          );
        }

        await facade.dispose();
      },
    );

    test(
      'facade threads non-default desktopIdentityId and attachedClientId from app edge',
      () async {
        const nonDefaultIdentityId = 'test-facade-identity';
        const nonDefaultClientId = 'test-facade-client';
        final capturedRequests = <CommonCodeSessionBootstrapRequest>[];

        final hostAdapter = _CapturingBootstrapHostAdapter(
          onCreateFreshSession: (request) {
            capturedRequests.add(request);
          },
        );
        final facade = createDesktopSessionFacade(
          hostService: hostAdapter as HostService,
          bootstrapPort: _CapturingBootstrapPortAdapter(
            hostAdapter: hostAdapter,
          ),
          attachedClientId: nonDefaultClientId,
          desktopIdentityId: nonDefaultIdentityId,
        );

        await facade.initialize();

        // Verify the facade threaded the non-default values through to the bootstrap request
        expect(capturedRequests, hasLength(1));
        expect(
          capturedRequests.first.desktopIdentity,
          const Identity(id: nonDefaultIdentityId),
        );
        expect(capturedRequests.first.attachedClientId, nonDefaultClientId);

        await facade.dispose();
      },
    );

    test(
      'source-structure regression guard: default facade path uses host_opencode package types',
      () async {
        // Find source files relative to the test file location
        // Platform.script can point to a cached location, so we use testDir
        // which is the directory containing the running test script
        final testScript = File(Platform.script.toFilePath());
        final testDir = testScript.parent;
        // testDir appears to be apps/common_code_desktop/ (not apps/common_code_desktop/test/)
        // so lib/src is a direct child
        final libSrcDirUri = testDir.uri.resolve('lib/src/');
        final compositionSrcFile = File.fromUri(
          libSrcDirUri.resolve('desktop_session_app_edge_composition.dart'),
        );
        final facadeAdaptersSrcFile = File.fromUri(
          libSrcDirUri.resolve('desktop_session_facade_adapters.dart'),
        );

        final compositionContent = await compositionSrcFile.readAsString();
        final facadeAdaptersContent = await facadeAdaptersSrcFile
            .readAsString();

        // Assert the default facade path imports the host_opencode package
        expect(
          compositionContent,
          contains("import 'package:host_opencode/host_opencode.dart'"),
          reason:
              'desktop_session_app_edge_composition.dart must import '
              'package:host_opencode/host_opencode.dart to use the '
              'OpenCode host adapter package.',
        );

        // Assert the default facade path composes the required types
        // from the host_opencode package
        expect(
          compositionContent,
          contains('OpenCodeHostGateway'),
          reason:
              'default facade must compose OpenCodeHostGateway '
              'from the host_opencode package.',
        );
        expect(
          compositionContent,
          contains('OpenCodePersistingHostServiceSessionObservation'),
          reason:
              'default facade must compose OpenCodePersistingHostServiceSessionObservation '
              'from the host_opencode package.',
        );
        expect(
          compositionContent,
          contains('OpenCodeHostServiceSessionObservation'),
          reason:
              'default facade must compose OpenCodeHostServiceSessionObservation '
              'from the host_opencode package.',
        );
        expect(
          compositionContent,
          contains('OutOfProcessOpenCodeHostAdapter('),
          reason:
              'default facade must use OutOfProcessOpenCodeHostAdapter '
              'from the host_opencode package.',
        );

        // Assert desktop_session_facade_adapters.dart has NOT regained those types
        // (ownership boundary regression guard)
        expect(
          facadeAdaptersContent,
          isNot(contains('OpenCodeHostGateway')),
          reason:
              'desktop_session_facade_adapters.dart must not define '
              'OpenCodeHostGateway - that type belongs to '
              'the host_opencode package.',
        );
        expect(
          facadeAdaptersContent,
          isNot(contains('OpenCodePersistingHostServiceSessionObservation')),
          reason:
              'desktop_session_facade_adapters.dart must not define '
              'OpenCodePersistingHostServiceSessionObservation - that type belongs to '
              'the host_opencode package.',
        );
        expect(
          facadeAdaptersContent,
          isNot(contains('OpenCodeHostServiceSessionObservation')),
          reason:
              'desktop_session_facade_adapters.dart must not define '
              'OpenCodeHostServiceSessionObservation - that type belongs to '
              'the host_opencode package.',
        );
        expect(
          facadeAdaptersContent,
          isNot(contains('OpenCodeHostAdapter')),
          reason:
              'desktop_session_facade_adapters.dart must not define '
              'OpenCodeHostAdapter - that type belongs to '
              'the host_opencode package.',
        );

        // Assert the live desktop path does NOT import host_core
        // (HostService is now Application-owned via common_code_application)
        final runtimeSrcFile = File.fromUri(
          libSrcDirUri.resolve('desktop_session_runtime.dart'),
        );
        final runtimeContent = await runtimeSrcFile.readAsString();
        expect(
          runtimeContent,
          isNot(contains("import 'package:host_core/host_core.dart'")),
          reason:
              'desktop_session_runtime.dart must not import host_core - '
              'HostService is now Application-owned via common_code_application.',
        );

        expect(
          facadeAdaptersContent,
          isNot(contains("import 'package:host_core/host_core.dart'")),
          reason:
              'desktop_session_facade_adapters.dart must not import host_core - '
              'HostService is now Application-owned via common_code_application.',
        );

        expect(
          compositionContent,
          isNot(contains("import 'package:host_core/host_core.dart'")),
          reason:
              'desktop_session_app_edge_composition.dart must not import host_core - '
              'HostService is now Application-owned via common_code_application.',
        );

        // Assert host_opencode source files do NOT import host_core directly
        // (they should use Application-owned HostService from common_code_application)
        final hostOpencodeDir = testDir.parent.parent.uri.resolve(
          'packages/host_opencode/lib/src/',
        );
        for (final fileName in [
          'opencode_host_adapter.dart',
          'opencode_host_gateway.dart',
          'opencode_session_observation.dart',
          'opencode_mapping.dart',
        ]) {
          final srcFile = File.fromUri(hostOpencodeDir.resolve(fileName));
          if (await srcFile.exists()) {
            final srcContent = await srcFile.readAsString();
            expect(
              srcContent,
              isNot(contains("import 'package:host_core/host_core.dart'")),
              reason:
                  '$fileName must not import host_core - '
                  'it must use HostService from common_code_application.',
            );
          }
        }

        // Assert host_opencode package does not leak OpenCode-specific types
        // to public contracts above the adapter boundary
        final hostOpencodeLibFile = File.fromUri(
          testDir.parent.parent.uri.resolve(
            'packages/host_opencode/lib/host_opencode.dart',
          ),
        );
        if (await hostOpencodeLibFile.exists()) {
          final hostOpencodeContent = await hostOpencodeLibFile.readAsString();
          // host_opencode.dart should NOT export internal src/ mapping helpers
          expect(
            hostOpencodeContent,
            isNot(contains("export 'src/opencode_mapping.dart'")),
            reason:
                'host_opencode.dart must not export opencode_mapping.dart - '
                'mapping helpers must stay internal to the adapter package.',
          );
        }
      },
    );
  });
}

Session _completedSessionWithNotification() {
  final session =
      Session(
            id: 'restored-session',
            activeHost: const Host(id: 'restored-host'),
            clients: const <Client>[
              Client(id: desktopSessionRuntimeAttachedClientId),
              Client(id: 'reviewer-client'),
            ],
          )
          .startTurn(
            turnId: 'turn-1',
            client: const Client(id: 'reviewer-client'),
            submittedText: 'Restored turn',
          )
          .advanceActiveTurnToRunning()
          .completeActiveTurn();

  return Session(
    id: session.id,
    activeHost: session.activeHost,
    clients: session.clients,
    promptThread: session.promptThread,
    notifications: <SessionNotification>[
      SessionNotification.forTransition(
        sessionId: session.id,
        turnId: 'turn-1',
        transition: SessionNotificationTransition.queuedToRunning,
      ),
    ],
  );
}

Session _completedSessionWithNotifications() {
  final session =
      Session(
            id: 'restored-session',
            activeHost: const Host(id: 'restored-host'),
            clients: const <Client>[
              Client(id: desktopSessionRuntimeAttachedClientId),
              Client(id: 'reviewer-client'),
            ],
          )
          .startTurn(
            turnId: 'turn-1',
            client: const Client(id: 'reviewer-client'),
            submittedText: 'First turn',
          )
          .advanceActiveTurnToRunning()
          .completeActiveTurn()
          .startTurn(
            turnId: 'turn-2',
            client: const Client(id: 'reviewer-client'),
            submittedText: 'Second turn',
          )
          .advanceActiveTurnToRunning();

  return Session(
    id: session.id,
    activeHost: session.activeHost,
    clients: session.clients,
    promptThread: session.promptThread,
    notifications: <SessionNotification>[
      SessionNotification.forTransition(
        sessionId: session.id,
        turnId: 'turn-1',
        transition: SessionNotificationTransition.queuedToRunning,
      ),
      SessionNotification.forTransition(
        sessionId: session.id,
        turnId: 'turn-1',
        transition: SessionNotificationTransition.runningToCompleted,
        isAcknowledged: true,
      ),
      SessionNotification.forTransition(
        sessionId: session.id,
        turnId: 'turn-2',
        transition: SessionNotificationTransition.queuedToRunning,
      ),
    ],
  );
}

final class _MemoryLegacySnapshotStore implements SessionSnapshotStore {
  @override
  Future<Session?> readLatestSession({required String desktopClientId}) async {
    return null;
  }

  @override
  Future<void> writeLatestSession(Session session) async {}
}

final class _MemoryDurableStorage implements DurableSessionStore {
  _MemoryDurableStorage({this.payload, this.legacySeedEnabled = true});

  String? payload;
  bool legacySeedEnabled;

  @override
  Future<void> disableLegacySeed({required String desktopClientId}) async {
    legacySeedEnabled = false;
  }

  @override
  Future<bool> isLegacySeedEnabled({required String desktopClientId}) async {
    return legacySeedEnabled;
  }

  @override
  Future<String?> readSessionPayload() async => payload;

  @override
  Future<void> writeSessionPayload(String payload) async {
    this.payload = payload;
  }
}

final class _MultiEmittingInMemoryHostAdapter implements HostService {
  _MultiEmittingInMemoryHostAdapter();

  final Map<String, Session> _sessions = <String, Session>{};
  final Map<String, StreamController<Session>> _controllers =
      <String, StreamController<Session>>{};

  /// Stages a queued turn with notifications, simulating a session that has
  /// a turn waiting to be processed. Call this before advanceSessionToNextState()
  /// to set up a non-empty notification baseline for preservation tests.
  void stageQueuedTurnWithNotifications() {
    for (final entry in _controllers.entries) {
      final session = _sessions[entry.key];
      if (session == null) continue;

      final turnClientId = session.clients.isNotEmpty
          ? session.clients.first.id
          : 'reviewer-client';
      final notification = SessionNotification.forTransition(
        sessionId: session.id,
        turnId: 'turn-1',
        transition: SessionNotificationTransition.queuedToRunning,
      );
      final updated = Session(
        id: session.id,
        activeHost: session.activeHost,
        clients: session.clients,
        promptThread: session.promptThread.append(
          Turn.queued(
            id: 'turn-1',
            clientId: turnClientId,
            submittedText: 'Staged turn',
          ),
        ),
        notifications: [...session.notifications, notification],
      );
      _sessions[entry.key] = updated;
    }
  }

  /// Emits a host-driven state transition directly through the watch stream
  /// without going through any mutation method (submitTurn, acknowledgeNotification).
  /// This simulates a transition that the host performs independently of client
  /// mutations, proving the watch path triggers persistence.
  void advanceSessionToNextState() {
    for (final entry in _controllers.entries) {
      final session = _sessions[entry.key];
      if (session == null) continue;

      Session updated;
      if (session.activeTurn == null) {
        // No active turn - stage a queued turn with a notification first.
        // This ensures the test has a non-empty notification baseline.
        stageQueuedTurnWithNotifications();
        // Re-fetch the session after staging
        final stagedSession = _sessions[entry.key]!;
        // Now advance the staged queued turn to running - this should emit
        // the queued->running notification
        updated = _advanceQueuedTurnToRunning(stagedSession);
      } else if (session.activeTurn!.status == TurnStatus.queued) {
        // Advance queued turn to running - emit queued->running notification
        updated = _advanceQueuedTurnToRunning(session);
      } else if (session.activeTurn!.status == TurnStatus.running) {
        // Advance running turn to completed - emit running->completed notification
        updated = _advanceRunningTurnToCompleted(session);
      } else {
        continue; // Already completed or failed
      }

      _sessions[entry.key] = updated;
      entry.value.add(updated);
    }
  }

  Session _advanceQueuedTurnToRunning(Session session) {
    return session.advanceActiveTurnToRunning();
  }

  Session _advanceRunningTurnToCompleted(Session session) {
    return session.completeActiveTurn();
  }

  /// Emits a fresh session with a known mix of acknowledged and unacknowledged
  /// notifications directly through the watch stream, then returns the emitted
  /// session. Use this to create a non-vacuous baseline for notification
  /// preservation tests.
  Session emitStreamedSessionWithNotifications() {
    for (final entry in _controllers.entries) {
      final session = _sessions[entry.key];
      if (session == null) continue;

      final turnId = session.promptThread.turns.isNotEmpty
          ? 'turn-${session.promptThread.turns.length + 1}'
          : 'turn-1';
      final turnClientId = session.clients.isNotEmpty
          ? session.clients.first.id
          : 'reviewer-client';

      // Create a session with both acknowledged and unacknowledged notifications
      // so the preservation assertion is non-vacuous (AC2).
      final notifications = <SessionNotification>[
        SessionNotification.forTransition(
          sessionId: session.id,
          turnId: turnId,
          transition: SessionNotificationTransition.queuedToRunning,
          isAcknowledged: false,
        ),
        SessionNotification.forTransition(
          sessionId: session.id,
          turnId: turnId,
          transition: SessionNotificationTransition.runningToCompleted,
          isAcknowledged: true,
        ),
      ];

      final queuedTurn = Turn.queued(
        id: turnId,
        clientId: turnClientId,
        submittedText: 'Streamed turn',
      );

      final updated = Session(
        id: session.id,
        activeHost: session.activeHost,
        clients: session.clients,
        promptThread: session.promptThread.append(queuedTurn),
        notifications: notifications,
      );

      _sessions[entry.key] = updated;
      entry.value.add(updated);
      return updated;
    }
    throw StateError('No active session controller to emit through');
  }

  @override
  Session acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  }) {
    final session = _sessions[sessionId]!;
    var didAcknowledge = false;
    final updatedSession = Session(
      id: session.id,
      activeHost: session.activeHost,
      clients: session.clients,
      promptThread: session.promptThread,
      notifications: [
        for (final notification in session.notifications)
          if (notification.id == notificationId && !notification.isAcknowledged)
            () {
              didAcknowledge = true;
              return SessionNotification.forTransition(
                sessionId: session.id,
                turnId: notification.turnId,
                transition: notification.transition,
                isAcknowledged: true,
              );
            }()
          else
            notification,
      ],
    );

    if (!didAcknowledge) {
      return session;
    }

    _sessions[sessionId] = updatedSession;
    _controllers[sessionId]?.add(updatedSession);
    return updatedSession;
  }

  @override
  Session attachClient({required String sessionId, required Client client}) {
    final updated = _sessions[sessionId]!.attachClient(client);
    _sessions[sessionId] = updated;
    _controllers[sessionId]?.add(updated);
    return updated;
  }

  @override
  Session createSession({required String sessionId, required Host activeHost}) {
    final session = Session(id: sessionId, activeHost: activeHost);
    _sessions[sessionId] = session;
    return session;
  }

  @override
  Session readSession(String sessionId) {
    return _sessions[sessionId]!;
  }

  @override
  Session restoreSession(Session session) {
    _sessions[session.id] = session;
    return session;
  }

  @override
  Session submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) {
    final session = _sessions[sessionId]!;
    final turnNumber =
        session.promptThread.turns
            .where((t) => t.clientId == client.id)
            .length +
        1;
    final updated = session.startTurn(
      turnId: 'turn-$turnNumber',
      client: client,
      submittedText: submittedText,
    );
    _sessions[sessionId] = updated;
    _controllers[sessionId]?.add(updated);
    return updated;
  }

  @override
  Stream<Session> watchSession(String sessionId) {
    if (_controllers.containsKey(sessionId)) {
      throw const HostServiceFailure(
        HostServiceFailureCode.activeSessionWatchAlreadyExists,
        'Session already has an active watch.',
      );
    }

    late final StreamController<Session> controller;
    controller = StreamController<Session>(
      sync: true,
      onListen: () {
        _controllers[sessionId] = controller;
        controller.add(_sessions[sessionId]!);
      },
      onCancel: () {
        _controllers.remove(sessionId);
      },
    );
    return controller.stream;
  }
}

/// A [HostService] that captures [CommonCodeSessionBootstrapRequest] values
/// passed during session creation for test verification.
final class _CapturingBootstrapHostAdapter implements HostService {
  _CapturingBootstrapHostAdapter({
    required void Function(CommonCodeSessionBootstrapRequest request)
    onCreateFreshSession,
  }) : _onCreateFreshSession = onCreateFreshSession;

  final void Function(CommonCodeSessionBootstrapRequest request)
  _onCreateFreshSession;

  final Map<String, Session> _sessions = <String, Session>{};

  @override
  Session acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  }) {
    return _sessions[sessionId]!;
  }

  @override
  Session attachClient({required String sessionId, required Client client}) {
    return _sessions[sessionId]!.attachClient(client);
  }

  @override
  Session createSession({required String sessionId, required Host activeHost}) {
    final session = Session(id: sessionId, activeHost: activeHost);
    _sessions[sessionId] = session;
    return session;
  }

  @override
  Session readSession(String sessionId) {
    return _sessions[sessionId]!;
  }

  @override
  Session restoreSession(Session session) {
    _sessions[session.id] = session;
    return session;
  }

  @override
  Session submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) {
    final session = _sessions[sessionId]!;
    final turnNumber =
        session.promptThread.turns
            .where((t) => t.clientId == client.id)
            .length +
        1;
    final updated = session.startTurn(
      turnId: 'turn-$turnNumber',
      client: client,
      submittedText: submittedText,
    );
    _sessions[sessionId] = updated;
    return updated;
  }

  @override
  Stream<Session> watchSession(String sessionId) {
    return Stream<Session>.value(_sessions[sessionId]!);
  }
}

/// A [CommonCodeSessionBootstrapPort] that captures the bootstrap request
/// for test verification.
final class _CapturingBootstrapPortAdapter
    implements CommonCodeSessionBootstrapPort {
  _CapturingBootstrapPortAdapter({
    required _CapturingBootstrapHostAdapter hostAdapter,
  }) : _hostAdapter = hostAdapter;

  final _CapturingBootstrapHostAdapter _hostAdapter;

  @override
  CommonCodeSessionStore get sessionStore =>
      _CapturingBootstrapSessionStore(this);

  @override
  Future<CommonCodeDurableBootstrapLoadResult> loadDurableSessionCandidate({
    required String attachedClientId,
  }) async {
    return CommonCodeDurableBootstrapLoadResult.missing();
  }

  @override
  Future<CommonCodeLegacySeedLoadResult> loadLegacySeedSession({
    required String attachedClientId,
  }) async {
    return const CommonCodeLegacySeedLoadResult.missing();
  }

  @override
  Session restoreDurableSession(Session session) {
    return session;
  }

  @override
  Future<Session> restoreLegacySeededSession({
    required Session session,
    required String attachedClientId,
  }) async {
    return session;
  }

  @override
  Future<Session> createFreshSession(
    CommonCodeSessionBootstrapRequest request,
  ) async {
    _hostAdapter._onCreateFreshSession(request);
    final createdSession = _hostAdapter.createSession(
      sessionId: request.defaultSessionId,
      activeHost: Host(id: request.hostId),
    );
    return _hostAdapter.attachClient(
      sessionId: createdSession.id,
      client: Client(id: request.attachedClientId),
    );
  }
}

final class _CapturingBootstrapSessionStore implements CommonCodeSessionStore {
  const _CapturingBootstrapSessionStore(this._port);

  final _CapturingBootstrapPortAdapter _port;

  @override
  Future<CommonCodeDurableBootstrapLoadResult> loadDurableSessionCandidate({
    required String attachedClientId,
  }) async {
    return _port.loadDurableSessionCandidate(
      attachedClientId: attachedClientId,
    );
  }

  @override
  Future<CommonCodeLegacySeedLoadResult> loadLegacySeedSession({
    required String attachedClientId,
  }) async {
    return _port.loadLegacySeedSession(attachedClientId: attachedClientId);
  }

  @override
  Future<void> persistSession(
    Session session, {
    String? attachedClientId,
  }) async {}

  @override
  Future<void> queueSessionPersistence(
    Session session, {
    String? attachedClientId,
  }) async {}

  @override
  Future<void> waitForPendingPersistence() async {}
}
