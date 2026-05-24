import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:host_core/host_core.dart';
import 'package:host_in_memory/host_in_memory.dart';
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
      final service = createInMemoryHostService(
        simulationPolicy: const HostExecutionSimulationPolicy(
          queuedToRunningDelay: Duration(seconds: 1),
          runningToTerminalDelay: Duration(seconds: 1),
        ),
      );

      service.createSession(sessionId: 'session-1', activeHost: host);
      service.attachClient(sessionId: 'session-1', client: client);

      final updatedSession = service.submitTurn(
        sessionId: 'session-1',
        client: client,
        submittedText: 'Submit the first desktop turn.',
      );

      expect(updatedSession.activeTurn?.id, 'turn-1');
      expect(
        updatedSession.activeTurn?.submittedText,
        'Submit the first desktop turn.',
      );
      expect(updatedSession.activeTurn?.status, TurnStatus.queued);
      expect(updatedSession.inputClient, client);
    });

    test('acknowledges one notification through the host boundary', () async {
      final service = createInMemoryHostService(
        simulationPolicy: const HostExecutionSimulationPolicy(
          queuedToRunningDelay: Duration.zero,
          runningToTerminalDelay: Duration.zero,
        ),
      );

      service.createSession(sessionId: 'session-1', activeHost: host);
      service.attachClient(sessionId: 'session-1', client: client);
      final completedSnapshots = service.watchSession('session-1').take(4).toList();

      service.submitTurn(
        sessionId: 'session-1',
        client: client,
        submittedText: 'Observe acknowledgement.',
      );

      final completedSession = (await completedSnapshots).last;
      final notificationId = completedSession.notifications.first.id;
      final acknowledgedSession = service.acknowledgeNotification(
        sessionId: 'session-1',
        notificationId: notificationId,
      );

      expect(
        acknowledgedSession.notifications.firstWhere(
          (notification) => notification.id == notificationId,
        ).isAcknowledged,
        isTrue,
      );
    });

    test('submitTurn persists the updated session for subsequent reads', () {
      final service = createInMemoryHostService(
        simulationPolicy: const HostExecutionSimulationPolicy(
          queuedToRunningDelay: Duration(seconds: 1),
          runningToTerminalDelay: Duration(seconds: 1),
        ),
      );

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
      expect(storedSession.activeTurn?.status, TurnStatus.queued);
      expect(
        storedSession.promptThread.turns.single.submittedText,
        'Stored in the shared prompt thread.',
      );
    });

    test(
      'watchSession emits the current stored snapshot immediately',
      () async {
        final service = createInMemoryHostService();

        service.createSession(sessionId: 'session-1', activeHost: host);
        service.attachClient(sessionId: 'session-1', client: client);

        final snapshots = await service
            .watchSession('session-1')
            .take(1)
            .toList();

        expect(snapshots.single, service.readSession('session-1'));
        expect(snapshots.single.clients, [client]);
      },
    );

    test('restoreSession stores a provided session for later reads', () {
      final service = createInMemoryHostService();
      final restoredSession = Session(
        id: 'restored-session',
        activeHost: host,
      ).attachClient(client);

      final storedSession = service.restoreSession(restoredSession);

      expect(storedSession, same(restoredSession));
      expect(service.readSession('restored-session'), same(restoredSession));
    });

    test('watchSession immediately emits a restored snapshot', () async {
      final service = createInMemoryHostService();
      final restoredSession = Session(
        id: 'restored-session',
        activeHost: host,
      ).attachClient(client);

      service.restoreSession(restoredSession);
      final snapshots = await service
          .watchSession('restored-session')
          .take(1)
          .toList();

      expect(snapshots.single, same(restoredSession));
    });

    test(
      'restoring queued or running turns does not trigger automatic execution progression',
      () async {
        final service = createInMemoryHostService(
          simulationPolicy: const HostExecutionSimulationPolicy(
            queuedToRunningDelay: Duration.zero,
            runningToTerminalDelay: Duration.zero,
          ),
        );
        final restoredSession =
            Session(id: 'restored-session', activeHost: host)
                .attachClient(client)
                .startTurn(
                  turnId: 'turn-1',
                  client: client,
                  submittedText: 'Restored queued turn.',
                );

        service.restoreSession(restoredSession);
        final snapshots = <Session>[];
        final subscription = service
            .watchSession('restored-session')
            .listen(snapshots.add);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await subscription.cancel();

        expect(snapshots, hasLength(1));
        expect(snapshots.single.activeTurn?.status, TurnStatus.queued);
      },
    );

    test(
      'simulated loop emits queued running and completed snapshots in order',
      () async {
        final service = createInMemoryHostService(
          simulationPolicy: const HostExecutionSimulationPolicy(
            queuedToRunningDelay: Duration.zero,
            runningToTerminalDelay: Duration.zero,
          ),
        );

        service.createSession(sessionId: 'session-1', activeHost: host);
        service.attachClient(sessionId: 'session-1', client: client);

        final snapshotsFuture = service
            .watchSession('session-1')
            .take(4)
            .toList();

        service.submitTurn(
          sessionId: 'session-1',
          client: client,
          submittedText: 'Submit the first desktop turn.',
        );

        final snapshots = await snapshotsFuture;

        expect(snapshots[0].activeTurn, isNull);
        expect(snapshots[1].activeTurn?.status, TurnStatus.queued);
        expect(snapshots[2].activeTurn?.status, TurnStatus.running);
        expect(snapshots[3].activeTurn, isNull);
        expect(
          snapshots[3].promptThread.turns.single.status,
          TurnStatus.completed,
        );
        expect(
          snapshots[3].notifications.map(
            (notification) => notification.transition,
          ),
          [
            SessionNotificationTransition.queuedToRunning,
            SessionNotificationTransition.runningToCompleted,
          ],
        );
      },
    );

    test(
      'simulated terminal failure is delivered as session data not watch error',
      () async {
        final service = createInMemoryHostService(
          simulationPolicy: const HostExecutionSimulationPolicy(
            queuedToRunningDelay: Duration.zero,
            runningToTerminalDelay: Duration.zero,
            terminalOutcome: SimulatedTurnTerminalOutcome.failed,
            failureSummary: 'Simulated host failure.',
          ),
        );

        service.createSession(sessionId: 'session-1', activeHost: host);
        service.attachClient(sessionId: 'session-1', client: client);

        final snapshotsFuture = service
            .watchSession('session-1')
            .take(4)
            .toList();

        service.submitTurn(
          sessionId: 'session-1',
          client: client,
          submittedText: 'Submit the first desktop turn.',
        );

        final snapshots = await snapshotsFuture;
        final failedTurn = snapshots[3].promptThread.turns.single;

        expect(snapshots[3].activeTurn, isNull);
        expect(failedTurn.status, TurnStatus.failed);
        expect(failedTurn.failureSummary, 'Simulated host failure.');
        expect(
          snapshots[3].notifications.map(
            (notification) => notification.transition,
          ),
          [
            SessionNotificationTransition.queuedToRunning,
            SessionNotificationTransition.runningToFailed,
          ],
        );
      },
    );

    test(
      're-observing stored session state does not duplicate notifications',
      () async {
        final service = createInMemoryHostService(
          simulationPolicy: const HostExecutionSimulationPolicy(
            queuedToRunningDelay: Duration.zero,
            runningToTerminalDelay: Duration.zero,
          ),
        );

        service.createSession(sessionId: 'session-1', activeHost: host);
        service.attachClient(sessionId: 'session-1', client: client);

        final firstSnapshots = service
            .watchSession('session-1')
            .take(4)
            .toList();
        service.submitTurn(
          sessionId: 'session-1',
          client: client,
          submittedText: 'Observe once.',
        );
        final completedSession = (await firstSnapshots).last;

        final secondSnapshots = await service
            .watchSession('session-1')
            .take(1)
            .toList();

        expect(
          secondSnapshots.single.notifications,
          completedSession.notifications,
        );
        expect(secondSnapshots.single.notifications, hasLength(2));
      },
    );

    test('submitting another turn while one is queued fails explicitly', () {
      final service = createInMemoryHostService(
        simulationPolicy: const HostExecutionSimulationPolicy(
          queuedToRunningDelay: Duration(seconds: 1),
          runningToTerminalDelay: Duration(seconds: 1),
        ),
      );

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

    test(
      'submitting another turn while one is running fails explicitly',
      () async {
        final service = createInMemoryHostService(
          simulationPolicy: const HostExecutionSimulationPolicy(
            queuedToRunningDelay: Duration.zero,
            runningToTerminalDelay: Duration(seconds: 1),
          ),
        );

        service.createSession(sessionId: 'session-1', activeHost: host);
        service.attachClient(sessionId: 'session-1', client: client);

        final snapshotsFuture = service
            .watchSession('session-1')
            .take(3)
            .toList();

        service.submitTurn(
          sessionId: 'session-1',
          client: client,
          submittedText: 'First active turn.',
        );

        final snapshots = await snapshotsFuture;
        expect(snapshots[2].activeTurn?.status, TurnStatus.running);

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
      },
    );

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

    test('restoring a duplicate session id fails explicitly', () {
      final service = createInMemoryHostService();

      service.createSession(sessionId: 'session-1', activeHost: host);

      expect(
        () =>
            service.restoreSession(Session(id: 'session-1', activeHost: host)),
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
