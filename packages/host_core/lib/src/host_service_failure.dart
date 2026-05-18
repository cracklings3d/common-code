enum HostServiceFailureCode { duplicateSessionId, unknownSessionId }

final class HostServiceFailure implements Exception {
  const HostServiceFailure(this.code, this.message);

  final HostServiceFailureCode code;
  final String message;

  @override
  String toString() {
    return 'HostServiceFailure(code: $code, message: $message)';
  }
}
