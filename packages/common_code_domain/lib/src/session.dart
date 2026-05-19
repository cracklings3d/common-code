import 'client.dart';
import 'host.dart';
import 'prompt_thread.dart';
import 'session_failure.dart';
import 'session_notification.dart';
import 'turn.dart';

final class Session {
  Session({
    required this.id,
    required this.activeHost,
    Iterable<Client> clients = const [],
    PromptThread? promptThread,
    Iterable<SessionNotification> notifications = const [],
  }) : clients = List.unmodifiable(clients),
       promptThread = promptThread ?? PromptThread(),
       notifications = List.unmodifiable(notifications) {
    _validateClientIdsAreUnique(this.clients);
    _validateActiveTurnInputClient(this.clients, this.promptThread);
    _validateNotificationIdsAreUnique(this.notifications);
  }

  final String id;
  final Host activeHost;
  final List<Client> clients;
  final PromptThread promptThread;
  final List<SessionNotification> notifications;

  Turn? get activeTurn => promptThread.activeTurn;

  Client? get inputClient {
    final currentTurn = activeTurn;
    if (currentTurn == null) {
      return null;
    }

    return _clientById(currentTurn.clientId);
  }

  Session replaceActiveHost(Host nextHost) {
    return Session(
      id: id,
      activeHost: nextHost,
      clients: clients,
      promptThread: promptThread,
      notifications: notifications,
    );
  }

  Session attachClient(Client client) {
    if (_hasAttachedClient(client.id)) {
      throw SessionFailure(
        SessionFailureCode.duplicateClientId,
        'Client ${client.id} is already attached to session $id.',
      );
    }

    return Session(
      id: id,
      activeHost: activeHost,
      clients: [...clients, client],
      promptThread: promptThread,
      notifications: notifications,
    );
  }

  Session startTurn({
    required String turnId,
    required Client client,
    required String submittedText,
  }) {
    if (activeTurn != null) {
      throw const SessionFailure(
        SessionFailureCode.activeTurnAlreadyExists,
        'Cannot start a new turn while another turn is active.',
      );
    }

    if (!_hasAttachedClient(client.id)) {
      throw SessionFailure(
        SessionFailureCode.clientNotAttached,
        'Client ${client.id} is not attached to session $id.',
      );
    }

    return Session(
      id: id,
      activeHost: activeHost,
      clients: clients,
      promptThread: promptThread.append(
        Turn.queued(
          id: turnId,
          clientId: client.id,
          submittedText: submittedText,
        ),
      ),
      notifications: notifications,
    );
  }

  Session advanceActiveTurnToRunning() {
    return _replaceActiveTurn((turn) => turn.queueToRunning());
  }

  Session completeActiveTurn() {
    return _replaceActiveTurn((turn) => turn.complete());
  }

  Session failActiveTurn({required String failureSummary}) {
    return _replaceActiveTurn((turn) => turn.fail(failureSummary));
  }

  bool _hasAttachedClient(String clientId) => _clientById(clientId) != null;

  Client? _clientById(String clientId) {
    for (final client in clients) {
      if (client.id == clientId) {
        return client;
      }
    }

    return null;
  }

  static void _validateClientIdsAreUnique(List<Client> clients) {
    final clientIds = clients.map((client) => client.id).toSet();
    if (clientIds.length != clients.length) {
      throw const SessionFailure(
        SessionFailureCode.duplicateClientId,
        'A session cannot contain duplicate client ids.',
      );
    }
  }

  static void _validateActiveTurnInputClient(
    List<Client> clients,
    PromptThread promptThread,
  ) {
    final currentTurn = promptThread.activeTurn;
    if (currentTurn == null) {
      return;
    }

    final hasMatchingClient = clients.any(
      (client) => client.id == currentTurn.clientId,
    );
    if (!hasMatchingClient) {
      throw SessionFailure(
        SessionFailureCode.inputClientNotAttached,
        'Active turn client ${currentTurn.clientId} must be attached to the '
        'session.',
      );
    }
  }

  static void _validateNotificationIdsAreUnique(
    List<SessionNotification> notifications,
  ) {
    final notificationIds = notifications
        .map((notification) => notification.id)
        .toSet();
    if (notificationIds.length != notifications.length) {
      throw StateError('A session cannot contain duplicate notification ids.');
    }
  }

  Session _replaceActiveTurn(Turn Function(Turn currentTurn) updateTurn) {
    final currentTurn = activeTurn;
    if (currentTurn == null) {
      throw const SessionFailure(
        SessionFailureCode.noActiveTurn,
        'Cannot update a turn when no active turn exists.',
      );
    }

    final updatedTurn = updateTurn(currentTurn);

    final updatedTurns = [
      for (final turn in promptThread.turns)
        if (turn.id == currentTurn.id) updatedTurn else turn,
    ];

    return Session(
      id: id,
      activeHost: activeHost,
      clients: clients,
      promptThread: PromptThread(turns: updatedTurns),
      notifications: _appendNotificationForTransition(
        previousTurn: currentTurn,
        updatedTurn: updatedTurn,
      ),
    );
  }

  List<SessionNotification> _appendNotificationForTransition({
    required Turn previousTurn,
    required Turn updatedTurn,
  }) {
    final transition = switch ((previousTurn.status, updatedTurn.status)) {
      (TurnStatus.queued, TurnStatus.running) =>
        SessionNotificationTransition.queuedToRunning,
      (TurnStatus.running, TurnStatus.completed) =>
        SessionNotificationTransition.runningToCompleted,
      (TurnStatus.running, TurnStatus.failed) =>
        SessionNotificationTransition.runningToFailed,
      _ => null,
    };
    if (transition == null) {
      return notifications;
    }

    final notificationId = SessionNotification.deterministicId(
      sessionId: id,
      turnId: updatedTurn.id,
      transition: transition,
    );
    if (notifications.any(
      (notification) => notification.id == notificationId,
    )) {
      return notifications;
    }

    return [
      ...notifications,
      SessionNotification.forTransition(
        sessionId: id,
        turnId: updatedTurn.id,
        transition: transition,
      ),
    ];
  }

  @override
  String toString() {
    return 'Session(id: $id, activeHost: $activeHost, clients: $clients, '
        'promptThread: $promptThread, notifications: $notifications)';
  }
}
