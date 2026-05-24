import 'package:common_code_observability/common_code_observability.dart';
import 'package:test/test.dart';

void main() {
  group('DurableLocalHostDiagnosticCode', () {
    test('has expected values', () {
      expect(DurableLocalHostDiagnosticCode.values, contains(DurableLocalHostDiagnosticCode.durableReadRestored));
      expect(DurableLocalHostDiagnosticCode.values, contains(DurableLocalHostDiagnosticCode.durableReadMissing));
      expect(DurableLocalHostDiagnosticCode.values, contains(DurableLocalHostDiagnosticCode.durableReadFailed));
      expect(DurableLocalHostDiagnosticCode.values, contains(DurableLocalHostDiagnosticCode.legacySeedActivated));
      expect(DurableLocalHostDiagnosticCode.values, contains(DurableLocalHostDiagnosticCode.legacySeedFailed));
      expect(DurableLocalHostDiagnosticCode.values, contains(DurableLocalHostDiagnosticCode.durableRestoreFailed));
      expect(DurableLocalHostDiagnosticCode.values, contains(DurableLocalHostDiagnosticCode.durableWriteFailed));
      expect(DurableLocalHostDiagnosticCode.values, contains(DurableLocalHostDiagnosticCode.freshBootstrapActivated));
    });
  });

  group('DurableLocalHostDiagnostic', () {
    test('can be constructed with code', () {
      const diagnostic = DurableLocalHostDiagnostic(DurableLocalHostDiagnosticCode.durableReadRestored);
      expect(diagnostic.code, equals(DurableLocalHostDiagnosticCode.durableReadRestored));
      expect(diagnostic.error, isNull);
      expect(diagnostic.stackTrace, isNull);
    });

    test('can be constructed with code and error', () {
      final error = Exception('test error');
      final stackTrace = StackTrace.current;
      final diagnostic = DurableLocalHostDiagnostic(
        DurableLocalHostDiagnosticCode.durableReadFailed,
        error: error,
        stackTrace: stackTrace,
      );
      expect(diagnostic.code, equals(DurableLocalHostDiagnosticCode.durableReadFailed));
      expect(diagnostic.error, equals(error));
      expect(diagnostic.stackTrace, equals(stackTrace));
    });
  });
}