import 'package:common_code_domain/common_code_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Session', () {
    const host = Host(id: 'host-1');
    const backupHost = Host(id: 'host-2');
    const clientA = Client(id: 'client-a');
    const clientB = Client(id: 'client-b');

    Session buildSession({PromptThread? promptThread}) {
      return Session(
        id: 'session-1',
        activeHost: host,
        clients: const [clientA, clientB],
        promptThread: promptThread,
      );
    }

    test('constructs a valid initial session with an active host', () {
      final session = buildSession();

      expect(session.activeHost, host);
      expect(session.activeTurn, isNull);
      expect(session.inputClient, isNull);
    });

    test('replaces the active host while preserving a single active host', () {
      final session = buildSession();

      final updatedSession = session.replaceActiveHost(backupHost);

      expect(updatedSession.activeHost, backupHost);
      expect(updatedSession.activeTurn, isNull);
      expect(updatedSession.inputClient, isNull);
    });

    test('attaches a client while preserving the active host', () {
      final session = Session(id: 'session-1', activeHost: host);

      final updatedSession = session.attachClient(clientA);

      expect(updatedSession.activeHost, host);
      expect(updatedSession.clients, [clientA]);
      expect(updatedSession.activeTurn, isNull);
      expect(updatedSession.inputClient, isNull);
    });

    test('rejects attaching a duplicate client id to a session', () {
      final session = Session(
        id: 'session-1',
        activeHost: host,
        clients: const [clientA],
      );

      expect(
        () => session.attachClient(clientA),
        throwsA(
          isA<SessionFailure>().having(
            (failure) => failure.code,
            'code',
            SessionFailureCode.duplicateClientId,
          ),
        ),
      );
    });

    test('attaching a non-input client preserves an active turn invariant', () {
      final session = Session(
        id: 'session-1',
        activeHost: host,
        clients: const [clientA],
      ).startTurn(turnId: 'turn-1', client: clientA);

      final updatedSession = session.attachClient(clientB);

      expect(updatedSession.activeTurn, session.activeTurn);
      expect(updatedSession.inputClient, clientA);
      expect(updatedSession.clients, [clientA, clientB]);
    });

    test(
      'starts a turn from a client and promotes that client to input client',
      () {
        final session = buildSession();

        final updatedSession = session.startTurn(
          turnId: 'turn-1',
          client: clientA,
        );

        expect(
          updatedSession.activeTurn,
          const Turn.active(id: 'turn-1', clientId: 'client-a'),
        );
        expect(updatedSession.inputClient, clientA);
        expect(updatedSession.promptThread.turns, [
          const Turn.active(id: 'turn-1', clientId: 'client-a'),
        ]);
      },
    );

    test('rejects a second active turn while one is already active', () {
      final session = buildSession().startTurn(
        turnId: 'turn-1',
        client: clientA,
      );

      expect(
        () => session.startTurn(turnId: 'turn-2', client: clientB),
        throwsA(
          isA<SessionFailure>().having(
            (failure) => failure.code,
            'code',
            SessionFailureCode.activeTurnAlreadyExists,
          ),
        ),
      );
    });

    test('completes the active turn and returns to a no-active-turn state', () {
      final session = buildSession().startTurn(
        turnId: 'turn-1',
        client: clientA,
      );

      final updatedSession = session.completeActiveTurn();

      expect(updatedSession.activeTurn, isNull);
      expect(updatedSession.inputClient, isNull);
      expect(updatedSession.promptThread.turns, [
        const Turn.completed(id: 'turn-1', clientId: 'client-a'),
      ]);
    });

    test('preserves ordered prompt-thread history across turn transitions', () {
      final firstTurnSession = buildSession().startTurn(
        turnId: 'turn-1',
        client: clientA,
      );
      final completedFirstTurnSession = firstTurnSession.completeActiveTurn();

      final secondTurnSession = completedFirstTurnSession.startTurn(
        turnId: 'turn-2',
        client: clientB,
      );

      expect(secondTurnSession.promptThread.turns, [
        const Turn.completed(id: 'turn-1', clientId: 'client-a'),
        const Turn.active(id: 'turn-2', clientId: 'client-b'),
      ]);
      expect(secondTurnSession.inputClient, clientB);
    });

    test('rejects completing a turn when no active turn exists', () {
      final session = buildSession();

      expect(
        session.completeActiveTurn,
        throwsA(
          isA<SessionFailure>().having(
            (failure) => failure.code,
            'code',
            SessionFailureCode.noActiveTurn,
          ),
        ),
      );
    });

    test(
      'rejects constructing a session whose active turn input client is unattached',
      () {
        expect(
          () => Session(
            id: 'session-1',
            activeHost: host,
            clients: const [clientA],
            promptThread: PromptThread(
              turns: const [
                Turn.active(id: 'turn-1', clientId: 'missing-client'),
              ],
            ),
          ),
          throwsA(
            isA<SessionFailure>().having(
              (failure) => failure.code,
              'code',
              SessionFailureCode.inputClientNotAttached,
            ),
          ),
        );
      },
    );

    test(
      'exports the intended public domain surface from the package entrypoint',
      () {
        final promptThread = PromptThread();
        final session = Session(
          id: 'session-1',
          activeHost: host,
          clients: const [clientA],
          promptThread: promptThread,
        );

        expect(session, isA<Session>());
        expect(promptThread, isA<PromptThread>());
        expect(
          const Turn.active(id: 'turn-1', clientId: 'client-a'),
          isA<Turn>(),
        );
        expect(host, isA<Host>());
        expect(clientA, isA<Client>());
        expect(
          const SessionFailure(SessionFailureCode.noActiveTurn, 'message'),
          isA<SessionFailure>(),
        );
      },
    );

    test(
      'retains the temporary compatibility descriptor for scaffold consumers',
      () {
        expect(commonCodeDomainDescriptor, isA<CommonCodeDomainDescriptor>());
        expect(
          commonCodeDomainDescriptor.label,
          'common_code_domain placeholder contract',
        );
      },
    );
  });
}
