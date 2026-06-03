// Test-only support file. Lives under `apps/common_code_desktop/test/support/`.
//
// Provides a counting [OpenCodeHostConnector] test double that records every
// `connect()` invocation (count, timestamp, and returned outcome). Used to
// prove the connector path was exercised when validating the process boundary
// observability assertions in the canonical plan.
//
// The connector is configurable: callers supply an [outcomeBuilder] that
// produces the outcome for a given call index, or accept the default of
// [OpenCodeHostConnectionSuccess] on every call (attach-to-existing path).

import 'package:host_opencode/host_opencode.dart';

/// Counting [OpenCodeHostConnector] that records every invocation.
///
/// The default outcome for every call is [OpenCodeHostConnectionSuccess]
/// (suitable for the "attach-to-existing" bootstrap path). For other
/// paths, supply an [outcomeBuilder] that takes the call index and
/// returns the outcome to record.
final class CapturingOutOfProcessHostConnector implements OpenCodeHostConnector {
  CapturingOutOfProcessHostConnector({
    OpenCodeHostConnectionOutcome Function(int callIndex)? outcomeBuilder,
    this.endpoint = 'localhost:4096',
  }) : _outcomeBuilder = outcomeBuilder;

  final OpenCodeHostConnectionOutcome Function(int callIndex)? _outcomeBuilder;
  final String endpoint;

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

  @override
  Future<OpenCodeHostConnectionOutcome> connect() async {
    _callCount++;
    _invocationTimestamps.add(DateTime.now());

    await Future<void>.delayed(Duration.zero);

    final outcome = _outcomeBuilder?.call(_callCount) ??
        OpenCodeHostConnectionSuccess(
          OpenCodeHostConnectionHandle(endpoint: endpoint),
        );
    _outcomes.add(outcome);
    return outcome;
  }
}
