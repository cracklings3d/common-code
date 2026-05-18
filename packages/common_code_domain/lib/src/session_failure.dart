enum SessionFailureCode {
  activeTurnAlreadyExists,
  noActiveTurn,
  clientNotAttached,
  duplicateClientId,
  invalidActiveTurnCount,
  inputClientNotAttached,
}

final class SessionFailure implements Exception {
  const SessionFailure(this.code, this.message);

  final SessionFailureCode code;
  final String message;

  @override
  String toString() => 'SessionFailure(code: $code, message: $message)';
}
