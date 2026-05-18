import 'package:common_code_domain/common_code_domain.dart';

import 'host_service.dart';
import 'host_service_failure.dart';

HostService createInMemoryHostService() => _InMemoryHostService();

final class _InMemoryHostService implements HostService {
  final Map<String, Session> _sessionsById = <String, Session>{};

  @override
  Session createSession({required String sessionId, required Host activeHost}) {
    if (_sessionsById.containsKey(sessionId)) {
      throw HostServiceFailure(
        HostServiceFailureCode.duplicateSessionId,
        'Session $sessionId already exists.',
      );
    }

    final session = Session(id: sessionId, activeHost: activeHost);
    _sessionsById[sessionId] = session;
    return session;
  }

  @override
  Session attachClient({required String sessionId, required Client client}) {
    final session = _readStoredSession(sessionId);
    final updatedSession = session.attachClient(client);
    _sessionsById[sessionId] = updatedSession;
    return updatedSession;
  }

  @override
  Session readSession(String sessionId) => _readStoredSession(sessionId);

  Session _readStoredSession(String sessionId) {
    final session = _sessionsById[sessionId];
    if (session == null) {
      throw HostServiceFailure(
        HostServiceFailureCode.unknownSessionId,
        'Session $sessionId does not exist.',
      );
    }

    return session;
  }
}
