final class Client {
  const Client({required this.id});

  final String id;

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is Client && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Client(id: $id)';
}
