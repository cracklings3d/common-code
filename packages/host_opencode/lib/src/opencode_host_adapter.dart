import 'dart:async';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:meta/meta.dart';

import 'opencode_host_gateway.dart';
import 'opencode_session_observation.dart';

/// Simulation policy for OpenCode host execution timing and outcomes.
final class OpenCodeHostExecutionSimulationPolicy {
  const OpenCodeHostExecutionSimulationPolicy({
    this.queuedToRunningDelay = const Duration(milliseconds: 200),
    this.runningToTerminalDelay = const Duration(milliseconds: 200),
    this.terminalOutcome = OpenCodeSimulatedTurnTerminalOutcome.completed,
    this.failureSummary = 'Simulated OpenCode host execution failed.',
  });

  final Duration queuedToRunningDelay;
  final Duration runningToTerminalDelay;
  final OpenCodeSimulatedTurnTerminalOutcome terminalOutcome;
  final String failureSummary;
}

/// Terminal outcome for simulated turn execution.
enum OpenCodeSimulatedTurnTerminalOutcome { completed, failed }

/// OpenCode host adapter that delegates to the OpenCode gateway and observation
/// implementations while implementing the [HostService] contract.
///
/// This adapter provides OpenCode-specific session management by composing:
/// - [OpenCodeHostGateway] for turn submission
/// - [OpenCodeHostServiceSessionObservation] for session watching
///
/// The adapter-local translation between CommonCode contracts and OpenCode-specific
/// vocabulary is handled in [opencode_mapping.dart].
@visibleForTesting
final class OpenCodeHostAdapter implements HostService {
  OpenCodeHostAdapter({
    OpenCodeHostExecutionSimulationPolicy simulationPolicy =
        const OpenCodeHostExecutionSimulationPolicy(),
  }) : _simulationPolicy = simulationPolicy;

  final OpenCodeHostExecutionSimulationPolicy _simulationPolicy;
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
            OpenCodeSimulatedTurnTerminalOutcome.completed =>
              session.completeActiveTurn(),
            OpenCodeSimulatedTurnTerminalOutcome.failed => session.failActiveTurn(
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

/// Creates an OpenCode host adapter instance.
///
/// This is a convenience factory for desktop composition to create
/// the OpenCode host adapter without directly instantiating the class.
OpenCodeHostAdapter createOpenCodeHostAdapter({
  OpenCodeHostExecutionSimulationPolicy simulationPolicy =
      const OpenCodeHostExecutionSimulationPolicy(),
}) =>
    OpenCodeHostAdapter(simulationPolicy: simulationPolicy);
