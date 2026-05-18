final class Turn {
  const Turn._({
    required this.id,
    required this.clientId,
    required this.submittedText,
    required this.isActive,
  });

  const Turn.active({
    required String id,
    required String clientId,
    required String submittedText,
  }) : this._(
         id: id,
         clientId: clientId,
         submittedText: submittedText,
         isActive: true,
       );

  const Turn.completed({
    required String id,
    required String clientId,
    required String submittedText,
  }) : this._(
         id: id,
         clientId: clientId,
         submittedText: submittedText,
         isActive: false,
       );

  final String id;
  final String clientId;
  final String submittedText;
  final bool isActive;

  Turn complete() {
    if (!isActive) {
      return this;
    }

    return Turn.completed(
      id: id,
      clientId: clientId,
      submittedText: submittedText,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Turn &&
            other.id == id &&
            other.clientId == clientId &&
            other.submittedText == submittedText &&
            other.isActive == isActive;
  }

  @override
  int get hashCode => Object.hash(id, clientId, submittedText, isActive);

  @override
  String toString() {
    return 'Turn(id: $id, clientId: $clientId, submittedText: '
        '$submittedText, isActive: $isActive)';
  }
}
