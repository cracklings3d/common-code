import 'package:common_code_application/common_code_application.dart';
import 'package:test/test.dart';

void main() {
  group('DurableLocalHostDiagnosticCode', () {
    test('exposes durable-local diagnostic cases', () {
      expect(
        DurableLocalHostDiagnosticCode.values,
        containsAll(<DurableLocalHostDiagnosticCode>[
          DurableLocalHostDiagnosticCode.durableReadRestored,
          DurableLocalHostDiagnosticCode.durableReadMissing,
          DurableLocalHostDiagnosticCode.durableReadCorruptOrInvalid,
          DurableLocalHostDiagnosticCode.durableReadFailed,
          DurableLocalHostDiagnosticCode.legacySeedActivated,
          DurableLocalHostDiagnosticCode.legacySeedSkipped,
          DurableLocalHostDiagnosticCode.legacySeedSucceeded,
          DurableLocalHostDiagnosticCode.legacySeedFailed,
          DurableLocalHostDiagnosticCode.durableRestoreFailed,
          DurableLocalHostDiagnosticCode.durableWriteFailed,
          DurableLocalHostDiagnosticCode.freshBootstrapActivated,
        ]),
      );
    });
  });

  test('DurableLocalHostDiagnostic stores optional error context', () {
    final error = StateError('boom');
    final stackTrace = StackTrace.current;
    final diagnostic = DurableLocalHostDiagnostic(
      DurableLocalHostDiagnosticCode.durableReadFailed,
      error: error,
      stackTrace: stackTrace,
    );

    expect(diagnostic.code, DurableLocalHostDiagnosticCode.durableReadFailed);
    expect(diagnostic.error, same(error));
    expect(diagnostic.stackTrace, same(stackTrace));
  });
}
