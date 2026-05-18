final class Host {
  const Host({required this.id});

  final String id;

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is Host && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Host(id: $id)';
}
