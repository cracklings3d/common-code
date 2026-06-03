// Test-only support file. Lives under `apps/common_code_desktop/test/support/`.
//
// Provides a counting [OpenCodeHostLauncher] test double that records every
// `launch()` invocation (count, timestamp, and returned outcome). Used to
// prove the launcher path was exercised when validating the process boundary
// observability assertions in the canonical plan.

import 'package:host_opencode/host_opencode.dart';

/// Counting [OpenCodeHostLauncher] that records every invocation.
///
/// Defaults to returning [OpenCodeHostProcessLaunchSuccess] on every
/// invocation. Callers that need to drive the bounded failed-start path
/// can pass `shouldSucceed: false` (or use a different stub).
final class CapturingOutOfProcessHostLauncher implements OpenCodeHostLauncher {
  CapturingOutOfProcessHostLauncher({
    this.shouldSucceed = true,
    this.processHandle = 42,
    this.endpoint = 'localhost:4096',
  });

  bool shouldSucceed;
  int processHandle;
  String endpoint;

  int _callCount = 0;
  final List<DateTime> _invocationTimestamps = <DateTime>[];
  final List<OpenCodeHostProcessLaunchOutcome> _outcomes =
      <OpenCodeHostProcessLaunchOutcome>[];

  /// Total number of times `launch()` has been invoked.
  int get launchCallCount => _callCount;

  /// Timestamps of each `launch()` invocation, in invocation order.
  List<DateTime> get invocationTimestamps =>
      List<DateTime>.unmodifiable(_invocationTimestamps);

  /// Outcomes returned by each `launch()` invocation, in invocation order.
  List<OpenCodeHostProcessLaunchOutcome> get outcomes =>
      List<OpenCodeHostProcessLaunchOutcome>.unmodifiable(_outcomes);

  @override
  Future<OpenCodeHostProcessLaunchOutcome> launch() async {
    _callCount++;
    _invocationTimestamps.add(DateTime.now());

    await Future<void>.delayed(Duration.zero);

    final outcome = shouldSucceed
        ? OpenCodeHostProcessLaunchSuccess(
            OpenCodeHostProcessLaunchResult(
              processHandle: processHandle,
              connectionEndpoint: endpoint,
            ),
          )
        : OpenCodeHostProcessLaunchFailed(
            const OpenCodeHostProcessLaunchFailure(
              reason: 'Stub launcher: launch failed',
            ),
          );
    _outcomes.add(outcome);
    return outcome;
  }
}
