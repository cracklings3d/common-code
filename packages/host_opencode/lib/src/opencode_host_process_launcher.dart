import 'dart:async';

/// Result of a successful host process launch.
final class OpenCodeHostProcessLaunchResult {
  const OpenCodeHostProcessLaunchResult({
    required this.processHandle,
    required this.connectionEndpoint,
  });

  final int processHandle;
  final String connectionEndpoint;
}

/// Result of a failed host process launch.
final class OpenCodeHostProcessLaunchFailure {
  const OpenCodeHostProcessLaunchFailure({required this.reason});

  final String reason;
}

/// Outcome of a launch attempt - either success or failure.
sealed class OpenCodeHostProcessLaunchOutcome {}

/// Successful launch outcome with result.
final class OpenCodeHostProcessLaunchSuccess
    extends OpenCodeHostProcessLaunchOutcome {
  OpenCodeHostProcessLaunchSuccess(this.result);

  final OpenCodeHostProcessLaunchResult result;
}

/// Failed launch outcome with failure details.
final class OpenCodeHostProcessLaunchFailed
    extends OpenCodeHostProcessLaunchOutcome {
  OpenCodeHostProcessLaunchFailed(this.failure);

  final OpenCodeHostProcessLaunchFailure failure;
}

/// Encapsulates logic to locate and spawn the machine-local OpenCode host binary.
///
/// One-shot launch only - no watchdog, auto-restart, or service manager integration.
abstract interface class OpenCodeHostLauncher {
  /// Locates the OpenCode host binary and spawns it.
  ///
  /// Returns [OpenCodeHostProcessLaunchSuccess] with process handle and connection endpoint on success.
  /// Returns [OpenCodeHostProcessLaunchFailed] when binary not found, permission denied,
  /// or process exits immediately.
  Future<OpenCodeHostProcessLaunchOutcome> launch();
}

/// Concrete implementation of [OpenCodeHostLauncher] for production use.
final class OpenCodeHostProcessLauncher implements OpenCodeHostLauncher {
  const OpenCodeHostProcessLauncher();

  @override
  Future<OpenCodeHostProcessLaunchOutcome> launch() async {
    // TODO: Implement actual binary location and spawning logic.
    // This is a placeholder that simulates a successful launch.
    // The actual implementation would:
    // 1. Locate the OpenCode binary (e.g., using platform-specific paths)
    // 2. Verify the binary exists and is executable
    // 3. Spawn the process
    // 4. Wait briefly to confirm process started successfully
    // 5. Return the process handle and connection endpoint

    await Future<dynamic>.delayed(const Duration(milliseconds: 100));

    return OpenCodeHostProcessLaunchSuccess(
      OpenCodeHostProcessLaunchResult(
        processHandle: 1,
        connectionEndpoint: 'localhost:12345',
      ),
    );
  }
}
