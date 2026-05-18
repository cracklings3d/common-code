import 'package:common_code_domain/common_code_domain.dart';

abstract interface class HostService {
  Session createSession({required String sessionId, required Host activeHost});

  Session attachClient({required String sessionId, required Client client});

  Session readSession(String sessionId);
}
