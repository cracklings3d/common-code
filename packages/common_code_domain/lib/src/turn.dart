enum TurnStatus { queued, running, completed, failed }

final class Turn {
  const Turn._({
    required this.id,
    required this.clientId,
    required this.submittedText,
    required this.status,
    required this.failureSummary,
  });

  const Turn.queued({
    required String id,
    required String clientId,
    required String submittedText,
  }) : this._(
         id: id,
         clientId: clientId,
         submittedText: submittedText,
         status: TurnStatus.queued,
         failureSummary: null,
       );

  const Turn.running({
    required String id,
    required String clientId,
    required String submittedText,
  }) : this._(
         id: id,
         clientId: clientId,
         submittedText: submittedText,
         status: TurnStatus.running,
         failureSummary: null,
       );

  const Turn.completed({
    required String id,
    required String clientId,
    required String submittedText,
  }) : this._(
         id: id,
         clientId: clientId,
         submittedText: submittedText,
         status: TurnStatus.completed,
         failureSummary: null,
       );

  const Turn.failed({
    required String id,
    required String clientId,
    required String submittedText,
    required String failureSummary,
  }) : this._(
         id: id,
         clientId: clientId,
         submittedText: submittedText,
         status: TurnStatus.failed,
         failureSummary: failureSummary,
       );

  final String id;
  final String clientId;
  final String submittedText;
  final TurnStatus status;
  final String? failureSummary;

  bool get isActive => switch (status) {
    TurnStatus.queued || TurnStatus.running => true,
    TurnStatus.completed || TurnStatus.failed => false,
  };

  Turn queueToRunning() {
    if (status == TurnStatus.running) {
      return this;
    }

    if (status != TurnStatus.queued) {
      throw StateError('Only queued turns can advance to running.');
    }

    return Turn.running(
      id: id,
      clientId: clientId,
      submittedText: submittedText,
    );
  }

  Turn complete() {
    if (status == TurnStatus.completed) {
      return this;
    }

    if (status != TurnStatus.running) {
      throw StateError('Only running turns can complete.');
    }

    return Turn.completed(
      id: id,
      clientId: clientId,
      submittedText: submittedText,
    );
  }

  Turn fail(String failureSummary) {
    if (status == TurnStatus.failed && this.failureSummary == failureSummary) {
      return this;
    }

    if (status != TurnStatus.running) {
      throw StateError('Only running turns can fail.');
    }

    return Turn.failed(
      id: id,
      clientId: clientId,
      submittedText: submittedText,
      failureSummary: failureSummary,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Turn &&
            other.id == id &&
            other.clientId == clientId &&
            other.submittedText == submittedText &&
            other.status == status &&
            other.failureSummary == failureSummary;
  }

  @override
  int get hashCode =>
      Object.hash(id, clientId, submittedText, status, failureSummary);

  @override
  String toString() {
    return 'Turn(id: $id, clientId: $clientId, submittedText: '
        '$submittedText, status: $status, failureSummary: $failureSummary)';
  }
}
