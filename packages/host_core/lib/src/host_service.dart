import 'package:common_code_domain/common_code_domain.dart';

abstract interface class HostService {
  @Deprecated(
    'Transitional host-core compatibility only. Use common_code_application '
    'session-store and identity-context seams instead.',
  )
  Session createSession({required String sessionId, required Host activeHost});

  @Deprecated(
    'Transitional host-core compatibility only. Use common_code_application '
    'session-store and identity-context seams instead.',
  )
  Session attachClient({required String sessionId, required Client client});

  Session acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  });

  Stream<Session> watchSession(String sessionId);

  @Deprecated(
    'Transitional host-core compatibility only. Use common_code_application '
    'session-store and identity-context seams instead.',
  )
  Session restoreSession(Session session);

  Session submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  });

  @Deprecated(
    'Transitional host-core compatibility only. Use common_code_application '
    'session-store and identity-context seams instead.',
  )
  Session readSession(String sessionId);
}
