// Test-only support file. Lives under `apps/common_code_desktop/test/support/`.
//
// Provides an [OpenCodeHostConnector] test double that flips from "alive"
// to "unreachable" mid-test. Used to exercise the R2.* reconnect acceptance
// criteria from the canonical plan, which require the production adapter to
// surface a bounded failed-start outcome when the authoritative host is
// unavailable on a reconnect attempt.
//
// The double records every `connect()` invocation (count and returned
// outcome) so tests can assert that the connector was probed on the
// reconnect attempt and that the launcher was not invoked as a fallback
// (per the binding contract, the launcher is one-shot at bootstrap only).

import 'package:host_opencode/host_opencode.dart';

/// [OpenCodeHostConnector] test double that flips between "alive" and
/// "unreachable" mid-test.
///
/// Default state is "alive" (succeeds on every `connect()` call). Tests
/// drive the transition to "unreachable" by calling [flipToUnreachable]
/// (or back to "alive" via [flipToAlive]) to model a host that becomes
/// unreachable between bootstrap and a later reconnect attempt.
final class ReconnectOutOfProcessHostDouble implements OpenCodeHostConnector {
  ReconnectOutOfProcessHostDouble({
    this.endpoint = 'localhost:4096',
    bool startUnreachable = false,
  }) : _unreachable = startUnreachable;

  /// Convenience constructor that begins the connector in the
  /// "unreachable" state. Equivalent to calling
  /// `ReconnectOutOfProcessHostDouble(startUnreachable: true)`.
  ReconnectOutOfProcessHostDouble.unreachable({
    String endpoint = 'localhost:4096',
  }) : this(endpoint: endpoint, startUnreachable: true);

  final String endpoint;
  bool _unreachable;

  int _callCount = 0;
  final List<DateTime> _invocationTimestamps = <DateTime>[];
  final List<OpenCodeHostConnectionOutcome> _outcomes =
      <OpenCodeHostConnectionOutcome>[];

  /// Total number of times `connect()` has been invoked.
  int get connectCallCount => _callCount;

  /// Timestamps of each `connect()` invocation, in invocation order.
  List<DateTime> get invocationTimestamps =>
      List<DateTime>.unmodifiable(_invocationTimestamps);

  /// Outcomes returned by each `connect()` invocation, in invocation order.
  List<OpenCodeHostConnectionOutcome> get outcomes =>
      List<OpenCodeHostConnectionOutcome>.unmodifiable(_outcomes);

  /// True if subsequent `connect()` calls will return
  /// [OpenCodeHostConnectionFailed].
  bool get isUnreachable => _unreachable;

  /// Flip the connector to the "unreachable" state. Subsequent
  /// `connect()` calls will return [OpenCodeHostConnectionFailed].
  void flipToUnreachable() {
    _unreachable = true;
  }

  /// Flip the connector back to the "alive" state. Subsequent
  /// `connect()` calls will return [OpenCodeHostConnectionSuccess].
  void flipToAlive() {
    _unreachable = false;
  }

  @override
  Future<OpenCodeHostConnectionOutcome> connect() async {
    _callCount++;
    _invocationTimestamps.add(DateTime.now());

    await Future<void>.delayed(Duration.zero);

    final OpenCodeHostConnectionOutcome outcome;
    if (_unreachable) {
      outcome = OpenCodeHostConnectionFailed(
        const OpenCodeHostConnectionFailure(
          reason: 'Reconnect double: host unreachable',
        ),
      );
    } else {
      outcome = OpenCodeHostConnectionSuccess(
        OpenCodeHostConnectionHandle(endpoint: endpoint),
      );
    }
    _outcomes.add(outcome);
    return outcome;
  }
}
