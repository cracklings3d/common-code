enum SessionNotificationTransition {
  queuedToRunning,
  runningToCompleted,
  runningToFailed,
}

final class SessionNotification {
  const SessionNotification._({
    required this.id,
    required this.turnId,
    required this.transition,
    required this.isAcknowledged,
  });

  factory SessionNotification.forTransition({
    required String sessionId,
    required String turnId,
    required SessionNotificationTransition transition,
    bool isAcknowledged = false,
  }) {
    return SessionNotification._(
      id: deterministicId(
        sessionId: sessionId,
        turnId: turnId,
        transition: transition,
      ),
      turnId: turnId,
      transition: transition,
      isAcknowledged: isAcknowledged,
    );
  }

  static String deterministicId({
    required String sessionId,
    required String turnId,
    required SessionNotificationTransition transition,
  }) {
    return '$sessionId:$turnId:${transition.name}';
  }

  final String id;
  final String turnId;
  final SessionNotificationTransition transition;
  final bool isAcknowledged;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SessionNotification &&
            other.id == id &&
            other.turnId == turnId &&
            other.transition == transition &&
            other.isAcknowledged == isAcknowledged;
  }

  @override
  int get hashCode => Object.hash(id, turnId, transition, isAcknowledged);

  @override
  String toString() {
    return 'SessionNotification(id: $id, turnId: $turnId, transition: '
        '$transition, isAcknowledged: $isAcknowledged)';
  }
}
