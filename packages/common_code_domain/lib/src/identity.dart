final class Identity {
  const Identity({required this.id});

  final String id;

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is Identity && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Identity(id: $id)';
}
