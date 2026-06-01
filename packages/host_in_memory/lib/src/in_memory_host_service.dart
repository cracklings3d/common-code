import 'dart:async';

import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_application/common_code_application.dart';

enum SimulatedTurnTerminalOutcome { completed, failed }

final class HostExecutionSimulationPolicy {
  const HostExecutionSimulationPolicy({
    this.queuedToRunningDelay = const Duration(milliseconds: 200),
    this.runningToTerminalDelay = const Duration(milliseconds: 200),
    this.terminalOutcome = SimulatedTurnTerminalOutcome.completed,
    this.failureSummary = 'Simulated host execution failed.',
  });

  final Duration queuedToRunningDelay;
  final Duration runningToTerminalDelay;
  final SimulatedTurnTerminalOutcome terminalOutcome;
  final String failureSummary;
}

HostService createInMemoryHostService({
  HostExecutionSimulationPolicy simulationPolicy =
      const HostExecutionSimulationPolicy(),
}) =>
    _InMemoryHostService(simulationPolicy: simulationPolicy);

final class _InMemoryHostService implements HostService {
  _InMemoryHostService({
    required HostExecutionSimulationPolicy simulationPolicy,
  }) : _simulationPolicy = simulationPolicy;

  final Map<String, Session> _sessionsById = <String, Session>{};
  final Map<String, StreamController<Session>> _sessionWatchControllersById =
      <String, StreamController<Session>>{};
  final HostExecutionSimulationPolicy _simulationPolicy;

  @override
  Session createSession({required String sessionId, required Host activeHost}) {
    if (_sessionsById.containsKey(sessionId)) {
      throw HostServiceFailure(
        HostServiceFailureCode.duplicateSessionId,
        'Session $sessionId already exists.',
      );
    }

    final session = Session(id: sessionId, activeHost: activeHost);
    _persistSession(sessionId, session);
    return session;
  }

  @override
  Session attachClient({required String sessionId, required Client client}) {
    final session = _readStoredSession(sessionId);
    final updatedSession = session.attachClient(client);
    _persistSession(sessionId, updatedSession);
    return updatedSession;
  }

  @override
  Session acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  }) {
    final session = _readStoredSession(sessionId);
    var didAcknowledge = false;
    final updatedNotifications = [
      for (final notification in session.notifications)
        if (notification.id == notificationId && !notification.isAcknowledged)
          () {
            didAcknowledge = true;
            return SessionNotification.forTransition(
              sessionId: session.id,
              turnId: notification.turnId,
              transition: notification.transition,
              isAcknowledged: true,
            );
          }()
        else
          notification,
    ];

    if (!didAcknowledge) {
      return session;
    }

    final updatedSession = Session(
      id: session.id,
      activeHost: session.activeHost,
      clients: session.clients,
      promptThread: session.promptThread,
      notifications: updatedNotifications,
    );
    _persistSession(sessionId, updatedSession);
    return updatedSession;
  }

  @override
  Stream<Session> watchSession(String sessionId) {
    _readStoredSession(sessionId);

    if (_sessionWatchControllersById.containsKey(sessionId)) {
      throw HostServiceFailure(
        HostServiceFailureCode.activeSessionWatchAlreadyExists,
        'Session $sessionId already has an active watch.',
      );
    }

    late final StreamController<Session> controller;
    controller = StreamController<Session>(
      sync: true,
      onListen: () {
        _sessionWatchControllersById[sessionId] = controller;
        controller.add(_readStoredSession(sessionId));
      },
      onCancel: () {
        _sessionWatchControllersById.remove(sessionId);
      },
    );

    return controller.stream;
  }

  @override
  Session restoreSession(Session session) {
    if (_sessionsById.containsKey(session.id)) {
      throw HostServiceFailure(
        HostServiceFailureCode.duplicateSessionId,
        'Session ${session.id} already exists.',
      );
    }

    _persistSession(session.id, session);
    return session;
  }

  @override
  Session submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) {
    final session = _readStoredSession(sessionId);
    final updatedSession = session.startTurn(
      turnId: _nextTurnId(session),
      client: client,
      submittedText: submittedText,
    );
    _persistSession(sessionId, updatedSession);
    _scheduleSimulatedExecution(
      sessionId: sessionId,
      turnId: updatedSession.activeTurn!.id,
    );
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

  void _persistSession(String sessionId, Session session) {
    _sessionsById[sessionId] = session;
    _sessionWatchControllersById[sessionId]?.add(session);
  }

  void _scheduleSimulatedExecution({
    required String sessionId,
    required String turnId,
  }) {
    Timer(_simulationPolicy.queuedToRunningDelay, () {
      final runningSession = _advanceTurnIfStillActive(
        sessionId: sessionId,
        turnId: turnId,
        expectedStatus: TurnStatus.queued,
        update: (session) => session.advanceActiveTurnToRunning(),
      );

      if (runningSession == null) {
        return;
      }

      Timer(_simulationPolicy.runningToTerminalDelay, () {
        _advanceTurnIfStillActive(
          sessionId: sessionId,
          turnId: turnId,
          expectedStatus: TurnStatus.running,
          update: (session) => switch (_simulationPolicy.terminalOutcome) {
            SimulatedTurnTerminalOutcome.completed =>
              session.completeActiveTurn(),
            SimulatedTurnTerminalOutcome.failed => session.failActiveTurn(
                failureSummary: _simulationPolicy.failureSummary,
              ),
          },
        );
      });
    });
  }

  Session? _advanceTurnIfStillActive({
    required String sessionId,
    required String turnId,
    required TurnStatus expectedStatus,
    required Session Function(Session session) update,
  }) {
    final session = _sessionsById[sessionId];
    final currentTurn = session?.activeTurn;
    if (session == null ||
        currentTurn == null ||
        currentTurn.id != turnId ||
        currentTurn.status != expectedStatus) {
      return null;
    }

    final updatedSession = update(session);
    _persistSession(sessionId, updatedSession);
    return updatedSession;
  }

  String _nextTurnId(Session session) =>
      'turn-${session.promptThread.turns.length + 1}';
}
