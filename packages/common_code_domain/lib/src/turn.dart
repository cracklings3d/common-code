final class Turn {
  const Turn._({
    required this.id,
    required this.clientId,
    required this.isActive,
  });

  const Turn.active({required String id, required String clientId})
    : this._(id: id, clientId: clientId, isActive: true);

  const Turn.completed({required String id, required String clientId})
    : this._(id: id, clientId: clientId, isActive: false);

  final String id;
  final String clientId;
  final bool isActive;

  Turn complete() {
    if (!isActive) {
      return this;
    }

    return Turn.completed(id: id, clientId: clientId);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Turn &&
            other.id == id &&
            other.clientId == clientId &&
            other.isActive == isActive;
  }

  @override
  int get hashCode => Object.hash(id, clientId, isActive);

  @override
  String toString() {
    return 'Turn(id: $id, clientId: $clientId, isActive: $isActive)';
  }
}
