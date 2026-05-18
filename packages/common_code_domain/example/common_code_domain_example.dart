import 'package:common_code_domain/common_code_domain.dart';

void main() {
  final session = Session(
    id: 'session-1',
    activeHost: Host(id: 'host-1'),
  );

  print(session.activeHost.id);
}
