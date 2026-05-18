import 'turn.dart';
import 'session_failure.dart';

final class PromptThread {
  PromptThread({Iterable<Turn> turns = const []})
    : turns = List.unmodifiable(turns) {
    final activeTurnCount = this.turns.where((turn) => turn.isActive).length;
    if (activeTurnCount > 1) {
      throw const SessionFailure(
        SessionFailureCode.invalidActiveTurnCount,
        'A prompt thread cannot contain more than one active turn.',
      );
    }
  }

  final List<Turn> turns;

  Turn? get activeTurn {
    for (final turn in turns) {
      if (turn.isActive) {
        return turn;
      }
    }

    return null;
  }

  PromptThread append(Turn turn) => PromptThread(turns: [...turns, turn]);

  @override
  String toString() => 'PromptThread(turns: $turns)';
}
