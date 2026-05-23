import 'package:common_code_domain/common_code_domain.dart';

abstract interface class CommonCodeSessionStore {
  Future<Session?> readLatestSession();

  Future<Session> restoreSession(Session session);
}

abstract interface class CommonCodeIdentityContext {
  Future<Client> resolveAttachedClient({required String sessionId});
}

final class CommonCodeSessionBootstrap {
  CommonCodeSessionBootstrap({
    required CommonCodeSessionStore sessionStore,
    required CommonCodeIdentityContext identityContext,
  }) : _sessionStore = sessionStore,
       _identityContext = identityContext;

  final CommonCodeSessionStore _sessionStore;
  final CommonCodeIdentityContext _identityContext;

  Future<Session> ensureSession({
    required String defaultSessionId,
    required String hostId,
  }) async {
    final restoredSession = await _sessionStore.readLatestSession();
    if (restoredSession != null) {
      try {
        return await _persistSessionWithAttachedClient(restoredSession);
      } catch (_) {
        // Fall back to the bounded fresh-session path.
      }
    }

    final freshSession = Session(
      id: defaultSessionId,
      activeHost: Host(id: hostId),
    );
    return _persistSessionWithAttachedClient(freshSession);
  }

  Future<Session> _persistSessionWithAttachedClient(Session session) async {
    final attachedClient = await _identityContext.resolveAttachedClient(
      sessionId: session.id,
    );
    return _sessionStore.restoreSession(
      _attachClientIfMissing(session, attachedClient),
    );
  }

  Session _attachClientIfMissing(Session session, Client attachedClient) {
    for (final client in session.clients) {
      if (client.id == attachedClient.id) {
        return session;
      }
    }

    return session.attachClient(attachedClient);
  }
}
