// Test-only support file. Lives under `apps/common_code_desktop/test/support/`.
//
// Provides a configurable stub [OpenCodeHostConnector] and [OpenCodeHostLauncher]
// pair that simulates a real out-of-process OpenCode host on a known local
// endpoint. The stub replaces only the bytes-on-the-wire portion of the
// production transport; the real `OutOfProcessOpenCodeHostAdapter` is exercised
// end-to-end (constructor, bootstrap, every `HostService` method, the watch
// stream).
//
// Stub-vs-real divergence:
// - The stub returns immediately (or after a single microtask). Real
//   network/process I/O would be subject to non-deterministic latency.
// - The stub connector only ever returns the configured outcomes. It does
//   not model partial reads, mid-stream disconnects, or transport-level
//   retries.
// - The stub launcher never actually spawns a process. It records that
//   `launch()` was invoked and returns a synthetic launch result.

import 'package:host_opencode/host_opencode.dart';

/// Behavior mode for [StubOutOfProcessHostConnector].
///
/// The mode is fixed at construction; the connector uses the mode to
/// determine the outcome of each `connect()` invocation.
enum StubOutOfProcessHostMode {
  /// Connector succeeds on every `connect()` call. Models the
  /// "attach-to-existing host" path where an authoritative host is
  /// already running and reachable.
  succeedOnFirstTry,

  /// Connector fails on the first `connect()` call and succeeds on the
  /// second. Models the "launch-then-attach" path where the first attach
  /// attempt fails, the launcher spawns a host, and the second attach
  /// attempt succeeds.
  failThenSucceed,

  /// Connector fails on every `connect()` call. Models a host that is
  /// never reachable. Used to exercise bounded failed-start outcomes
  /// in combination with a failing launcher.
  failOnBothAttempts,
}

/// Stub [OpenCodeHostConnector] that simulates a real out-of-process host
/// on a known local endpoint.
///
/// Configurable via [StubOutOfProcessHostMode]. The stub records every
/// invocation: call count, invocation timestamps, and returned outcomes.
/// This makes it suitable for asserting the process-boundary observability
/// expectations of the canonical plan.
final class StubOutOfProcessHostConnector implements OpenCodeHostConnector {
  StubOutOfProcessHostConnector({
    StubOutOfProcessHostMode mode = StubOutOfProcessHostMode.succeedOnFirstTry,
    this.endpoint = 'localhost:4096',
  }) : _mode = mode;

  final StubOutOfProcessHostMode _mode;
  final String endpoint;

  int _connectCallCount = 0;
  final List<DateTime> _invocationTimestamps = <DateTime>[];
  final List<OpenCodeHostConnectionOutcome> _outcomes =
      <OpenCodeHostConnectionOutcome>[];

  /// Total number of times `connect()` has been invoked.
  int get connectCallCount => _connectCallCount;

  /// Timestamps of each `connect()` invocation, in invocation order.
  List<DateTime> get invocationTimestamps =>
      List<DateTime>.unmodifiable(_invocationTimestamps);

  /// Outcomes returned by each `connect()` invocation, in invocation order.
  List<OpenCodeHostConnectionOutcome> get outcomes =>
      List<OpenCodeHostConnectionOutcome>.unmodifiable(_outcomes);

  @override
  Future<OpenCodeHostConnectionOutcome> connect() async {
    _connectCallCount++;
    _invocationTimestamps.add(DateTime.now());

    // Yield to the microtask queue so callers can chain off the returned
    // future deterministically.
    await Future<void>.delayed(Duration.zero);

    final outcome = _outcomeForCall(_connectCallCount);
    _outcomes.add(outcome);
    return outcome;
  }

  OpenCodeHostConnectionOutcome _outcomeForCall(int call) {
    switch (_mode) {
      case StubOutOfProcessHostMode.succeedOnFirstTry:
        return OpenCodeHostConnectionSuccess(
          OpenCodeHostConnectionHandle(endpoint: endpoint),
        );
      case StubOutOfProcessHostMode.failThenSucceed:
        if (call == 1) {
          return OpenCodeHostConnectionFailed(
            const OpenCodeHostConnectionFailure(
              reason: 'Stub connector: no running host on first attempt',
            ),
          );
        }
        return OpenCodeHostConnectionSuccess(
          OpenCodeHostConnectionHandle(endpoint: endpoint),
        );
      case StubOutOfProcessHostMode.failOnBothAttempts:
        return OpenCodeHostConnectionFailed(
          const OpenCodeHostConnectionFailure(
            reason: 'Stub connector: host unreachable',
          ),
        );
    }
  }
}

/// Stub [OpenCodeHostLauncher] that simulates a real host binary launch.
///
/// Records every `launch()` invocation (count and timestamps) and returns
/// a configurable outcome. The stub never actually spawns a process; it
/// returns a synthetic launch result with a known process handle and
/// endpoint so the production adapter can chain a second `connect()` call
/// against the stub connector.
final class StubOutOfProcessHostLauncher implements OpenCodeHostLauncher {
  StubOutOfProcessHostLauncher({
    this.shouldSucceed = true,
    this.processHandle = 42,
    this.endpoint = 'localhost:4096',
  });

  bool shouldSucceed;
  int processHandle;
  String endpoint;

  int _launchCallCount = 0;
  final List<DateTime> _invocationTimestamps = <DateTime>[];
  final List<OpenCodeHostProcessLaunchOutcome> _outcomes =
      <OpenCodeHostProcessLaunchOutcome>[];

  /// Total number of times `launch()` has been invoked.
  int get launchCallCount => _launchCallCount;

  /// Timestamps of each `launch()` invocation, in invocation order.
  List<DateTime> get invocationTimestamps =>
      List<DateTime>.unmodifiable(_invocationTimestamps);

  /// Outcomes returned by each `launch()` invocation, in invocation order.
  List<OpenCodeHostProcessLaunchOutcome> get outcomes =>
      List<OpenCodeHostProcessLaunchOutcome>.unmodifiable(_outcomes);

  @override
  Future<OpenCodeHostProcessLaunchOutcome> launch() async {
    _launchCallCount++;
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
              reason: 'Stub launcher: binary not found',
            ),
          );
    _outcomes.add(outcome);
    return outcome;
  }
}
