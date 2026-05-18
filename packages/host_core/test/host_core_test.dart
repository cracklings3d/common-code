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

    test('submits a turn for an attached client through the host boundary', () {
      final service = createInMemoryHostService();

      service.createSession(sessionId: 'session-1', activeHost: host);
      service.attachClient(sessionId: 'session-1', client: client);

      final updatedSession = service.submitTurn(
        sessionId: 'session-1',
        client: client,
        submittedText: 'Submit the first desktop turn.',
      );

      expect(updatedSession.activeTurn?.id, 'turn-1');
      expect(updatedSession.activeTurn?.submittedText, 'Submit the first desktop turn.');
      expect(updatedSession.inputClient, client);
    });

    test('submitTurn persists the updated session for subsequent reads', () {
      final service = createInMemoryHostService();

      service.createSession(sessionId: 'session-1', activeHost: host);
      service.attachClient(sessionId: 'session-1', client: client);
      service.submitTurn(
        sessionId: 'session-1',
        client: client,
        submittedText: 'Stored in the shared prompt thread.',
      );

      final storedSession = service.readSession('session-1');

      expect(storedSession.inputClient, client);
      expect(storedSession.activeTurn?.id, 'turn-1');
      expect(storedSession.promptThread.turns.single.submittedText, 'Stored in the shared prompt thread.');
    });

    test('submitting another turn while one is active fails explicitly', () {
      final service = createInMemoryHostService();

      service.createSession(sessionId: 'session-1', activeHost: host);
      service.attachClient(sessionId: 'session-1', client: client);
      service.submitTurn(
        sessionId: 'session-1',
        client: client,
        submittedText: 'First active turn.',
      );

      expect(
        () => service.submitTurn(
          sessionId: 'session-1',
          client: client,
          submittedText: 'Blocked second turn.',
        ),
        throwsA(
          isA<SessionFailure>().having(
            (failure) => failure.code,
            'code',
            SessionFailureCode.activeTurnAlreadyExists,
          ),
        ),
      );
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
