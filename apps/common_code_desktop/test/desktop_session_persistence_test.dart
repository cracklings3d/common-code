import 'dart:async';
import 'dart:convert';

import 'package:common_code_desktop/src/desktop_session_controller.dart';
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
      'round-trips valid session data without storing input client field',
      () {
        final encoded = codec.encode(_runningRestoredSession());
        final decoded = codec.decode(
          encoded,
          desktopClientId: 'desktop-client',
        );

        expect(encoded.containsKey('inputClient'), isFalse);
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

  group('DesktopSessionController persistence behavior', () {
    test(
      'falls back to fresh bootstrap when no stored snapshot exists',
      () async {
        final controller = DesktopSessionController(
          hostService: createInMemoryHostService(),
          snapshotStore: _FakeSnapshotStore(),
        );

        await controller.initialize();

        expect(controller.state.status, DesktopSessionControllerStatus.data);
        expect(controller.state.snapshot, isNotNull);
        expect(controller.state.snapshot!.session.id, 'desktop-session');
        expect(
          controller.state.snapshot!.session.activeHost.id,
          'desktop-host',
        );
        expect(
          controller.state.snapshot!.session.clients.map((client) => client.id),
          ['desktop-client'],
        );
        expect(controller.state.snapshot!.session.activeTurn, isNull);
      },
    );

    test(
      'falls back to fresh bootstrap when stored snapshot is invalid',
      () async {
        final controller = DesktopSessionController(
          hostService: createInMemoryHostService(),
          snapshotStore: _FakeSnapshotStore(storedSession: null),
        );

        await controller.initialize();

        expect(controller.state.status, DesktopSessionControllerStatus.data);
        expect(controller.state.snapshot!.session.id, 'desktop-session');
      },
    );

    test('restores a valid stored snapshot and preserves identities', () async {
      final controller = DesktopSessionController(
        hostService: createInMemoryHostService(),
        snapshotStore: _FakeSnapshotStore(
          storedSession: _runningRestoredSession(),
        ),
      );

      await controller.initialize();

      final snapshot = controller.state.snapshot;
      expect(snapshot, isNotNull);
      expect(snapshot!.session.id, 'restored-session');
      expect(snapshot.session.activeHost.id, 'restored-host');
      expect(snapshot.session.clients.map((client) => client.id).toList(), [
        'desktop-client',
        'reviewer-client',
      ]);
      expect(
        snapshot.session.promptThread.turns
            .map((turn) => turn.submittedText)
            .toList(),
        ['First submitted turn', 'Second submitted turn'],
      );
      expect(snapshot.session.activeTurn?.status, TurnStatus.running);
      expect(snapshot.session.inputClient?.id, 'reviewer-client');
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
        final controller = DesktopSessionController(
          hostService: hostService,
          snapshotStore: _FakeSnapshotStore(
            storedSession: _queuedRestoredSession(),
          ),
        );

        await controller.initialize();

        expect(controller.state.snapshot, isNotNull);
        expect(
          controller.state.snapshot!.session.activeTurn?.status,
          TurnStatus.queued,
        );
        expect(
          controller.state.snapshot!.session.inputClient?.id,
          'reviewer-client',
        );
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
        final controller = DesktopSessionController(
          hostService: hostService,
          snapshotStore: _FakeSnapshotStore(
            storedSession: _runningRestoredSession(),
          ),
        );

        await controller.initialize();

        expect(controller.state.snapshot, isNotNull);
        expect(
          controller.state.snapshot!.session.activeTurn?.status,
          TurnStatus.running,
        );
        expect(
          controller.state.snapshot!.session.inputClient?.id,
          'reviewer-client',
        );
        expect(
          hostService.readSession('restored-session').activeTurn?.status,
          TurnStatus.running,
        );
      },
    );

    test('restored completed snapshot keeps input client at none', () async {
      final controller = DesktopSessionController(
        hostService: createInMemoryHostService(),
        snapshotStore: _FakeSnapshotStore(
          storedSession: _completedRestoredSession(),
        ),
      );

      await controller.initialize();

      expect(controller.state.snapshot!.session.activeTurn, isNull);
      expect(controller.state.snapshot!.session.inputClient, isNull);
    });

    test('restored failed snapshot keeps input client at none', () async {
      final controller = DesktopSessionController(
        hostService: createInMemoryHostService(),
        snapshotStore: _FakeSnapshotStore(
          storedSession: _failedRestoredSession(),
        ),
      );

      await controller.initialize();

      expect(controller.state.snapshot!.session.activeTurn, isNull);
      expect(controller.state.snapshot!.session.inputClient, isNull);
      expect(
        controller
            .state
            .snapshot!
            .session
            .promptThread
            .turns
            .single
            .failureSummary,
        'Restored failure.',
      );
    });

    test('watch writes each emitted snapshot back to storage', () async {
      final store = _FakeSnapshotStore();
      final controller = DesktopSessionController(
        hostService: createInMemoryHostService(),
        snapshotStore: store,
      );

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(store.writtenSessions, isNotEmpty);
      expect(store.writtenSessions.single.id, 'desktop-session');
    });

    test('persistence write failures are non-fatal to live state', () async {
      final controller = DesktopSessionController(
        hostService: createInMemoryHostService(),
        snapshotStore: _ThrowingSnapshotStore(),
      );

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, DesktopSessionControllerStatus.data);
      expect(controller.state.snapshot!.session.id, 'desktop-session');
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
