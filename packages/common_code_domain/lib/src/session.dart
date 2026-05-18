import 'client.dart';
import 'host.dart';
import 'prompt_thread.dart';
import 'session_failure.dart';
import 'turn.dart';

final class Session {
  Session({
    required this.id,
    required this.activeHost,
    Iterable<Client> clients = const [],
    PromptThread? promptThread,
  }) : clients = List.unmodifiable(clients),
       promptThread = promptThread ?? PromptThread() {
    _validateClientIdsAreUnique(this.clients);
    _validateActiveTurnInputClient(this.clients, this.promptThread);
  }

  final String id;
  final Host activeHost;
  final List<Client> clients;
  final PromptThread promptThread;

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
        Turn.active(
          id: turnId,
          clientId: client.id,
          submittedText: submittedText,
        ),
      ),
    );
  }

  Session completeActiveTurn() {
    final currentTurn = activeTurn;
    if (currentTurn == null) {
      throw const SessionFailure(
        SessionFailureCode.noActiveTurn,
        'Cannot complete a turn when no active turn exists.',
      );
    }

    final updatedTurns = [
      for (final turn in promptThread.turns)
        if (turn.id == currentTurn.id) currentTurn.complete() else turn,
    ];

    return Session(
      id: id,
      activeHost: activeHost,
      clients: clients,
      promptThread: PromptThread(turns: updatedTurns),
    );
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

  @override
  String toString() {
    return 'Session(id: $id, activeHost: $activeHost, clients: $clients, '
        'promptThread: $promptThread)';
  }
}
