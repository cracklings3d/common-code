// Test-only support file. Lives under `apps/common_code_desktop/test/support/`.
//
// Provides a test-only [DurableLocalHostDiagnosticsPort] that records every
// emitted [DurableLocalHostDiagnostic] in memory and exposes them for test
// assertions. Used to confirm the diagnostics emitted during an out-of-process
// flow do not include any in-process fallback indicator and that the
// connector/launcher path was exercised.

import 'package:common_code_application/common_code_application.dart';

/// In-memory [DurableLocalHostDiagnosticsPort] that records every emitted
/// diagnostic.
///
/// The collector is suitable for both the production OOPIE path (where the
/// current `OutOfProcessOpenCodeHostAdapter` emits few or no diagnostics
/// at runtime) and the in-process fallback path (where the diagnostics
/// stream is the test's only signal that the fallback was or was not
/// taken). Tests that need to assert "the OOPIE path did not silently
/// fall back to in-process authority" can compare the collected codes
/// against a known set.
final class OutOfProcessDiagnosticCollector
    implements DurableLocalHostDiagnosticsPort {
  final List<DurableLocalHostDiagnostic> _diagnostics =
      <DurableLocalHostDiagnostic>[];

  /// All diagnostics emitted so far, in emission order.
  List<DurableLocalHostDiagnostic> get diagnostics =>
      List<DurableLocalHostDiagnostic>.unmodifiable(_diagnostics);

  /// The list of [DurableLocalHostDiagnosticCode] values emitted so far,
  /// in emission order.
  List<DurableLocalHostDiagnosticCode> get codes =>
      List<DurableLocalHostDiagnosticCode>.unmodifiable(
        _diagnostics.map((d) => d.code),
      );

  /// True if any diagnostic with the given [code] has been emitted.
  bool hasCode(DurableLocalHostDiagnosticCode code) =>
      _diagnostics.any((d) => d.code == code);

  /// Drop all recorded diagnostics. Useful between sub-cases of a test
  /// that share a single collector.
  void clear() {
    _diagnostics.clear();
  }

  @override
  void emit(DurableLocalHostDiagnostic diagnostic) {
    _diagnostics.add(diagnostic);
  }
}
