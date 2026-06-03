// Test-only support file. Lives under `apps/common_code_desktop/test/support/`.
//
// Provides a helper that drives a queued turn through `queuedToRunning`,
// `runningToCompleted`, or `runningToFailed` transitions and exposes the
// resulting `Session` snapshots for the watch-stream assertions in the
// canonical plan.
//
// The production `OutOfProcessOpenCodeHostAdapter` does not yet schedule
// host-driven transitions; the connector/launcher are still TODO placeholders.
// This helper simulates what the real transport will do by computing the
// post-transition snapshot locally (using the `Session` public API) and
// forwarding it through a stream the test can subscribe to.
//
// The helper does NOT mutate the production adapter's internal state. It
// reads the latest known session from its own subscription to
// `adapter.watchSession(...)` and applies the requested transition to
// produce a snapshot the test can assert against. This models the contract
// that the future real transport will satisfy: the host emits a session
// snapshot reflecting the new turn state through the watch stream.

import 'dart:async';

import 'package:common_code_domain/common_code_domain.dart';
import 'package:host_opencode/host_opencode.dart';

/// Test-only helper that drives host-side turn transitions through a
/// "watch stream" view of an [OutOfProcessOpenCodeHostAdapter].
///
/// Usage:
/// ```dart
/// final emitter = HostDrivenTransitionEmitter(adapter: adapter);
/// final stream = emitter.watchWithTransitions('e2e-session');
/// final snapshots = <Session>[];
/// final sub = stream.listen(snapshots.add);
/// // ... submitTurn, etc. ...
/// emitter.driveQueuedToRunning(sessionId: 'e2e-session');
/// expect(snapshots.last.activeTurn!.status, TurnStatus.running);
/// ```
class HostDrivenTransitionEmitter {
  HostDrivenTransitionEmitter({required this.adapter});

  /// The production adapter under test.
  final OutOfProcessOpenCodeHostAdapter adapter;

  Session? _lastSeen;
  StreamSubscription<Session>? _subscription;
  final StreamController<Session> _controller =
      StreamController<Session>.broadcast();
  final List<Session> _emitted = <Session>[];

  /// Combined stream of production watch emissions and host-driven
  /// transition emissions.
  Stream<Session> get transitions => _controller.stream;

  /// All snapshots produced by the helper (production emissions and
  /// host-driven emissions), in order.
  List<Session> get emittedSnapshots => List<Session>.unmodifiable(_emitted);

  /// The most recent session observed from the production watch stream,
  /// or `null` if [attach] has not been called.
  Session? get lastSeenSession => _lastSeen;

  /// True if [attach] has been called and the helper is forwarding
  /// production emissions.
  bool get isAttached => _subscription != null;

  /// Begin forwarding production watch emissions for the given session.
  /// The helper does not provide a method to "drive" transitions; it
  /// only tracks what the production stream emits. Tests use the
  /// `driveX` methods to add helper-emitted transitions.
  void attach({required String sessionId}) {
    if (_subscription != null) {
      throw StateError('HostDrivenTransitionEmitter is already attached.');
    }
    _subscription = adapter.watchSession(sessionId).listen((session) {
      _lastSeen = session;
      _emitted.add(session);
      _controller.add(session);
    });
  }

  /// Stop forwarding production watch emissions.
  Future<void> detach() async {
    final subscription = _subscription;
    if (subscription == null) return;
    _subscription = null;
    await subscription.cancel();
  }

  /// Computes the snapshot the host would emit when a queued turn is
  /// advanced to running. Returns the new `Session` for assertions.
  Session driveQueuedToRunning({required String sessionId}) {
    final current = _currentSession(sessionId);
    final updated = current.advanceActiveTurnToRunning();
    _lastSeen = updated;
    _recordHelperEmission(updated);
    return updated;
  }

  /// Computes the snapshot the host would emit when a running turn is
  /// advanced to completed. Returns the new `Session` for assertions.
  Session driveRunningToCompleted({required String sessionId}) {
    final current = _currentSession(sessionId);
    final updated = current.completeActiveTurn();
    _lastSeen = updated;
    _recordHelperEmission(updated);
    return updated;
  }

  /// Computes the snapshot the host would emit when a running turn is
  /// failed with the given [failureSummary]. Returns the new `Session`
  /// for assertions.
  Session driveRunningToFailed({
    required String sessionId,
    required String failureSummary,
  }) {
    final current = _currentSession(sessionId);
    final updated = current.failActiveTurn(failureSummary: failureSummary);
    _lastSeen = updated;
    _recordHelperEmission(updated);
    return updated;
  }

  /// Closes the helper. After calling this, [attach] can be called again
  /// to re-subscribe.
  Future<void> dispose() async {
    await detach();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  void _recordHelperEmission(Session session) {
    _emitted.add(session);
    _controller.add(session);
  }

  Session _currentSession(String sessionId) {
    final last = _lastSeen;
    if (last != null && last.id == sessionId) {
      return last;
    }
    return adapter.readSession(sessionId);
  }
}
