import 'dart:async';

import 'package:common_code_desktop/src/desktop_session_runtime.dart';
import 'package:common_code_desktop/src/desktop_session_snapshot_store.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_core/host_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HostDesktopSessionRuntime', () {
    test('fresh bootstrap when no snapshot is restored', () async {
      final hostService = _TrackingHostService();
      final store = _MemorySnapshotStore();
      final runtime = HostDesktopSessionRuntime(
        hostService: hostService,
        snapshotStore: store,
      );
      final snapshots = <Session>[];
      runtime.bind(
        onSnapshot: snapshots.add,
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();

      expect(snapshots.single.id, 'desktop-session');
      expect(hostService.createdSessionIds, ['desktop-session']);
      expect(hostService.attachedClientIds, ['desktop-client']);
    });

    test('restore path when a valid snapshot exists', () async {
      final hostService = _TrackingHostService();
      final runtime = HostDesktopSessionRuntime(
        hostService: hostService,
        snapshotStore: _MemorySnapshotStore(
          storedSession: _runningRestoredSession(),
        ),
      );
      final snapshots = <Session>[];
      runtime.bind(
        onSnapshot: snapshots.add,
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();

      expect(hostService.restoredSessionIds, ['restored-session']);
      expect(snapshots.single.id, 'restored-session');
      expect(snapshots.single.activeTurn?.status, TurnStatus.running);
    });

    test(
      'fallback bootstrap when restore data is invalid or restore fails',
      () async {
        final hostService = _FailingRestoreHostService();
        final runtime = HostDesktopSessionRuntime(
          hostService: hostService,
          snapshotStore: _MemorySnapshotStore(
            storedSession: _runningRestoredSession(),
          ),
        );
        final snapshots = <Session>[];
        runtime.bind(
          onSnapshot: snapshots.add,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();

        expect(hostService.restoreAttempts, 1);
        expect(hostService.createdSessionIds, ['desktop-session']);
        expect(snapshots.single.id, 'desktop-session');
      },
    );

    test(
      'initialize waits for the first snapshot for the active watch cycle',
      () async {
        final hostService = _ManualWatchHostService();
        final runtime = HostDesktopSessionRuntime(
          hostService: hostService,
          snapshotStore: _MemorySnapshotStore(),
        );
        runtime.bind(
          onSnapshot: (session) {},
          onWatchError: (error, stackTrace) {},
        );

        var settled = false;
        final initializeFuture = runtime.initialize().then(
          (value) => settled = true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(settled, isFalse);

        hostService.emit(_bootstrapSession());
        await initializeFuture;

        expect(settled, isTrue);
      },
    );

    test(
      'initialize settles on first watch error for the active watch cycle',
      () async {
        final hostService = _ManualWatchHostService();
        final runtime = HostDesktopSessionRuntime(
          hostService: hostService,
          snapshotStore: _MemorySnapshotStore(),
        );
        final errors = <Object>[];
        runtime.bind(
          onSnapshot: (session) {},
          onWatchError: (error, stackTrace) => errors.add(error),
        );

        final initializeFuture = runtime.initialize();
        await Future<void>.delayed(Duration.zero);

        hostService.emitError(StateError('watch boom'));
        await initializeFuture;

        expect(errors.single.toString(), contains('watch boom'));
      },
    );

    test(
      'refresh cancels the prior watch before starting replacement watch',
      () async {
        final hostService = _TrackingHostService();
        final runtime = HostDesktopSessionRuntime(
          hostService: hostService,
          snapshotStore: _MemorySnapshotStore(),
        );
        runtime.bind(
          onSnapshot: (session) {},
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();
        expect(hostService.watchStarts, 1);
        expect(hostService.watchCancels, 0);

        await runtime.refresh();

        expect(hostService.watchCancels, 1);
        expect(hostService.watchStarts, 2);
        expect(hostService.concurrentWatchViolation, isFalse);
      },
    );

    test('overlapping refresh calls serialize watch restarts', () async {
      final hostService = _DelayedCancelTrackingHostService();
      final runtime = HostDesktopSessionRuntime(
        hostService: hostService,
        snapshotStore: _MemorySnapshotStore(),
      );
      runtime.bind(
        onSnapshot: (session) {},
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();
      expect(hostService.watchStarts, 1);

      final firstRefresh = runtime.refresh();
      await Future<void>.delayed(Duration.zero);
      await hostService.waitForCancellationToStart();

      final secondRefresh = runtime.refresh();
      await Future<void>.delayed(Duration.zero);

      expect(hostService.watchStarts, 1);
      expect(hostService.concurrentWatchViolation, isFalse);

      hostService.allowCancellationToFinish();
      await Future.wait([firstRefresh, secondRefresh]);

      expect(hostService.watchCancels, 2);
      expect(hostService.watchStarts, 3);
      expect(hostService.concurrentWatchViolation, isFalse);
    });

    test('stale watch events are suppressed after watch replacement', () async {
      final hostService = _ReplaceableWatchHostService();
      final runtime = HostDesktopSessionRuntime(
        hostService: hostService,
        snapshotStore: _MemorySnapshotStore(),
      );
      final snapshots = <Session>[];
      runtime.bind(
        onSnapshot: snapshots.add,
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();
      expect(snapshots.single.id, 'desktop-session');

      final staleSession = _bootstrapSession().startTurn(
        turnId: 'turn-stale',
        client: const Client(id: 'desktop-client'),
        submittedText: 'stale update',
      );
      final refreshFuture = runtime.refresh();
      await Future<void>.delayed(Duration.zero);

      hostService.emitFromCancelledWatch(staleSession);
      hostService.emitCurrent(_bootstrapSession());
      await refreshFuture;

      expect(snapshots.length, greaterThanOrEqualTo(2));
      expect(
        snapshots.any((session) => session.activeTurn?.id == 'turn-stale'),
        isFalse,
      );
    });

    test('stale watch events are suppressed after runtime disposal', () async {
      final hostService = _ReplaceableWatchHostService();
      final runtime = HostDesktopSessionRuntime(
        hostService: hostService,
        snapshotStore: _MemorySnapshotStore(),
      );
      final snapshots = <Session>[];
      runtime.bind(
        onSnapshot: snapshots.add,
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();
      await runtime.dispose();

      hostService.emitFromCancelledWatch(
        _bootstrapSession().startTurn(
          turnId: 'turn-late',
          client: const Client(id: 'desktop-client'),
          submittedText: 'late update',
        ),
      );

      expect(snapshots.length, 1);
    });

    test('submit delegates against the attached desktop client', () async {
      final hostService = _TrackingHostService();
      final runtime = HostDesktopSessionRuntime(
        hostService: hostService,
        snapshotStore: _MemorySnapshotStore(),
      );
      runtime.bind(
        onSnapshot: (session) {},
        onWatchError: (error, stackTrace) {},
      );

      await runtime.initialize();
      await runtime.submitTurn(submittedText: 'queued turn');

      expect(hostService.submittedTexts, ['queued turn']);
      expect(hostService.submitClientIds, ['desktop-client']);
    });

    test(
      'watch error propagation reaches the controller-facing surface',
      () async {
        final runtime = HostDesktopSessionRuntime(
          hostService: _WatchErrorHostService(),
          snapshotStore: _MemorySnapshotStore(),
        );
        final errors = <Object>[];
        runtime.bind(
          onSnapshot: (session) {},
          onWatchError: (error, stackTrace) => errors.add(error),
        );

        await runtime.initialize();
        await Future<void>.delayed(Duration.zero);

        expect(errors.single.toString(), contains('watch boom'));
      },
    );

    test(
      'persistence writes remain non-fatal to live runtime behavior',
      () async {
        final runtime = HostDesktopSessionRuntime(
          hostService: _TrackingHostService(),
          snapshotStore: _ThrowingSnapshotStore(),
        );
        final snapshots = <Session>[];
        runtime.bind(
          onSnapshot: snapshots.add,
          onWatchError: (error, stackTrace) {},
        );

        await runtime.initialize();
        await Future<void>.delayed(Duration.zero);

        expect(snapshots.single.id, 'desktop-session');
      },
    );
  });
}

Session _bootstrapSession() {
  return Session(
    id: 'desktop-session',
    activeHost: const Host(id: 'desktop-host'),
  ).attachClient(const Client(id: 'desktop-client'));
}

Session _baseRestoredSession() {
  const desktopClient = Client(id: 'desktop-client');
  const reviewerClient = Client(id: 'reviewer-client');

  return Session(
    id: 'restored-session',
    activeHost: const Host(id: 'restored-host'),
  ).attachClient(desktopClient).attachClient(reviewerClient);
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

final class _MemorySnapshotStore implements DesktopSessionSnapshotStore {
  _MemorySnapshotStore({this.storedSession});

  final Session? storedSession;

  @override
  Future<Session?> readLatestSession({required String desktopClientId}) async {
    return storedSession;
  }

  @override
  Future<void> writeLatestSession(Session session) async {}
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

class _TrackingHostService implements HostService {
  final Map<String, Session> _sessions = <String, Session>{};
  final Map<String, StreamController<Session>> _controllers =
      <String, StreamController<Session>>{};

  final List<String> createdSessionIds = <String>[];
  final List<String> attachedClientIds = <String>[];
  final List<String> restoredSessionIds = <String>[];
  final List<String> submittedTexts = <String>[];
  final List<String> submitClientIds = <String>[];
  int watchStarts = 0;
  int watchCancels = 0;
  bool concurrentWatchViolation = false;

  @override
  Session attachClient({required String sessionId, required Client client}) {
    attachedClientIds.add(client.id);
    final updated = _sessions[sessionId]!.attachClient(client);
    _sessions[sessionId] = updated;
    _controllers[sessionId]?.add(updated);
    return updated;
  }

  @override
  Session createSession({required String sessionId, required Host activeHost}) {
    createdSessionIds.add(sessionId);
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
    restoredSessionIds.add(session.id);
    _sessions[session.id] = session;
    return session;
  }

  @override
  Session submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) {
    submittedTexts.add(submittedText);
    submitClientIds.add(client.id);
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

final class _FailingRestoreHostService extends _TrackingHostService {
  int restoreAttempts = 0;

  @override
  Session restoreSession(Session session) {
    restoreAttempts += 1;
    throw StateError('restore failed');
  }
}

final class _ManualWatchHostService extends _TrackingHostService {
  StreamController<Session>? _controller;

  @override
  Stream<Session> watchSession(String sessionId) {
    watchStarts += 1;
    late final StreamController<Session> controller;
    controller = StreamController<Session>(
      onListen: () {
        _controller = controller;
      },
      onCancel: () {
        watchCancels += 1;
        if (identical(_controller, controller)) {
          _controller = null;
        }
      },
    );
    return controller.stream;
  }

  @override
  void emit(Session session) {
    _controller?.add(session);
  }

  void emitError(Object error) {
    _controller?.addError(error);
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

final class _ReplaceableWatchHostService extends _TrackingHostService {
  StreamController<Session>? _cancelledController;

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
        _cancelledController = controller;
        _controllers.remove(sessionId);
      },
    );
    return controller.stream;
  }

  void emitFromCancelledWatch(Session session) {
    _cancelledController?.add(session);
  }

  void emitCurrent(Session session) {
    emit(session);
  }
}

final class _WatchErrorHostService extends _TrackingHostService {
  @override
  Stream<Session> watchSession(String sessionId) {
    return Stream<Session>.error(StateError('watch boom'));
  }
}
