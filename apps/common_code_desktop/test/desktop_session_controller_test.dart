import 'dart:async';

import 'package:common_code_desktop/src/desktop_session_controller.dart';
import 'package:common_code_desktop/src/desktop_session_snapshot_store.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_core/host_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopSessionController', () {
    test('exposes loading then data on initialize', () async {
      final controller = DesktopSessionController(
        hostService: createInMemoryHostService(),
        snapshotStore: _MemorySnapshotStore(),
      );

      expect(controller.state.status, DesktopSessionControllerStatus.loading);

      await controller.initialize();

      expect(controller.state.status, DesktopSessionControllerStatus.data);
      expect(controller.state.snapshot, isNotNull);
      expect(controller.state.snapshot!.session.id, 'desktop-session');
    });

    test(
      'refresh cancels the prior watch before starting replacement watch',
      () async {
        final hostService = _TrackingHostService();
        final controller = DesktopSessionController(
          hostService: hostService,
          snapshotStore: _MemorySnapshotStore(),
        );

        await controller.initialize();
        expect(hostService.watchStarts, 1);
        expect(hostService.watchCancels, 0);

        await controller.refresh();

        expect(hostService.watchCancels, 1);
        expect(hostService.watchStarts, 2);
        expect(hostService.concurrentWatchViolation, isFalse);
        expect(controller.state.status, DesktopSessionControllerStatus.data);
      },
    );

    test('overlapping refresh calls serialize watch restarts', () async {
      final hostService = _DelayedCancelTrackingHostService();
      final controller = DesktopSessionController(
        hostService: hostService,
        snapshotStore: _MemorySnapshotStore(),
      );

      await controller.initialize();
      expect(hostService.watchStarts, 1);

      final firstRefresh = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      await hostService.waitForCancellationToStart();

      final secondRefresh = controller.refresh();
      await Future<void>.delayed(Duration.zero);

      expect(hostService.watchStarts, 1);
      expect(hostService.concurrentWatchViolation, isFalse);

      hostService.allowCancellationToFinish();
      await Future.wait([firstRefresh, secondRefresh]);

      expect(hostService.watchCancels, 2);
      expect(hostService.watchStarts, 3);
      expect(hostService.concurrentWatchViolation, isFalse);
      expect(controller.state.status, DesktopSessionControllerStatus.data);
    });

    test('submit toggles submission state and clears it on success', () async {
      final hostService = _SubmitCompletesOnDemandHostService();
      final controller = DesktopSessionController(
        hostService: hostService,
        snapshotStore: _MemorySnapshotStore(),
      );

      await controller.initialize();

      final submitFuture = controller.submitTurn(submittedText: 'queued turn');

      expect(controller.state.isSubmitting, isTrue);

      await Future<void>.delayed(Duration.zero);
      expect(
        controller.state.snapshot!.session.promptThread.turns.last.status,
        TurnStatus.queued,
      );

      hostService.emitRunningLifecycle();
      await submitFuture;
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.isSubmitting, isFalse);
      expect(controller.state.status, DesktopSessionControllerStatus.data);
      expect(
        controller.state.snapshot!.session.promptThread.turns.last.status,
        TurnStatus.completed,
      );
    });

    test(
      'submit failure surfaces as renderable error state and clears flag',
      () async {
        final controller = DesktopSessionController(
          hostService: _FailingSubmitHostService(),
          snapshotStore: _MemorySnapshotStore(),
        );

        await controller.initialize();

        await expectLater(
          controller.submitTurn(submittedText: 'bad turn'),
          throwsA(isA<StateError>()),
        );

        expect(controller.state.isSubmitting, isFalse);
        expect(controller.state.status, DesktopSessionControllerStatus.error);
        expect(controller.state.message, contains('submit failed'));
      },
    );

    test(
      'watch stream drives queued running completed failed state updates',
      () async {
        final hostService = _TrackingHostService();
        final controller = DesktopSessionController(
          hostService: hostService,
          snapshotStore: _MemorySnapshotStore(),
        );

        await controller.initialize();

        hostService.emit(
          _sessionWithTurn(
            Turn.queued(
              id: 'turn-1',
              clientId: 'desktop-client',
              submittedText: 'queued turn',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          controller.state.snapshot!.session.activeTurn!.status,
          TurnStatus.queued,
        );

        hostService.emit(
          _sessionWithTurn(
            Turn.running(
              id: 'turn-1',
              clientId: 'desktop-client',
              submittedText: 'queued turn',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          controller.state.snapshot!.session.activeTurn!.status,
          TurnStatus.running,
        );

        hostService.emit(
          _sessionWithTurn(
            Turn.completed(
              id: 'turn-1',
              clientId: 'desktop-client',
              submittedText: 'queued turn',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.snapshot!.session.activeTurn, isNull);
        expect(
          controller.state.snapshot!.session.promptThread.turns.single.status,
          TurnStatus.completed,
        );

        hostService.emit(
          _sessionWithTurn(
            Turn.failed(
              id: 'turn-2',
              clientId: 'desktop-client',
              submittedText: 'failed turn',
              failureSummary: 'Simulated host failure.',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.snapshot!.session.activeTurn, isNull);
        expect(
          controller.state.snapshot!.session.promptThread.turns.single.status,
          TurnStatus.failed,
        );
        expect(
          controller
              .state
              .snapshot!
              .session
              .promptThread
              .turns
              .single
              .failureSummary,
          'Simulated host failure.',
        );
      },
    );

    test('watch errors surface as controller error state', () async {
      final controller = DesktopSessionController(
        hostService: _WatchErrorHostService(),
        snapshotStore: _MemorySnapshotStore(),
      );

      await controller.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.status, DesktopSessionControllerStatus.error);
      expect(controller.state.message, contains('watch boom'));
    });
  });
}

Session _bootstrapSession() {
  return Session(
    id: 'desktop-session',
    activeHost: const Host(id: 'desktop-host'),
  ).attachClient(const Client(id: 'desktop-client'));
}

Session _sessionWithTurn(Turn turn) {
  return Session(
    id: 'desktop-session',
    activeHost: const Host(id: 'desktop-host'),
    clients: const [Client(id: 'desktop-client')],
    promptThread: PromptThread(turns: [turn]),
  );
}

final class _MemorySnapshotStore implements DesktopSessionSnapshotStore {
  Session? storedSession;

  @override
  Future<Session?> readLatestSession({required String desktopClientId}) async {
    return storedSession;
  }

  @override
  Future<void> writeLatestSession(Session session) async {
    storedSession = session;
  }
}

final class _TrackingHostService implements HostService {
  final Map<String, Session> _sessions = <String, Session>{};
  final Map<String, StreamController<Session>> _controllers =
      <String, StreamController<Session>>{};

  int watchStarts = 0;
  int watchCancels = 0;
  bool concurrentWatchViolation = false;

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

  void emit(Session session) {
    _sessions[session.id] = session;
    _controllers[session.id]?.add(session);
  }

  @override
  Session readSession(String sessionId) => _sessions[sessionId]!;

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

final class _SubmitCompletesOnDemandHostService extends _TrackingHostService {
  @override
  Session submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) {
    return super.submitTurn(
      sessionId: sessionId,
      client: client,
      submittedText: submittedText,
    );
  }

  void emitRunningLifecycle() {
    emit(
      _sessionWithTurn(
        Turn.running(
          id: 'turn-1',
          clientId: 'desktop-client',
          submittedText: 'queued turn',
        ),
      ),
    );
    emit(
      _sessionWithTurn(
        Turn.completed(
          id: 'turn-1',
          clientId: 'desktop-client',
          submittedText: 'queued turn',
        ),
      ),
    );
  }
}

final class _DelayedCancelTrackingHostService extends _TrackingHostService {
  Completer<void>? _cancelCompleter;
  Completer<void>? _cancelStartedCompleter;
  bool _shouldDelayNextCancellation = true;

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
      onCancel: () async {
        watchCancels += 1;
        if (_shouldDelayNextCancellation) {
          _shouldDelayNextCancellation = false;
          final cancelCompleter = Completer<void>();
          final cancelStartedCompleter = Completer<void>();
          _cancelCompleter = cancelCompleter;
          _cancelStartedCompleter = cancelStartedCompleter;
          cancelStartedCompleter.complete();
          await cancelCompleter.future;
        }
        _controllers.remove(sessionId);
      },
    );
    return controller.stream;
  }

  Future<void> waitForCancellationToStart() async {
    final cancelStartedCompleter = _cancelStartedCompleter;
    if (cancelStartedCompleter == null) {
      throw StateError('No cancellation is in progress.');
    }

    await cancelStartedCompleter.future;
  }

  void allowCancellationToFinish() {
    final cancelCompleter = _cancelCompleter;
    if (cancelCompleter == null || cancelCompleter.isCompleted) {
      return;
    }

    cancelCompleter.complete();
  }
}

final class _FailingSubmitHostService extends _TrackingHostService {
  @override
  Session submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) {
    throw StateError('submit failed');
  }
}

final class _WatchErrorHostService extends _TrackingHostService {
  @override
  Stream<Session> watchSession(String sessionId) {
    return Stream<Session>.error(StateError('watch boom'));
  }
}
