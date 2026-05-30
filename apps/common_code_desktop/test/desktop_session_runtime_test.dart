import 'dart:async';
import 'dart:convert';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_desktop/src/desktop_session_runtime.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_observability/common_code_observability.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_core/host_core.dart';
import 'package:host_in_memory/host_in_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('HostDesktopSessionRuntime', () {
    test('initialize uses the durable local host default path', () async {
      final diagnostics = <DurableLocalHostDiagnosticCode>[];
      final runtime = _createDurableRuntime(
        snapshotStore: _MemoryLegacySnapshotStore(),
        diagnosticsPort: DurableLocalHostDiagnosticsEmitter(
          (diagnostic) => diagnostics.add(diagnostic.code),
        ),
      );
      final snapshots = <Session>[];
      runtime.bind(
        onSnapshot: snapshots.add,
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();

      expect(snapshots.single.id, desktopSessionRuntimeDefaultSessionId);
      expect(
        diagnostics,
        containsAllInOrder(<DurableLocalHostDiagnosticCode>[
          DurableLocalHostDiagnosticCode.durableReadMissing,
          DurableLocalHostDiagnosticCode.legacySeedActivated,
          DurableLocalHostDiagnosticCode.legacySeedFailed,
          DurableLocalHostDiagnosticCode.freshBootstrapActivated,
        ]),
      );
    });

    test(
      'runtime emits missing branch diagnostics when legacy seeding succeeds',
      () async {
        final diagnostics = <DurableLocalHostDiagnosticCode>[];
        final durableStorage = _MemoryDurableStorage();
        final snapshotStore = _MemoryLegacySnapshotStore(
          storedSession: _completedSession(),
        );
        final runtime = _createDurableRuntime(
          durableStorage: durableStorage,
          snapshotStore: snapshotStore,
          diagnosticsPort: DurableLocalHostDiagnosticsEmitter(
            (diagnostic) => diagnostics.add(diagnostic.code),
          ),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        expect(snapshot, isNotNull);
        expect(snapshot!.id, 'restored-session');
        expect(
          diagnostics,
          containsAllInOrder(<DurableLocalHostDiagnosticCode>[
            DurableLocalHostDiagnosticCode.durableReadMissing,
            DurableLocalHostDiagnosticCode.legacySeedActivated,
            DurableLocalHostDiagnosticCode.legacySeedSucceeded,
          ]),
        );
        expect(
          diagnostics,
          isNot(
            contains(DurableLocalHostDiagnosticCode.freshBootstrapActivated),
          ),
        );
      },
    );

    test(
      'runtime emits missing branch diagnostics when legacy seeding is skipped',
      () async {
        final diagnostics = <DurableLocalHostDiagnosticCode>[];
        final durableStorage = _MemoryDurableStorage();
        final snapshotStore = _MemoryLegacySnapshotStore(
          storedSession: _completedSession(),
        );
        durableStorage.legacySeedEnabled = false;
        final runtime = _createDurableRuntime(
          durableStorage: durableStorage,
          snapshotStore: snapshotStore,
          diagnosticsPort: DurableLocalHostDiagnosticsEmitter(
            (diagnostic) => diagnostics.add(diagnostic.code),
          ),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        expect(snapshot, isNotNull);
        expect(snapshot!.id, desktopSessionRuntimeDefaultSessionId);
        expect(
          diagnostics,
          containsAllInOrder(<DurableLocalHostDiagnosticCode>[
            DurableLocalHostDiagnosticCode.durableReadMissing,
            DurableLocalHostDiagnosticCode.legacySeedSkipped,
            DurableLocalHostDiagnosticCode.freshBootstrapActivated,
          ]),
        );
        expect(
          diagnostics,
          isNot(contains(DurableLocalHostDiagnosticCode.legacySeedActivated)),
        );
      },
    );

    test(
      'runtime emits corrupt branch diagnostics when legacy seeding fails',
      () async {
        final diagnostics = <DurableLocalHostDiagnosticCode>[];
        final durableStorage = _MemoryDurableStorage(payload: '{bad-json');
        final runtime = _createDurableRuntime(
          durableStorage: durableStorage,
          snapshotStore: _MemoryLegacySnapshotStore(),
          diagnosticsPort: DurableLocalHostDiagnosticsEmitter(
            (diagnostic) => diagnostics.add(diagnostic.code),
          ),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        expect(snapshot, isNotNull);
        expect(snapshot!.id, desktopSessionRuntimeDefaultSessionId);
        expect(
          diagnostics,
          containsAllInOrder(<DurableLocalHostDiagnosticCode>[
            DurableLocalHostDiagnosticCode.durableReadCorruptOrInvalid,
            DurableLocalHostDiagnosticCode.legacySeedActivated,
            DurableLocalHostDiagnosticCode.legacySeedFailed,
            DurableLocalHostDiagnosticCode.freshBootstrapActivated,
          ]),
        );
      },
    );

    test(
      'runtime emits read_failed diagnostics before legacy seed fallback',
      () async {
        final diagnostics = <DurableLocalHostDiagnosticCode>[];
        final durableStorage = _MemoryDurableStorage(
          readError: StateError('read failed'),
        );
        final runtime = _createDurableRuntime(
          durableStorage: durableStorage,
          snapshotStore: _MemoryLegacySnapshotStore(
            storedSession: _completedSession(),
          ),
          diagnosticsPort: DurableLocalHostDiagnosticsEmitter(
            (diagnostic) => diagnostics.add(diagnostic.code),
          ),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        expect(snapshot, isNotNull);
        expect(snapshot!.id, 'restored-session');
        expect(
          diagnostics,
          containsAllInOrder(<DurableLocalHostDiagnosticCode>[
            DurableLocalHostDiagnosticCode.durableReadFailed,
            DurableLocalHostDiagnosticCode.legacySeedActivated,
            DurableLocalHostDiagnosticCode.legacySeedSucceeded,
          ]),
        );
      },
    );

    test(
      'runtime falls back fresh when legacy restore persist fails',
      () async {
        final diagnostics = <DurableLocalHostDiagnosticCode>[];
        final runtime = _createDurableRuntime(
          durableStorage: _MemoryDurableStorage(
            writeError: StateError('write failed'),
          ),
          snapshotStore: _MemoryLegacySnapshotStore(
            storedSession: _completedSession(),
          ),
          diagnosticsPort: DurableLocalHostDiagnosticsEmitter(
            (diagnostic) => diagnostics.add(diagnostic.code),
          ),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        expect(snapshot, isNotNull);
        expect(snapshot!.id, desktopSessionRuntimeDefaultSessionId);
        expect(
          diagnostics,
          containsAllInOrder(<DurableLocalHostDiagnosticCode>[
            DurableLocalHostDiagnosticCode.durableReadMissing,
            DurableLocalHostDiagnosticCode.legacySeedActivated,
            DurableLocalHostDiagnosticCode.legacySeedFailed,
            DurableLocalHostDiagnosticCode.freshBootstrapActivated,
          ]),
        );
        expect(
          diagnostics,
          isNot(contains(DurableLocalHostDiagnosticCode.legacySeedSucceeded)),
        );
      },
    );

    test('restart continuity surfaces restored durable state', () async {
      final durableStorage = _MemoryDurableStorage(
        payload: jsonEncode(
          const SessionSnapshotCodec().encode(
            _runningSessionWithNotifications(),
          ),
        ),
      );
      final snapshotStore = _MemoryLegacySnapshotStore();
      final hostAdapter = InMemoryHostAdapter();
      final sessionStore = DurableLocalSessionStore.fromPersistenceComponents(
        legacySnapshotStore: snapshotStore,
        durableStorage: durableStorage,
      );
      final bootstrapPort = CommonCodeSessionBootstrapPortAdapter(
        sessionStore: sessionStore,
        host: CommonCodeSessionBootstrapHost(
          restoreSession: hostAdapter.restoreSession,
          createSession: hostAdapter.createSession,
          attachClient: hostAdapter.attachClient,
        ),
      );
      final runtime = HostDesktopSessionRuntime(
        hostService: hostAdapter as HostService,
        bootstrapPort: bootstrapPort,
        snapshotStore: snapshotStore,
        persistSessionMutation: _createPersistSessionMutation(
          sessionStore,
          attachedClientId: desktopSessionRuntimeAttachedClientId,
        ),
      );
      Session? snapshot;
      runtime.bind(
        onSnapshot: (session) => snapshot = session,
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();

      expect(snapshot, isNotNull);
      expect(snapshot!.id, 'restored-session');
      expect(snapshot!.activeTurn?.status, TurnStatus.running);
      expect(
        snapshot!.notifications,
        _runningSessionWithNotifications().notifications,
      );
    });

    test(
      'initialize uses bootstrap port lifecycle without durable concrete type',
      () async {
        final hostService = _BootstrapPortHostService(
          bootstrappedSession: _completedSession(),
        );
        final runtime = HostDesktopSessionRuntime(
          hostService: hostService,
          snapshotStore: _FailingLegacySnapshotStore(),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();
        await runtime.refresh();

        expect(snapshot, isNotNull);
        expect(snapshot!.id, 'restored-session');
        expect(hostService.loadDurableCalls, 1);
        expect(hostService.restoreDurableCalls, 1);
        expect(hostService.watchStarts, 2);
        expect(hostService.createCalls, 0);
        expect(hostService.attachCalls, 0);
        expect(hostService.restoreCalls, 1);
      },
    );

    test(
      'watch path establishes cached identity context before subscription',
      () async {
        final hostService = _TrackingHostService();
        late HostDesktopSessionRuntime runtime;
        hostService.onWatchSession = () {
          final context = runtime.debugSessionContext;
          expect(context, isNotNull);
          expect(context!.sessionId, 'restored-session');
          expect(
            context.identity,
            const Identity(id: desktopSessionRuntimeIdentityId),
          );
          expect(
            context.attachedClientId,
            desktopSessionRuntimeAttachedClientId,
          );
        };
        runtime = HostDesktopSessionRuntime(
          hostService: hostService,
          snapshotStore: _MemoryLegacySnapshotStore(
            storedSession: _completedSession(),
          ),
        );
        runtime.bind(
          onSnapshot: (session) {},
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        expect(runtime.debugSessionContext, (
          sessionId: 'restored-session',
          identity: const Identity(id: desktopSessionRuntimeIdentityId),
          attachedClientId: desktopSessionRuntimeAttachedClientId,
        ));
      },
    );

    test(
      'submit reuses the cached session context from watch bootstrap',
      () async {
        final hostService = _TrackingHostService();
        final runtime = HostDesktopSessionRuntime(
          hostService: hostService,
          snapshotStore: _MemoryLegacySnapshotStore(
            storedSession: _completedSession(),
          ),
        );
        runtime.bind(
          onSnapshot: (session) {},
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();
        final initialContext = runtime.debugSessionContext;

        await runtime.submitTurn(submittedText: 'reuse cached context');

        expect(runtime.debugSessionContext, initialContext);
        expect(hostService.restoreCalls, 1);
        expect(hostService.lastSubmittedSessionId, initialContext!.sessionId);
        expect(
          hostService.lastSubmittedClientId,
          initialContext.attachedClientId,
        );
      },
    );

    test(
      'refresh cancels the prior watch before starting replacement watch',
      () async {
        final hostService = _TrackingHostService();
        final runtime = HostDesktopSessionRuntime(
          hostService: hostService,
          snapshotStore: _MemoryLegacySnapshotStore(
            storedSession: _completedSession(),
          ),
        );
        runtime.bind(
          onSnapshot: (session) {},
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();
        await runtime.refresh();

        expect(hostService.watchStarts, 2);
        expect(hostService.watchCancels, 1);
        expect(hostService.concurrentWatchViolation, isFalse);
        expect(hostService.createCalls, 0);
        expect(hostService.attachCalls, 0);
        expect(hostService.readCalls, 0);
        expect(hostService.restoreCalls, 1);
      },
    );

    test(
      'runtime emits durable restore failure diagnostics for fallback branch',
      () async {
        final diagnostics = <DurableLocalHostDiagnosticCode>[];
        final runtime = _createRejectingDurableRuntime(
          durableStorage: _MemoryDurableStorage(
            payload: jsonEncode(
              const SessionSnapshotCodec().encode(_queuedSession()),
            ),
          ),
          snapshotStore: _MemoryLegacySnapshotStore(
            storedSession: _completedSession(),
          ),
          diagnosticsPort: DurableLocalHostDiagnosticsEmitter(
            (diagnostic) => diagnostics.add(diagnostic.code),
          ),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        expect(snapshot, isNotNull);
        expect(snapshot!.id, desktopSessionRuntimeDefaultSessionId);
        expect(
          diagnostics,
          containsAllInOrder(<DurableLocalHostDiagnosticCode>[
            DurableLocalHostDiagnosticCode.durableRestoreFailed,
            DurableLocalHostDiagnosticCode.freshBootstrapActivated,
          ]),
        );
        expect(
          diagnostics,
          isNot(contains(DurableLocalHostDiagnosticCode.legacySeedActivated)),
        );
      },
    );

    test(
      'durable write failures stay non-fatal through the runtime seam',
      () async {
        final diagnostics = <DurableLocalHostDiagnosticCode>[];
        final storage = _MemoryDurableStorage();
        final hostAdapter = InMemoryHostAdapter();
        final hostService = hostAdapter as HostService;
        final diagnosticsPort = DurableLocalHostDiagnosticsEmitter(
          (diagnostic) => diagnostics.add(diagnostic.code),
        );
        final sessionStore = DurableLocalSessionStore.fromPersistenceComponents(
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
          durableStorage: storage,
        );
        final bootstrapPort = CommonCodeSessionBootstrapPortAdapter(
          sessionStore: sessionStore,
          host: CommonCodeSessionBootstrapHost(
            restoreSession: hostAdapter.restoreSession,
            createSession: hostAdapter.createSession,
            attachClient: hostAdapter.attachClient,
          ),
          diagnosticsPort: diagnosticsPort,
        );
        final runtime = HostDesktopSessionRuntime(
          hostService: hostService,
          bootstrapPort: bootstrapPort,
          snapshotStore: _MemoryLegacySnapshotStore(),
          persistSessionMutation: _createPersistSessionMutation(
            sessionStore,
            attachedClientId: desktopSessionRuntimeAttachedClientId,
            diagnosticsPort: diagnosticsPort,
          ),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();
        storage.writeError = StateError('write failed');

        await runtime.submitTurn(submittedText: 'persist me');
        await sessionStore.waitForPendingPersistence();

        expect(snapshot, isNotNull);
        expect(
          hostService.readSession(snapshot!.id).activeTurn?.submittedText,
          'persist me',
        );
        expect(
          diagnostics,
          contains(DurableLocalHostDiagnosticCode.durableWriteFailed),
        );
      },
    );

    test(
      'host-driven streamed transition persists updated session without second explicit mutation',
      () async {
        final durableStorage = _MemoryDurableStorage();
        final hostAdapter = _MultiEmittingInMemoryHostAdapter();
        final sessionStore = DurableLocalSessionStore.fromPersistenceComponents(
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
          durableStorage: durableStorage,
        );
        final bootstrapPort = CommonCodeSessionBootstrapPortAdapter(
          sessionStore: sessionStore,
          host: CommonCodeSessionBootstrapHost(
            restoreSession: hostAdapter.restoreSession,
            createSession: hostAdapter.createSession,
            attachClient: hostAdapter.attachClient,
          ),
        );
        final runtime = HostDesktopSessionRuntime(
          hostService: hostAdapter as HostService,
          bootstrapPort: bootstrapPort,
          snapshotStore: _MemoryLegacySnapshotStore(),
          persistSessionMutation: _createPersistSessionMutation(
            sessionStore,
            attachedClientId: desktopSessionRuntimeAttachedClientId,
          ),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();
        await sessionStore.waitForPendingPersistence();

        // Capture initial payload after initialize - this is the baseline write
        final initialPayload = durableStorage.payload;
        expect(initialPayload, isNotNull);
        final initialDecoded = const SessionSnapshotCodec().decode(
          jsonDecode(initialPayload!),
          desktopClientId: desktopSessionRuntimeAttachedClientId,
        );

        // Trigger a host-driven transition WITHOUT going through submitTurn.
        // The adapter's advanceSessionToNextState emits directly through the watch
        // stream, simulating a host-driven transition that occurs independently
        // of any client mutation. This proves the watch path itself triggers
        // persistence, not just the explicit mutation path.
        hostAdapter.advanceSessionToNextState();

        // Wait for the watch to deliver the updated session and persistence to complete
        await sessionStore.waitForPendingPersistence();

        // The durable storage must reflect a NEW write that is DISTINCT from
        // the initialize() write. This proves the watch path persisted the
        // host-driven transition, not just replaying the initial mutation result.
        final payloadAfter = durableStorage.payload;
        expect(payloadAfter, isNotNull);

        // Prove distinct write: payload must differ from initial
        // (If only submitTurn had triggered persistence, initialPayload == payloadAfter)
        expect(payloadAfter, isNot(equals(initialPayload)));

        // Decode and verify the session state reflects the host-driven transition
        final decoded = const SessionSnapshotCodec().decode(
          jsonDecode(payloadAfter!),
          desktopClientId: desktopSessionRuntimeAttachedClientId,
        );

        // Verify the session advanced state through the watch path
        // (host-driven transitions advance queued->running->completed)
        expect(decoded.promptThread.turns.last.status, TurnStatus.running);

        // Verify notification ids are preserved verbatim from the streamed snapshot,
        // including isAcknowledged flags. This proves the watch path does not
        // re-synthesize or re-key notifications.
        final initialNotificationMap = {
          for (final n in initialDecoded.notifications) n.id: n,
        };
        for (final original in decoded.notifications) {
          final initial = initialNotificationMap[original.id];
          if (initial != null) {
            expect(original.isAcknowledged, initial.isAcknowledged,
                reason: 'Notification ${original.id} isAcknowledged must be preserved');
            expect(original.turnId, initial.turnId,
                reason: 'Notification ${original.id} turnId must be preserved');
            expect(original.transition, initial.transition,
                reason: 'Notification ${original.id} transition must be preserved');
          }
        }
      },
    );
  });
}

Session _baseSession() {
  return Session(
    id: 'restored-session',
    activeHost: const Host(id: 'restored-host'),
    clients: const <Client>[
      Client(id: desktopSessionRuntimeAttachedClientId),
      Client(id: 'reviewer-client'),
    ],
  );
}

Session _queuedSession() {
  return _baseSession().startTurn(
    turnId: 'turn-1',
    client: const Client(id: 'reviewer-client'),
    submittedText: 'Queued turn',
  );
}

Session _completedSession() {
  return _baseSession()
      .startTurn(
        turnId: 'turn-1',
        client: const Client(id: 'reviewer-client'),
        submittedText: 'Completed turn',
      )
      .advanceActiveTurnToRunning()
      .completeActiveTurn();
}

Session _runningSessionWithNotifications() {
  final activeSession = _baseSession()
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
    id: activeSession.id,
    activeHost: activeSession.activeHost,
    clients: activeSession.clients,
    promptThread: activeSession.promptThread,
    notifications: <SessionNotification>[
      SessionNotification.forTransition(
        sessionId: activeSession.id,
        turnId: 'turn-1',
        transition: SessionNotificationTransition.queuedToRunning,
      ),
      SessionNotification.forTransition(
        sessionId: activeSession.id,
        turnId: 'turn-1',
        transition: SessionNotificationTransition.runningToCompleted,
        isAcknowledged: true,
      ),
      SessionNotification.forTransition(
        sessionId: activeSession.id,
        turnId: 'turn-2',
        transition: SessionNotificationTransition.queuedToRunning,
      ),
    ],
  );
}

final class _MemoryLegacySnapshotStore implements SessionSnapshotStore {
  _MemoryLegacySnapshotStore({this.storedSession});

  final Session? storedSession;

  @override
  Future<Session?> readLatestSession({required String desktopClientId}) async {
    return storedSession;
  }

  @override
  Future<void> writeLatestSession(Session session) async {}
}

final class _FailingLegacySnapshotStore implements SessionSnapshotStore {
  @override
  Future<Session?> readLatestSession({required String desktopClientId}) {
    throw StateError('legacy snapshot path should not be used');
  }

  @override
  Future<void> writeLatestSession(Session session) async {}
}

final class _MemoryDurableStorage implements DurableSessionStore {
  _MemoryDurableStorage({this.payload, this.readError, this.writeError});

  String? payload;
  bool legacySeedEnabled = true;
  Object? readError;
  Object? writeError;

  @override
  Future<void> disableLegacySeed({required String desktopClientId}) async {
    legacySeedEnabled = false;
  }

  @override
  Future<bool> isLegacySeedEnabled({required String desktopClientId}) async {
    return legacySeedEnabled;
  }

  @override
  Future<String?> readSessionPayload() async {
    final error = readError;
    if (error != null) {
      throw error;
    }

    return payload;
  }

  @override
  Future<void> writeSessionPayload(String payload) async {
    final error = writeError;
    if (error != null) {
      throw error;
    }

    this.payload = payload;
  }
}

final class _TrackingHostService implements HostService {
  final Map<String, Session> _sessions = <String, Session>{};
  final Map<String, StreamController<Session>> _controllers =
      <String, StreamController<Session>>{};

  int createCalls = 0;
  int attachCalls = 0;
  int readCalls = 0;
  int restoreCalls = 0;
  int watchStarts = 0;
  int watchCancels = 0;
  bool concurrentWatchViolation = false;
  void Function()? onWatchSession;
  String? lastSubmittedSessionId;
  String? lastSubmittedClientId;

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
    attachCalls += 1;
    final updated = _sessions[sessionId]!.attachClient(client);
    _sessions[sessionId] = updated;
    _controllers[sessionId]?.add(updated);
    return updated;
  }

  @override
  Session createSession({required String sessionId, required Host activeHost}) {
    createCalls += 1;
    final session = Session(id: sessionId, activeHost: activeHost);
    _sessions[sessionId] = session;
    return session;
  }

  @override
  Session readSession(String sessionId) {
    readCalls += 1;
    return _sessions[sessionId]!;
  }

  @override
  Session restoreSession(Session session) {
    restoreCalls += 1;
    _sessions[session.id] = session;
    return session;
  }

  @override
  Session submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) {
    lastSubmittedSessionId = sessionId;
    lastSubmittedClientId = client.id;
    final updated = _sessions[sessionId]!.startTurn(
      turnId: 'turn-1',
      client: client,
      submittedText: submittedText,
    );
    _sessions[sessionId] = updated;
    _controllers[sessionId]?.add(updated);
    return updated;
  }

  @override
  Stream<Session> watchSession(String sessionId) {
    onWatchSession?.call();
    if (_controllers.containsKey(sessionId)) {
      concurrentWatchViolation = true;
      throw const HostServiceFailure(
        HostServiceFailureCode.activeSessionWatchAlreadyExists,
        'Session already has an active watch.',
      );
    }

    watchStarts += 1;
    late final StreamController<Session> controller;
    controller = StreamController<Session>(
      sync: true,
      onListen: () {
        _controllers[sessionId] = controller;
        controller.add(_sessions[sessionId]!);
      },
      onCancel: () {
        watchCancels += 1;
        _controllers.remove(sessionId);
      },
    );
    return controller.stream;
  }
}

final class _BootstrapPortHostService extends _TrackingHostService
    implements CommonCodeSessionBootstrapPort {
  _BootstrapPortHostService({required Session bootstrappedSession})
    : _bootstrappedSession = bootstrappedSession;

  final Session _bootstrappedSession;

  int loadDurableCalls = 0;
  int restoreDurableCalls = 0;

  @override
  CommonCodeSessionStore get sessionStore => _BootstrapPortSessionStore(this);

  @override
  Future<CommonCodeDurableBootstrapLoadResult> loadDurableSessionCandidate({
    required String attachedClientId,
  }) {
    return sessionStore.loadDurableSessionCandidate(
      attachedClientId: attachedClientId,
    );
  }

  @override
  Future<CommonCodeLegacySeedLoadResult> loadLegacySeedSession({
    required String attachedClientId,
  }) {
    return sessionStore.loadLegacySeedSession(
      attachedClientId: attachedClientId,
    );
  }

  @override
  Future<Session> createFreshSession(
    CommonCodeSessionBootstrapRequest request,
  ) async {
    throw StateError('fresh bootstrap should not be used');
  }

  @override
  Session restoreDurableSession(Session session) {
    restoreDurableCalls += 1;
    return restoreSession(session);
  }

  @override
  Future<Session> restoreLegacySeededSession({
    required Session session,
    required String attachedClientId,
  }) async {
    throw StateError('legacy seed restore should not be used');
  }
}

final class _BootstrapPortSessionStore implements CommonCodeSessionStore {
  const _BootstrapPortSessionStore(this.hostService);

  final _BootstrapPortHostService hostService;

  @override
  Future<CommonCodeDurableBootstrapLoadResult> loadDurableSessionCandidate({
    required String attachedClientId,
  }) async {
    hostService.loadDurableCalls += 1;
    return CommonCodeDurableBootstrapLoadResult.available(
      hostService._bootstrappedSession,
    );
  }

  @override
  Future<CommonCodeLegacySeedLoadResult> loadLegacySeedSession({
    required String attachedClientId,
  }) async {
    throw StateError('legacy seed path should not be used');
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

final class _MultiEmittingInMemoryHostAdapter implements HostService {
  _MultiEmittingInMemoryHostAdapter();

  final Map<String, Session> _sessions = <String, Session>{};
  final Map<String, StreamController<Session>> _controllers =
      <String, StreamController<Session>>{};

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
        // No active turn - create one with a queued->running notification
        // and emit the snapshot directly. This simulates a host that pushes
        // a complete transition snapshot through the watch stream.
        // Use a client that exists in the session's clients list to avoid
        // SessionFailure.inputClientNotAttached validation.
        final turnClientId = session.clients.isNotEmpty
            ? session.clients.first.id
            : 'reviewer-client'; // Fallback for pre-attached-client session
        final notification = SessionNotification.forTransition(
          sessionId: session.id,
          turnId: 'turn-1',
          transition: SessionNotificationTransition.queuedToRunning,
        );
        updated = Session(
          id: session.id,
          activeHost: session.activeHost,
          clients: session.clients,
          promptThread: session.promptThread.append(
            Turn.running(
              id: 'turn-1',
              clientId: turnClientId,
              submittedText: 'Host-initiated turn',
            ),
          ),
          notifications: [...session.notifications, notification],
        );
      } else if (session.activeTurn!.status == TurnStatus.queued) {
        updated = session.advanceActiveTurnToRunning();
      } else {
        continue; // Already running or completed
      }

      _sessions[entry.key] = updated;
      entry.value.add(updated);
    }
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
    final turnNumber = session.promptThread.turns
            .where((t) => t.clientId == client.id)
            .length +
        1;
    final updated = session.startTurn(
      turnId: 'turn-$turnNumber',
      client: client,
      submittedText: submittedText,
    );
    _sessions[sessionId] = updated;
    // Emit to existing watch controller (host-driven transition)
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

HostDesktopSessionRuntime _createDurableRuntime({
  SessionSnapshotStore? snapshotStore,
  Object? durableStorage,
  DurableLocalHostDiagnosticsPort? diagnosticsPort,
}) {
  final effectiveSnapshotStore = snapshotStore ?? _MemoryLegacySnapshotStore();
  final hostAdapter = InMemoryHostAdapter();
  final sessionStore = DurableLocalSessionStore.fromPersistenceComponents(
    legacySnapshotStore: effectiveSnapshotStore,
    durableStorage: durableStorage,
  );
  final bootstrapPort = CommonCodeSessionBootstrapPortAdapter(
    sessionStore: sessionStore,
    host: CommonCodeSessionBootstrapHost(
      restoreSession: hostAdapter.restoreSession,
      createSession: hostAdapter.createSession,
      attachClient: hostAdapter.attachClient,
    ),
    diagnosticsPort: diagnosticsPort,
  );
  return HostDesktopSessionRuntime(
    hostService: hostAdapter as HostService,
    bootstrapPort: bootstrapPort,
    snapshotStore: effectiveSnapshotStore,
    persistSessionMutation: _createPersistSessionMutation(
      sessionStore,
      attachedClientId: desktopSessionRuntimeAttachedClientId,
      diagnosticsPort: diagnosticsPort,
    ),
  );
}

HostDesktopSessionRuntime _createRejectingDurableRuntime({
  required SessionSnapshotStore snapshotStore,
  required Object? durableStorage,
  DurableLocalHostDiagnosticsPort? diagnosticsPort,
}) {
  final hostAdapter = InMemoryHostAdapter();
  final sessionStore = DurableLocalSessionStore.fromPersistenceComponents(
    legacySnapshotStore: snapshotStore,
    durableStorage: durableStorage,
  );
  final bootstrapPort = CommonCodeSessionBootstrapPortAdapter(
    sessionStore: sessionStore,
    host: CommonCodeSessionBootstrapHost(
      restoreSession: (session) => throw StateError('restore rejected'),
      createSession: hostAdapter.createSession,
      attachClient: hostAdapter.attachClient,
    ),
    diagnosticsPort: diagnosticsPort,
  );
  return HostDesktopSessionRuntime(
    hostService: hostAdapter as HostService,
    bootstrapPort: bootstrapPort,
    snapshotStore: snapshotStore,
    persistSessionMutation: _createPersistSessionMutation(
      sessionStore,
      attachedClientId: desktopSessionRuntimeAttachedClientId,
      diagnosticsPort: diagnosticsPort,
    ),
  );
}

void Function(Session session) _createPersistSessionMutation(
  DurableLocalSessionStore sessionStore, {
  required String attachedClientId,
  DurableLocalHostDiagnosticsPort? diagnosticsPort,
}) {
  return sessionStore.createPersistenceContinuation(
    attachedClientId: attachedClientId,
    onError: createDurableWriteFailureReporter(diagnosticsPort),
  );
}
