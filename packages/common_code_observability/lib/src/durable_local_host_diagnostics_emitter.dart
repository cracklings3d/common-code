import 'package:common_code_application/common_code_application.dart';

final class DurableLocalHostDiagnosticsEmitter
    implements DurableLocalHostDiagnosticsPort {
  const DurableLocalHostDiagnosticsEmitter(this._emitDiagnostic);

  final void Function(DurableLocalHostDiagnostic diagnostic) _emitDiagnostic;

  @override
  void emit(DurableLocalHostDiagnostic diagnostic) {
    _emitDiagnostic(diagnostic);
  }
}

void Function(Object error, StackTrace stackTrace)?
createDurableWriteFailureReporter(
  DurableLocalHostDiagnosticsPort? diagnosticsPort,
) {
  if (diagnosticsPort == null) {
    return null;
  }

  return (Object error, StackTrace stackTrace) {
    diagnosticsPort.emit(
      DurableLocalHostDiagnostic(
        DurableLocalHostDiagnosticCode.durableWriteFailed,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  };
}

DurableLocalHostDiagnosticsPort? resolveDurableLocalHostDiagnosticsPort(
  Object? candidate,
) {
  if (candidate == null) {
    return null;
  }

  if (candidate case final DurableLocalHostDiagnosticsPort port) {
    return port;
  }

  if (candidate is void Function(DurableLocalHostDiagnostic diagnostic)) {
    return DurableLocalHostDiagnosticsEmitter(candidate);
  }

  throw ArgumentError.value(
    candidate,
    'candidate',
    'Expected a DurableLocalHostDiagnosticsPort or diagnostic callback.',
  );
}
