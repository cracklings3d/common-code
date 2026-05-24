import 'package:common_code_domain/common_code_domain.dart';
import 'package:host_in_memory/host_in_memory.dart';

void main() {
  final hostService = createInMemoryHostService();
  final session = hostService.createSession(
    sessionId: 'example-session',
    activeHost: const Host(id: 'desktop-host'),
  );

  print(session.id);
}
