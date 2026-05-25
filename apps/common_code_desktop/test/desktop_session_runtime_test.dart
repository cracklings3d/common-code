import 'dart:async';
import 'dart:convert';

import 'package:common_code_desktop/src/desktop_session_runtime.dart'
    hide
        desktopSessionRuntimeAttachedClientId,
        desktopSessionRuntimeDefaultSessionId;
import 'package:common_code_desktop/src/desktop_session_app_edge_composition.dart';
import 'package:common_code_desktop/src/durable_local_host_service.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:common_code_application/common_code_application.dart';
import 'package:host_core/host_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:common_code_desktop/src/desktop_session_runtime_constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('HostDesktopSessionRuntime', () {
    test('initialize uses the durable local host default path', () async {
      final diagnostics = <DurableLocalHostDiagnosticCode>[];
      final runtime = HostDesktopSessionRuntime(
        snapshotStore: _MemoryLegacySnapshotStore(),
        diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
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
        final runtime = HostDesktopSessionRuntime(
          hostServiceFactory: () =>
              DurableLocalHostService(durableStorage: durableStorage),
          snapshotStore: snapshotStore,
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
        final runtime = HostDesktopSessionRuntime(
          hostServiceFactory: () =>
              DurableLocalHostService(durableStorage: durableStorage),
          snapshotStore: snapshotStore,
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
        final runtime = HostDesktopSessionRuntime(
          hostServiceFactory: () =>
              DurableLocalHostService(durableStorage: durableStorage),
          snapshotStore: _MemoryLegacySnapshotStore(),
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
        final runtime = HostDesktopSessionRuntime(
          hostServiceFactory: () =>
              DurableLocalHostService(durableStorage: durableStorage),
          snapshotStore: _MemoryLegacySnapshotStore(
            storedSession: _completedSession(),
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
        final runtime = HostDesktopSessionRuntime(
          hostServiceFactory: () => DurableLocalHostService(
            durableStorage: _MemoryDurableStorage(
              writeError: StateError('write failed'),
            ),
            legacySnapshotStore: _MemoryLegacySnapshotStore(
              storedSession: _completedSession(),
            ),
            diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
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
      final runtime = HostDesktopSessionRuntime(
        hostServiceFactory: () => DurableLocalHostService(
          durableStorage: durableStorage,
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
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
      'refresh cancels the prior watch before starting replacement watch',
      () async {
        final hostService = _TrackingHostService();
        final runtime = HostDesktopSessionRuntime(
          hostService: hostService,
          snapshotStore: _MemoryLegacySnapshotStore(),
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
        final durableStorage = _MemoryDurableStorage(
          payload: jsonEncode(
            const SessionSnapshotCodec().encode(_queuedSession()),
          ),
        );
        final runtime = HostDesktopSessionRuntime(
          hostServiceFactory: () => _RejectingRestoreDurableLocalHostService(
            durableStorage: _MemoryDurableStorage(
              payload: jsonEncode(
                const SessionSnapshotCodec().encode(_queuedSession()),
              ),
            ),
            legacySnapshotStore: _MemoryLegacySnapshotStore(
              storedSession: _completedSession(),
            ),
            diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
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
        final hostService = DurableLocalHostService(
          durableStorage: storage,
          legacySnapshotStore: _MemoryLegacySnapshotStore(),
          diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
        );
        final runtime = HostDesktopSessionRuntime(hostService: hostService);
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();
        storage.writeError = StateError('write failed');

        await runtime.submitTurn(submittedText: 'persist me');
        await hostService.flushPendingWrites();

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
      'app-edge driver returns bound identity and attached client',
      () async {
        final driver = HostCoreDesktopSessionDriver(
          hostService: _TrackingHostService(),
          snapshotStore: _MemoryLegacySnapshotStore(),
        );

        final binding = await driver.ensureSession();

        expect(binding.sessionId, desktopSessionRuntimeDefaultSessionId);
        expect(
          binding.identity,
          const Identity(id: desktopSessionRuntimeIdentityId),
        );
        expect(binding.attachedClientId, desktopSessionRuntimeAttachedClientId);
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

final class _MemoryDurableStorage implements DurableSessionStore {
  _MemoryDurableStorage({
    this.payload,
    this.legacySeedEnabled = true,
    this.readError,
    this.writeError,
  });

  String? payload;
  bool legacySeedEnabled;
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

final class _RejectingRestoreDurableLocalHostService
    extends DurableLocalHostService {
  _RejectingRestoreDurableLocalHostService({
    required super.legacySnapshotStore,
    required super.durableStorage,
    super.diagnosticsSink,
  });

  @override
  Session restoreBootstrappedSession(Session session) {
    throw StateError('restore rejected');
  }
}
