import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:test/test.dart';

void main() {
  group('CommonCodeSessionBootstrap', () {
    test(
      'creates a fresh session with active host and attached client',
      () async {
        final store = _FakeSessionStore();
        final bootstrap = CommonCodeSessionBootstrap(
          sessionStore: store,
          identityContext: const _FakeIdentityContext('desktop-client'),
        );

        final session = await bootstrap.ensureSession(
          defaultSessionId: 'desktop-session',
          hostId: 'desktop-host',
        );

        expect(session.id, 'desktop-session');
        expect(session.activeHost, const Host(id: 'desktop-host'));
        expect(session.clients, [const Client(id: 'desktop-client')]);
        expect(store.restoredSessions.single, session);
      },
    );

    test('restores stored continuity through the session store seam', () async {
      final store = _FakeSessionStore(
        latestSession: Session(
          id: 'restored-session',
          activeHost: const Host(id: 'restored-host'),
        ),
      );
      final bootstrap = CommonCodeSessionBootstrap(
        sessionStore: store,
        identityContext: const _FakeIdentityContext('desktop-client'),
      );

      final session = await bootstrap.ensureSession(
        defaultSessionId: 'desktop-session',
        hostId: 'desktop-host',
      );

      expect(session.id, 'restored-session');
      expect(session.activeHost, const Host(id: 'restored-host'));
      expect(session.clients, [const Client(id: 'desktop-client')]);
      expect(store.restoredSessions.single.id, 'restored-session');
    });

    test('falls back to a fresh session when restore storage fails', () async {
      final store = _FakeSessionStore(
        latestSession: Session(
          id: 'restored-session',
          activeHost: const Host(id: 'restored-host'),
        ),
        failFirstRestore: true,
      );
      final bootstrap = CommonCodeSessionBootstrap(
        sessionStore: store,
        identityContext: const _FakeIdentityContext('desktop-client'),
      );

      final session = await bootstrap.ensureSession(
        defaultSessionId: 'desktop-session',
        hostId: 'desktop-host',
      );

      expect(session.id, 'desktop-session');
      expect(session.activeHost, const Host(id: 'desktop-host'));
      expect(session.clients, [const Client(id: 'desktop-client')]);
      expect(store.restoredSessions, hasLength(2));
      expect(store.restoredSessions.first.id, 'restored-session');
      expect(store.restoredSessions.last.id, 'desktop-session');
    });
  });
}

final class _FakeSessionStore implements CommonCodeSessionStore {
  _FakeSessionStore({this.latestSession, this.failFirstRestore = false});

  final Session? latestSession;
  final bool failFirstRestore;
  final List<Session> restoredSessions = <Session>[];

  bool _didFailRestore = false;

  @override
  Future<Session?> readLatestSession() async => latestSession;

  @override
  Future<Session> restoreSession(Session session) async {
    restoredSessions.add(session);
    if (failFirstRestore && !_didFailRestore) {
      _didFailRestore = true;
      throw StateError('restore failed');
    }

    return session;
  }
}

final class _FakeIdentityContext implements CommonCodeIdentityContext {
  const _FakeIdentityContext(this.clientId);

  final String clientId;

  @override
  Future<Client> resolveAttachedClient({required String sessionId}) async {
    return Client(id: clientId);
  }
}
