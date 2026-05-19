import 'dart:convert';

import 'package:common_code_desktop/src/desktop_session_runtime.dart';
import 'package:common_code_desktop/src/desktop_session_snapshot_codec.dart';
import 'package:common_code_desktop/src/desktop_session_snapshot_store.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_core/host_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopSessionSnapshotJsonCodec', () {
    const codec = DesktopSessionSnapshotJsonCodec();

    test(
      'round-trips schema 2 notifications without storing input client field',
      () {
        final encoded = codec.encode(_runningRestoredSession());
        final decoded = codec.decode(
          encoded,
          desktopClientId: 'desktop-client',
        );

        expect(encoded.containsKey('inputClient'), isFalse);
        expect(encoded['schemaVersion'], 2);
        expect(decoded.id, 'restored-session');
        expect(decoded.activeHost.id, 'restored-host');
        expect(decoded.clients.map((client) => client.id).toList(), [
          'desktop-client',
          'reviewer-client',
        ]);
        expect(
          decoded.promptThread.turns.map((turn) => turn.submittedText).toList(),
          ['First submitted turn', 'Second submitted turn'],
        );
        expect(decoded.promptThread.turns.map((turn) => turn.status).toList(), [
          TurnStatus.completed,
          TurnStatus.running,
        ]);
        expect(decoded.activeTurn?.id, 'turn-2');
        expect(decoded.inputClient?.id, 'reviewer-client');
        expect(decoded.notifications, _runningRestoredSession().notifications);
      },
    );

    test('preserves failure summary for failed turns', () {
      final decoded = codec.decode(
        codec.encode(_failedRestoredSession()),
        desktopClientId: 'desktop-client',
      );

      expect(decoded.activeTurn, isNull);
      expect(decoded.inputClient, isNull);
      expect(
        decoded.promptThread.turns.single.failureSummary,
        'Restored failure.',
      );
    });

    test('rejects unknown schema versions', () {
      expect(
        () => codec.decode(<String, Object?>{
          'schemaVersion': 99,
          'sessionId': 'restored-session',
          'activeHostId': 'restored-host',
          'clientIds': ['desktop-client'],
          'turns': <Object?>[],
        }, desktopClientId: 'desktop-client'),
        throwsA(isA<FormatException>()),
      );
    });

    test('schema 1 restore yields empty notifications', () {
      final decoded = codec.decode(<String, Object?>{
        'schemaVersion': 1,
        'sessionId': 'restored-session',
        'activeHostId': 'restored-host',
        'clientIds': ['desktop-client', 'reviewer-client'],
        'turns': <Map<String, Object?>>[
          {
            'id': 'turn-1',
            'clientId': 'reviewer-client',
            'submittedText': 'First submitted turn',
            'status': 'completed',
            'failureSummary': null,
          },
          {
            'id': 'turn-2',
            'clientId': 'reviewer-client',
            'submittedText': 'Second submitted turn',
            'status': 'running',
            'failureSummary': null,
          },
        ],
      }, desktopClientId: 'desktop-client');

      expect(decoded.notifications, isEmpty);
      expect(decoded.activeTurn?.status, TurnStatus.running);
    });

    test(
      'schema 1 restore does not synthesize notifications from turn state',
      () {
        final decoded = codec.decode(<String, Object?>{
          'schemaVersion': 1,
          'sessionId': 'restored-session',
          'activeHostId': 'restored-host',
          'clientIds': ['desktop-client', 'reviewer-client'],
          'turns': <Map<String, Object?>>[
            {
              'id': 'turn-1',
              'clientId': 'reviewer-client',
              'submittedText': 'Failed submitted turn',
              'status': 'failed',
              'failureSummary': 'Restored failure.',
            },
          ],
        }, desktopClientId: 'desktop-client');

        expect(decoded.notifications, isEmpty);
      },
    );
  });

  group('SharedPreferencesDesktopSessionSnapshotStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('returns null when no snapshot exists', () async {
      final store = SharedPreferencesDesktopSessionSnapshotStore();

      expect(
        await store.readLatestSession(desktopClientId: 'desktop-client'),
        isNull,
      );
    });

    test('returns null when stored JSON is malformed', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SharedPreferencesDesktopSessionSnapshotStore.storageKey: '{bad-json',
      });
      final store = SharedPreferencesDesktopSessionSnapshotStore();

      expect(
        await store.readLatestSession(desktopClientId: 'desktop-client'),
        isNull,
      );
    });

    test('returns null when stored JSON is semantically invalid', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SharedPreferencesDesktopSessionSnapshotStore.storageKey: jsonEncode(
          <String, Object?>{
            'schemaVersion': 1,
            'sessionId': 'restored-session',
            'activeHostId': 'restored-host',
            'clientIds': <String>['reviewer-client'],
            'turns': <Object?>[],
          },
        ),
      });
      final store = SharedPreferencesDesktopSessionSnapshotStore();

      expect(
        await store.readLatestSession(desktopClientId: 'desktop-client'),
        isNull,
      );
    });

    test('writes and reads a valid snapshot', () async {
      final store = SharedPreferencesDesktopSessionSnapshotStore();

      await store.writeLatestSession(_runningRestoredSession());
      final restored = await store.readLatestSession(
        desktopClientId: 'desktop-client',
      );

      expect(restored, isNotNull);
      expect(restored!.id, 'restored-session');
      expect(restored.activeHost.id, 'restored-host');
      expect(restored.activeTurn?.status, TurnStatus.running);
    });
  });

  group('HostDesktopSessionRuntime persistence behavior', () {
    test(
      'falls back to fresh bootstrap when no stored snapshot exists',
      () async {
        final runtime = HostDesktopSessionRuntime(
          hostService: createInMemoryHostService(),
          snapshotStore: _FakeSnapshotStore(),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        expect(snapshot, isNotNull);
        expect(snapshot!.id, 'desktop-session');
        expect(snapshot!.activeHost.id, 'desktop-host');
        expect(snapshot!.clients.map((client) => client.id), [
          'desktop-client',
        ]);
        expect(snapshot!.activeTurn, isNull);
      },
    );

    test(
      'falls back to fresh bootstrap when stored snapshot is invalid',
      () async {
        final runtime = HostDesktopSessionRuntime(
          hostService: createInMemoryHostService(),
          snapshotStore: _FakeSnapshotStore(storedSession: null),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        expect(snapshot, isNotNull);
        expect(snapshot!.id, 'desktop-session');
      },
    );

    test('restores a valid stored snapshot and preserves identities', () async {
      final runtime = HostDesktopSessionRuntime(
        hostService: createInMemoryHostService(),
        snapshotStore: _FakeSnapshotStore(
          storedSession: _runningRestoredSession(),
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
      expect(snapshot!.activeHost.id, 'restored-host');
      expect(snapshot!.clients.map((client) => client.id).toList(), [
        'desktop-client',
        'reviewer-client',
      ]);
      expect(
        snapshot!.promptThread.turns.map((turn) => turn.submittedText).toList(),
        ['First submitted turn', 'Second submitted turn'],
      );
      expect(snapshot!.activeTurn?.status, TurnStatus.running);
      expect(snapshot!.inputClient?.id, 'reviewer-client');
    });

    test(
      'restored queued snapshot remains frozen as last-known state',
      () async {
        final hostService = createInMemoryHostService(
          simulationPolicy: const HostExecutionSimulationPolicy(
            queuedToRunningDelay: Duration.zero,
            runningToTerminalDelay: Duration.zero,
          ),
        );
        final runtime = HostDesktopSessionRuntime(
          hostService: hostService,
          snapshotStore: _FakeSnapshotStore(
            storedSession: _queuedRestoredSession(),
          ),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        expect(snapshot, isNotNull);
        expect(snapshot!.activeTurn?.status, TurnStatus.queued);
        expect(snapshot!.inputClient?.id, 'reviewer-client');
        expect(snapshot!.notifications, isEmpty);
        expect(
          hostService.readSession('restored-session').activeTurn?.status,
          TurnStatus.queued,
        );
      },
    );

    test(
      'restored running snapshot remains frozen as last-known state',
      () async {
        final hostService = createInMemoryHostService(
          simulationPolicy: const HostExecutionSimulationPolicy(
            queuedToRunningDelay: Duration.zero,
            runningToTerminalDelay: Duration.zero,
          ),
        );
        final runtime = HostDesktopSessionRuntime(
          hostService: hostService,
          snapshotStore: _FakeSnapshotStore(
            storedSession: _runningRestoredSession(),
          ),
        );
        Session? snapshot;
        runtime.bind(
          onSnapshot: (session) => snapshot = session,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        expect(snapshot, isNotNull);
        expect(snapshot!.activeTurn?.status, TurnStatus.running);
        expect(snapshot!.inputClient?.id, 'reviewer-client');
        expect(snapshot!.notifications, _runningRestoredSession().notifications);
        expect(
          hostService.readSession('restored-session').activeTurn?.status,
          TurnStatus.running,
        );
      },
    );

    test('restored completed snapshot keeps input client at none', () async {
      final runtime = HostDesktopSessionRuntime(
        hostService: createInMemoryHostService(),
        snapshotStore: _FakeSnapshotStore(
          storedSession: _completedRestoredSession(),
        ),
      );
      Session? snapshot;
      runtime.bind(
        onSnapshot: (session) => snapshot = session,
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();

      expect(snapshot!.activeTurn, isNull);
      expect(snapshot!.inputClient, isNull);
      expect(snapshot!.notifications, _completedRestoredSession().notifications);
    });

    test('restored failed snapshot keeps input client at none', () async {
      final runtime = HostDesktopSessionRuntime(
        hostService: createInMemoryHostService(),
        snapshotStore: _FakeSnapshotStore(
          storedSession: _failedRestoredSession(),
        ),
      );
      Session? snapshot;
      runtime.bind(
        onSnapshot: (session) => snapshot = session,
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();

      expect(snapshot!.activeTurn, isNull);
      expect(snapshot!.inputClient, isNull);
      expect(snapshot!.notifications, _failedRestoredSession().notifications);
      expect(
        snapshot!.promptThread.turns.single.failureSummary,
        'Restored failure.',
      );
    });

    test('watch writes each emitted snapshot back to storage', () async {
      final store = _FakeSnapshotStore();
      final runtime = HostDesktopSessionRuntime(
        hostService: createInMemoryHostService(),
        snapshotStore: store,
      );
      runtime.bind(
        onSnapshot: (session) {},
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(store.writtenSessions, isNotEmpty);
      expect(store.writtenSessions.single.id, 'desktop-session');
    });

    test('persistence write failures are non-fatal to live state', () async {
      final runtime = HostDesktopSessionRuntime(
        hostService: createInMemoryHostService(),
        snapshotStore: _ThrowingSnapshotStore(),
      );
      Session? snapshot;
      runtime.bind(
        onSnapshot: (session) => snapshot = session,
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(snapshot, isNotNull);
      expect(snapshot!.id, 'desktop-session');
    });
  });
}

Session _baseRestoredSession() {
  const desktopClient = Client(id: 'desktop-client');
  const reviewerClient = Client(id: 'reviewer-client');

  return Session(
    id: 'restored-session',
    activeHost: const Host(id: 'restored-host'),
  ).attachClient(desktopClient).attachClient(reviewerClient);
}

Session _queuedRestoredSession() {
  const reviewerClient = Client(id: 'reviewer-client');

  return _baseRestoredSession().startTurn(
    turnId: 'turn-1',
    client: reviewerClient,
    submittedText: 'Queued submitted turn',
  );
}

Session _runningRestoredSession() {
  const reviewerClient = Client(id: 'reviewer-client');

  return _baseRestoredSession()
      .startTurn(
        turnId: 'turn-1',
        client: reviewerClient,
        submittedText: 'First submitted turn',
      )
      .advanceActiveTurnToRunning()
      .completeActiveTurn()
      .startTurn(
        turnId: 'turn-2',
        client: reviewerClient,
        submittedText: 'Second submitted turn',
      )
      .advanceActiveTurnToRunning();
}

Session _completedRestoredSession() {
  const reviewerClient = Client(id: 'reviewer-client');

  return _baseRestoredSession()
      .startTurn(
        turnId: 'turn-1',
        client: reviewerClient,
        submittedText: 'Completed submitted turn',
      )
      .advanceActiveTurnToRunning()
      .completeActiveTurn();
}

Session _failedRestoredSession() {
  const reviewerClient = Client(id: 'reviewer-client');

  return _baseRestoredSession()
      .startTurn(
        turnId: 'turn-1',
        client: reviewerClient,
        submittedText: 'Failed submitted turn',
      )
      .advanceActiveTurnToRunning()
      .failActiveTurn(failureSummary: 'Restored failure.');
}

final class _FakeSnapshotStore implements DesktopSessionSnapshotStore {
  _FakeSnapshotStore({this.storedSession});

  final Session? storedSession;
  final List<Session> writtenSessions = <Session>[];

  @override
  Future<Session?> readLatestSession({required String desktopClientId}) async {
    return storedSession;
  }

  @override
  Future<void> writeLatestSession(Session session) async {
    writtenSessions.add(session);
  }
}

final class _ThrowingSnapshotStore implements DesktopSessionSnapshotStore {
  @override
  Future<Session?> readLatestSession({required String desktopClientId}) async {
    return null;
  }

  @override
  Future<void> writeLatestSession(Session session) async {
    throw StateError('persist failed');
  }
}
