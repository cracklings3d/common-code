import 'dart:async';

import 'package:common_code_domain/common_code_domain.dart';
import 'package:host_core/host_core.dart';

import 'in_memory_host_service.dart';

/// In-memory host adapter that owns session storage, turn simulation,
/// and session observation lifecycle.
///
/// This adapter implements the [HostService] contract for pure in-memory
/// session management, without any durable write semantics.
class InMemoryHostAdapter implements HostService {
  InMemoryHostAdapter({
    HostExecutionSimulationPolicy simulationPolicy =
        const HostExecutionSimulationPolicy(),
  }) : _simulationPolicy = simulationPolicy;

  final HostExecutionSimulationPolicy _simulationPolicy;
  final Map<String, Session> _sessionsById = <String, Session>{};
  final Map<String, StreamController<Session>> _sessionWatchControllersById =
      <String, StreamController<Session>>{};

  @override
  Session attachClient({required String sessionId, required Client client}) {
    final session = _readStoredSession(sessionId);
    final updatedSession = session.attachClient(client);
    _sessionsById[sessionId] = updatedSession;
    _sessionWatchControllersById[sessionId]?.add(updatedSession);
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
    _sessionsById[sessionId] = updatedSession;
    _sessionWatchControllersById[sessionId]?.add(updatedSession);
    return updatedSession;
  }

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
  Session readSession(String sessionId) => _readStoredSession(sessionId);

  @override
  Session restoreSession(Session session) {
    return _restoreSession(session: session);
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
    _sessionsById[sessionId] = updatedSession;
    _sessionWatchControllersById[sessionId]?.add(updatedSession);
    _scheduleSimulatedExecution(
      sessionId: sessionId,
      turnId: updatedSession.activeTurn!.id,
    );
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

  Session _restoreSession({required Session session}) {
    if (_sessionsById.containsKey(session.id)) {
      throw HostServiceFailure(
        HostServiceFailureCode.duplicateSessionId,
        'Session ${session.id} already exists.',
      );
    }

    _sessionsById[session.id] = session;
    return session;
  }

  String _nextTurnId(Session session) =>
      'turn-${session.promptThread.turns.length + 1}';

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
    _sessionsById[sessionId] = updatedSession;
    _sessionWatchControllersById[sessionId]?.add(updatedSession);
    return updatedSession;
  }
}
