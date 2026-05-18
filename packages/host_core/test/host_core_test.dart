import 'package:common_code_domain/common_code_domain.dart';
import 'package:host_core/host_core.dart';
import 'package:test/test.dart';

void main() {
  group('host_core', () {
    const host = Host(id: 'host-1');
    const client = Client(id: 'client-1');

    test('exports the intended public boundary surface', () {
      final service = createInMemoryHostService();

      expect(service, isA<HostService>());
      expect(
        const HostServiceFailure(
          HostServiceFailureCode.unknownSessionId,
          'message',
        ),
        isA<HostServiceFailure>(),
      );
      expect(host, isA<Host>());
      expect(client, isA<Client>());
    });

    test('creates a session and reads the initial snapshot', () {
      final service = createInMemoryHostService();

      final createdSession = service.createSession(
        sessionId: 'session-1',
        activeHost: host,
      );
      final readSession = service.readSession('session-1');

      expect(createdSession.id, 'session-1');
      expect(createdSession.activeHost, host);
      expect(createdSession.clients, isEmpty);
      expect(readSession, same(createdSession));
    });

    test('attaches one client and persists the updated session in memory', () {
      final service = createInMemoryHostService();

      service.createSession(sessionId: 'session-1', activeHost: host);
      final updatedSession = service.attachClient(
        sessionId: 'session-1',
        client: client,
      );

      expect(updatedSession.clients, [client]);
      expect(service.readSession('session-1').clients, [client]);
    });

    test('reading an unknown session fails explicitly', () {
      final service = createInMemoryHostService();

      expect(
        () => service.readSession('missing-session'),
        throwsA(
          isA<HostServiceFailure>().having(
            (failure) => failure.code,
            'code',
            HostServiceFailureCode.unknownSessionId,
          ),
        ),
      );
    });

    test('creating a duplicate session id fails explicitly', () {
      final service = createInMemoryHostService();

      service.createSession(sessionId: 'session-1', activeHost: host);

      expect(
        () => service.createSession(sessionId: 'session-1', activeHost: host),
        throwsA(
          isA<HostServiceFailure>().having(
            (failure) => failure.code,
            'code',
            HostServiceFailureCode.duplicateSessionId,
          ),
        ),
      );
    });
  });
}
