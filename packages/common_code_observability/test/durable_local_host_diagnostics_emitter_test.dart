import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_observability/common_code_observability.dart';
import 'package:test/test.dart';

void main() {
  group('DurableLocalHostDiagnosticsEmitter', () {
    test('emits provided diagnostic to callback', () {
      DurableLocalHostDiagnostic? captured;
      final emitter = DurableLocalHostDiagnosticsEmitter(
        (diagnostic) => captured = diagnostic,
      );
      const diagnostic = DurableLocalHostDiagnostic(
        DurableLocalHostDiagnosticCode.durableReadRestored,
      );

      emitter.emit(diagnostic);

      expect(captured, same(diagnostic));
    });
  });

  group('resolveDurableLocalHostDiagnosticsPort', () {
    test('returns null for null candidate', () {
      expect(resolveDurableLocalHostDiagnosticsPort(null), isNull);
    });

    test('passes through an existing diagnostics port', () {
      final port = DurableLocalHostDiagnosticsEmitter((_) {});

      expect(resolveDurableLocalHostDiagnosticsPort(port), same(port));
    });

    test('wraps callback candidate in emitter', () {
      final emitted = <DurableLocalHostDiagnostic>[];
      final port = resolveDurableLocalHostDiagnosticsPort(emitted.add);
      const diagnostic = DurableLocalHostDiagnostic(
        DurableLocalHostDiagnosticCode.durableWriteFailed,
      );

      port!.emit(diagnostic);

      expect(emitted, [same(diagnostic)]);
    });

    test('rejects unsupported candidate type', () {
      expect(
        () => resolveDurableLocalHostDiagnosticsPort('bad'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('createDurableWriteFailureReporter', () {
    test('emits durable write failed diagnostics through port', () {
      final emitted = <DurableLocalHostDiagnostic>[];
      final reporter = createDurableWriteFailureReporter(
        DurableLocalHostDiagnosticsEmitter(emitted.add),
      );
      final error = StateError('write boom');
      final stackTrace = StackTrace.current;

      reporter!(error, stackTrace);

      expect(emitted, hasLength(1));
      expect(
        emitted.single.code,
        DurableLocalHostDiagnosticCode.durableWriteFailed,
      );
      expect(emitted.single.error, same(error));
      expect(emitted.single.stackTrace, same(stackTrace));
    });
  });
}
