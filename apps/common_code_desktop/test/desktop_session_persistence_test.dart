import 'dart:convert';

import 'package:common_code_desktop/src/desktop_session_runtime.dart';
import 'package:common_code_desktop/src/durable_local_host_service.dart';
import 'package:common_code_domain/common_code_domain.dart';
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
      await _lastCreatedDurableService!.flushPendingWrites();

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
        diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
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
        diagnosticsSink: (diagnostic) => diagnostics.add(diagnostic.code),
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
      final acknowledgedNotificationId = firstSnapshot!.notifications.firstWhere(
        (notification) => !notification.isAcknowledged,
      ).id;

      final acknowledgedSession = firstHostService.acknowledgeNotification(
        sessionId: firstSnapshot!.id,
        notificationId: acknowledgedNotificationId,
      );
      _lastCreatedDurableService!.queueSessionPersistence(acknowledgedSession);
      await _lastCreatedDurableService!.flushPendingWrites();

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
        restartedSnapshot!.notifications.firstWhere(
          (notification) => notification.id == acknowledgedNotificationId,
        ).isAcknowledged,
        isTrue,
      );
      expect(
        restartedSnapshot!.notifications.where(
          (notification) => !notification.isAcknowledged,
        ),
        isNotEmpty,
      );
    });
  });
}

SessionSnapshotStore? _lastCreatedSnapshotStore;
DurableLocalHostService? _lastCreatedDurableService;
HostService? _lastCreatedHostService;

HostService _createDurableHostAdapter({
  required Object? durableStorage,
  required SessionSnapshotStore snapshotStore,
  DurableLocalHostDiagnosticsSink? diagnosticsSink,
}) {
  final hostAdapter = InMemoryHostAdapter();
  final hostService = hostAdapter as HostService;
  final durableService = DurableLocalHostService.withAdapter(
    hostAdapter: hostAdapter,
    sessionStore: DurableLocalSessionStore.fromPersistenceComponents(
      legacySnapshotStore: snapshotStore,
      durableStorage: durableStorage,
    ),
    diagnosticsSink: diagnosticsSink,
  );
  _lastCreatedSnapshotStore = snapshotStore;
  _lastCreatedDurableService = durableService;
  _lastCreatedHostService = hostService;
  return hostService;
}

HostDesktopSessionRuntime _createDurableRuntime({
  required Object? durableStorage,
  required SessionSnapshotStore snapshotStore,
  DurableLocalHostDiagnosticsSink? diagnosticsSink,
}) {
  final hostService = _createDurableHostAdapter(
    durableStorage: durableStorage,
    snapshotStore: snapshotStore,
    diagnosticsSink: diagnosticsSink,
  );
  return HostDesktopSessionRuntime(
    hostService: hostService,
    bootstrapPort: _lastCreatedDurableService,
    snapshotStore: snapshotStore,
    persistSessionMutation: _lastCreatedDurableService!.queueSessionPersistence,
  );
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
