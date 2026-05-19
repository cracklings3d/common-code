import 'package:common_code_domain/common_code_domain.dart';

abstract interface class HostService {
  Session createSession({required String sessionId, required Host activeHost});

  Session attachClient({required String sessionId, required Client client});

  Stream<Session> watchSession(String sessionId);

  Session submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  });

  Session readSession(String sessionId);
}
