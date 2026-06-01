library;

// Passive compatibility re-export: HostService is now owned by common_code_application.
// This package remains only for compile-safety of any dormant callers outside
// the active desktop/in-memory path.
export 'package:common_code_application/common_code_application.dart' show HostService, HostServiceFailure, HostServiceFailureCode;
