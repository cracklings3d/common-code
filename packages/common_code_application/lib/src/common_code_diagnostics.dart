enum DurableLocalHostDiagnosticCode {
  durableReadRestored,
  durableReadMissing,
  durableReadCorruptOrInvalid,
  durableReadFailed,
  legacySeedActivated,
  legacySeedSkipped,
  legacySeedSucceeded,
  legacySeedFailed,
  durableRestoreFailed,
  durableWriteFailed,
  freshBootstrapActivated,
}

final class DurableLocalHostDiagnostic {
  const DurableLocalHostDiagnostic(this.code, {this.error, this.stackTrace});

  final DurableLocalHostDiagnosticCode code;
  final Object? error;
  final StackTrace? stackTrace;
}

abstract interface class DurableLocalHostDiagnosticsPort {
  void emit(DurableLocalHostDiagnostic diagnostic);
}
