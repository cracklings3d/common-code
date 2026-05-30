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

  group('SessionSnapshotCodec', () {
    const codec = SessionSnapshotCodec();

    test('round-trips schema 2 notifications without synthesis', () {
      final encoded = codec.encode(_runningSessionWithNotifications());
      final decoded = codec.decode(
        encoded,
        desktopClientId: desktopSessionRuntimeAttachedClientId,
      );

      expectSessionLike(decoded, _runningSessionWithNotifications());
      expect(encoded['schemaVersion'], 2);
    });

    test('schema 1 restore yields empty notifications', () {
      final decoded = codec.decode(<String, Object?>{
        'schemaVersion': 1,
        'sessionId': 'restored-session',
        'activeHostId': 'restored-host',
        'clientIds': <String>[
          desktopSessionRuntimeAttachedClientId,
          'reviewer-client',
        ],
        'turns': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'turn-1',
            'clientId': 'reviewer-client',
            'submittedText': 'Completed turn',
            'status': 'completed',
            'failureSummary': null,
          },
        ],
      }, desktopClientId: desktopSessionRuntimeAttachedClientId);

      expect(decoded.notifications, isEmpty);
    });
  });

  group('SharedPreferencesDurableSessionStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('writes and reads durable payload and marker', () async {
      final storage = SharedPreferencesDurableSessionStore();

      await storage.writeSessionPayload('payload');
      expect(await storage.readSessionPayload(), 'payload');
      expect(
        await storage.isLegacySeedEnabled(
          desktopClientId: desktopSessionRuntimeAttachedClientId,
        ),
        isTrue,
      );

      await storage.disableLegacySeed(
        desktopClientId: desktopSessionRuntimeAttachedClientId,
      );
      expect(
        await storage.isLegacySeedEnabled(
          desktopClientId: desktopSessionRuntimeAttachedClientId,
        ),
        isFalse,
      );
    });
  });

  group('desktop durable continuity compatibility', () {
    test('eligible legacy snapshot seeds durable state once', () async {
      final storage = _MemoryDurableStorage();
      final legacyStore = _MemoryLegacySnapshotStore(
        storedSession: _completedSessionWithNotifications(),
      );
      final runtime = _createDurableRuntime(
        durableStorage: storage,
        snapshotStore: legacyStore,
      );
      Session? snapshot;
      runtime.bind(
        onSnapshot: (session) => snapshot = session,
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();
      await _lastCreatedSessionStore!.waitForPendingPersistence();

      expectSessionLike(snapshot!, _completedSessionWithNotifications());
      expect(storage.payload, isNotNull);
      expect(storage.legacySeedEnabled, isFalse);
    });

    test('missing ineligible branch boots fresh instead of seeding', () async {
      final diagnostics = <DurableLocalHostDiagnosticCode>[];
      final storage = _MemoryDurableStorage(legacySeedEnabled: false);
      final runtime = _createDurableRuntime(
        durableStorage: storage,
        snapshotStore: _MemoryLegacySnapshotStore(
          storedSession: _completedSessionWithNotifications(),
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
          DurableLocalHostDiagnosticCode.legacySeedSkipped,
          DurableLocalHostDiagnosticCode.freshBootstrapActivated,
        ]),
      );
    });

    test('corrupt ineligible branch boots fresh instead of seeding', () async {
      final diagnostics = <DurableLocalHostDiagnosticCode>[];
      final runtime = _createDurableRuntime(
        durableStorage: _MemoryDurableStorage(
          payload: '{bad-json',
          legacySeedEnabled: false,
        ),
        snapshotStore: _MemoryLegacySnapshotStore(
          storedSession: _completedSessionWithNotifications(),
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
          DurableLocalHostDiagnosticCode.durableReadCorruptOrInvalid,
          DurableLocalHostDiagnosticCode.legacySeedSkipped,
          DurableLocalHostDiagnosticCode.freshBootstrapActivated,
        ]),
      );
    });

    test(
      'after first successful durable write bootstrap ignores legacy shadow data',
      () async {
        final storage = _MemoryDurableStorage(
          payload: jsonEncode(
            const SessionSnapshotCodec().encode(
              _runningSessionWithNotifications(),
            ),
          ),
          legacySeedEnabled: false,
        );
        final runtime = _createDurableRuntime(
          durableStorage: storage,
          snapshotStore: _MemoryLegacySnapshotStore(
            storedSession: _completedSessionWithNotifications(),
          ),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        expectSessionLike(snapshot!, _runningSessionWithNotifications());
      },
    );

    test(
      'acknowledged notifications stay non-replayable after restart while unacknowledged remain replayable',
      () async {
        final runtime = _createDurableRuntime(
          durableStorage: _MemoryDurableStorage(
            payload: jsonEncode(
              const SessionSnapshotCodec().encode(
                _runningSessionWithNotifications(),
              ),
            ),
          ),
          snapshotStore: _MemoryLegacySnapshotStore(),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        final replayableNotifications = snapshot!.notifications
            .where((notification) => !notification.isAcknowledged)
            .toList(growable: false);
        final acknowledgedNotifications = snapshot!.notifications
            .where((notification) => notification.isAcknowledged)
            .toList(growable: false);

        expect(replayableNotifications, hasLength(2));
        expect(acknowledgedNotifications, hasLength(1));
      },
    );

    test('live acknowledgement persists across full restart', () async {
      final storage = _MemoryDurableStorage(
        payload: jsonEncode(
          const DesktopSessionSnapshotJsonCodec().encode(
            _runningSessionWithNotifications(),
          ),
        ),
      );
      final firstRuntime = _createDurableRuntime(
        durableStorage: storage,
        snapshotStore: _MemoryLegacySnapshotStore(),
      );
      final firstHostService = _lastCreatedHostService!;
      Session? firstSnapshot;
      firstRuntime.bind(
        onSnapshot: (session) => firstSnapshot = session,
        onWatchError: (error, stackTrace) {},
      );

      await firstRuntime.initialize();
      final acknowledgedNotificationId = firstSnapshot!.notifications
          .firstWhere((notification) => !notification.isAcknowledged)
          .id;

      final acknowledgedSession = firstHostService.acknowledgeNotification(
        sessionId: firstSnapshot!.id,
        notificationId: acknowledgedNotificationId,
      );
      _createPersistSessionMutation(
        _lastCreatedSessionStore!,
        attachedClientId: desktopSessionRuntimeAttachedClientId,
      )(acknowledgedSession);
      await _lastCreatedSessionStore!.waitForPendingPersistence();

      final restartedRuntime = _createDurableRuntime(
        durableStorage: storage,
        snapshotStore: _MemoryLegacySnapshotStore(),
      );
      Session? restartedSnapshot;
      restartedRuntime.bind(
        onSnapshot: (session) => restartedSnapshot = session,
        onWatchError: (error, stackTrace) {},
      );

      await restartedRuntime.initialize();

      expect(
        restartedSnapshot!.notifications
            .firstWhere(
              (notification) => notification.id == acknowledgedNotificationId,
            )
            .isAcknowledged,
        isTrue,
      );
      expect(
        restartedSnapshot!.notifications.where(
          (notification) => !notification.isAcknowledged,
        ),
        isNotEmpty,
      );
    });

    test(
      'streamed transition preserves notification ids and acknowledgement flags verbatim',
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

        // Record the initial notifications
        final initialNotifications = snapshot!.notifications;

        // Capture initial payload to prove distinct write
        final initialPayload = durableStorage.payload;
        expect(initialPayload, isNotNull);

        // Trigger a host-driven transition WITHOUT going through submitTurn.
        // This proves the watch path itself triggers persistence, not just
        // the explicit mutation handler.
        hostAdapter.advanceSessionToNextState();
        await sessionStore.waitForPendingPersistence();

        // Read back from durable storage
        final payloadAfter = durableStorage.payload;
        expect(payloadAfter, isNotNull);

        // Prove distinct write from the watch path
        expect(payloadAfter, isNot(equals(initialPayload)),
            reason: 'Watch path must trigger distinct write beyond initialize()');

        final decoded = const SessionSnapshotCodec().decode(
          jsonDecode(payloadAfter!),
          desktopClientId: desktopSessionRuntimeAttachedClientId,
        );

        // Verify notification ids are preserved verbatim through the watch path
        for (final original in initialNotifications) {
          final persisted = decoded.notifications.firstWhere(
            (n) => n.id == original.id,
            orElse: () => throw StateError(
              'Notification ${original.id} not found after persistence',
            ),
          );
          expect(persisted.isAcknowledged, original.isAcknowledged,
              reason: 'Notification ${original.id} isAcknowledged must be preserved');
          expect(persisted.turnId, original.turnId,
              reason: 'Notification ${original.id} turnId must be preserved');
          expect(persisted.transition, original.transition,
              reason: 'Notification ${original.id} transition must be preserved');
        }
      },
    );
  });
}

CommonCodeSessionStore? _lastCreatedSessionStore;
HostService? _lastCreatedHostService;

HostService _createDurableHostAdapter({
  required Object? durableStorage,
  required SessionSnapshotStore snapshotStore,
  DurableLocalHostDiagnosticsPort? diagnosticsPort,
}) {
  final hostAdapter = InMemoryHostAdapter();
  final hostService = hostAdapter as HostService;
  final sessionStore = DurableLocalSessionStore.fromPersistenceComponents(
    legacySnapshotStore: snapshotStore,
    durableStorage: durableStorage,
  );
  _lastCreatedSessionStore = sessionStore;
  final bootstrapPort = CommonCodeSessionBootstrapPortAdapter(
    sessionStore: sessionStore,
    host: CommonCodeSessionBootstrapHost(
      restoreSession: hostAdapter.restoreSession,
      createSession: hostAdapter.createSession,
      attachClient: hostAdapter.attachClient,
    ),
    diagnosticsPort: diagnosticsPort,
  );
  _lastCreatedHostService = hostService;
  return _BootstrappedHostService(
    hostService: hostService,
    bootstrapPort: bootstrapPort,
  );
}

HostDesktopSessionRuntime _createDurableRuntime({
  required Object? durableStorage,
  required SessionSnapshotStore snapshotStore,
  DurableLocalHostDiagnosticsPort? diagnosticsPort,
}) {
  final hostService = _createDurableHostAdapter(
    durableStorage: durableStorage,
    snapshotStore: snapshotStore,
    diagnosticsPort: diagnosticsPort,
  );
  return HostDesktopSessionRuntime(
    hostService: hostService,
    bootstrapPort: (hostService as _BootstrappedHostService).bootstrapPort,
    snapshotStore: snapshotStore,
    persistSessionMutation: _createPersistSessionMutation(
      _lastCreatedSessionStore!,
      attachedClientId: desktopSessionRuntimeAttachedClientId,
      diagnosticsPort: diagnosticsPort,
    ),
  );
}

void Function(Session session) _createPersistSessionMutation(
  CommonCodeSessionStore sessionStore, {
  required String attachedClientId,
  DurableLocalHostDiagnosticsPort? diagnosticsPort,
}) {
  return (Session session) {
    sessionStore
        .queueSessionPersistence(session, attachedClientId: attachedClientId)
        .catchError((Object error, StackTrace stackTrace) {
          diagnosticsPort?.emit(
            DurableLocalHostDiagnostic(
              DurableLocalHostDiagnosticCode.durableWriteFailed,
              error: error,
              stackTrace: stackTrace,
            ),
          );
        });
  };
}

final class _BootstrappedHostService implements HostService {
  const _BootstrappedHostService({
    required HostService hostService,
    required this.bootstrapPort,
  }) : _hostService = hostService;

  final HostService _hostService;
  final CommonCodeSessionBootstrapPort bootstrapPort;

  @override
  Session acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  }) => _hostService.acknowledgeNotification(
    sessionId: sessionId,
    notificationId: notificationId,
  );

  @override
  Session attachClient({required String sessionId, required Client client}) =>
      _hostService.attachClient(sessionId: sessionId, client: client);

  @override
  Session createSession({
    required String sessionId,
    required Host activeHost,
  }) =>
      _hostService.createSession(sessionId: sessionId, activeHost: activeHost);

  @override
  Session readSession(String sessionId) => _hostService.readSession(sessionId);

  @override
  Session restoreSession(Session session) =>
      _hostService.restoreSession(session);

  @override
  Session submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) => _hostService.submitTurn(
    sessionId: sessionId,
    client: client,
    submittedText: submittedText,
  );

  @override
  Stream<Session> watchSession(String sessionId) =>
      _hostService.watchSession(sessionId);
}

void expectSessionLike(Session actual, Session expected) {
  expect(actual.id, expected.id);
  expect(actual.activeHost.id, expected.activeHost.id);
  expect(
    actual.clients.map((client) => client.id).toList(growable: false),
    expected.clients.map((client) => client.id).toList(growable: false),
  );
  expect(
    actual.promptThread.turns.map(_turnSignature).toList(growable: false),
    expected.promptThread.turns.map(_turnSignature).toList(growable: false),
  );
  expect(
    actual.notifications.map(_notificationSignature).toList(growable: false),
    expected.notifications.map(_notificationSignature).toList(growable: false),
  );
}

Map<String, Object?> _turnSignature(Turn turn) {
  return <String, Object?>{
    'id': turn.id,
    'clientId': turn.clientId,
    'submittedText': turn.submittedText,
    'status': turn.status,
    'failureSummary': turn.failureSummary,
  };
}

Map<String, Object?> _notificationSignature(SessionNotification notification) {
  return <String, Object?>{
    'id': notification.id,
    'turnId': notification.turnId,
    'transition': notification.transition,
    'isAcknowledged': notification.isAcknowledged,
  };
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

Session _completedSessionWithNotifications() {
  return _runningSessionWithNotifications().completeActiveTurn();
}

Session _runningSessionWithNotifications() {
  final session = _baseSession()
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
  _MemoryLegacySnapshotStore({this.storedSession});

  final Session? storedSession;

  @override
  Future<Session?> readLatestSession({required String desktopClientId}) async {
    return storedSession;
  }

  @override
  Future<void> writeLatestSession(Session session) async {}
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
