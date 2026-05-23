import 'package:common_code_domain/common_code_domain.dart';

const int sessionSnapshotSchemaVersion = 2;

final class SessionSnapshotCodec {
  const SessionSnapshotCodec();

  Map<String, Object?> encode(Session session) {
    return <String, Object?>{
      'schemaVersion': sessionSnapshotSchemaVersion,
      'sessionId': session.id,
      'activeHostId': session.activeHost.id,
      'clientIds': <String>[for (final client in session.clients) client.id],
      'turns': <Map<String, Object?>>[
        for (final turn in session.promptThread.turns) _encodeTurn(turn),
      ],
      'notifications': <Map<String, Object?>>[
        for (final notification in session.notifications)
          _encodeNotification(notification),
      ],
    };
  }

  Session decode(Object? payload, {required String desktopClientId}) {
    final map = _asMap(payload, fieldName: 'snapshot');
    final schemaVersion = map['schemaVersion'];
    if (schemaVersion != 1 && schemaVersion != sessionSnapshotSchemaVersion) {
      throw FormatException('Unknown schema version: $schemaVersion');
    }

    final sessionId = _asString(map, fieldName: 'sessionId');
    final clientIds = _asStringList(map['clientIds'], fieldName: 'clientIds');
    if (!clientIds.contains(desktopClientId)) {
      throw const FormatException(
        'Stored snapshot is missing the desktop client id.',
      );
    }

    final turns = _asList(
      map['turns'],
      fieldName: 'turns',
    ).map(_decodeTurn).toList(growable: false);
    final notifications = switch (schemaVersion) {
      1 => const <SessionNotification>[],
      _ =>
        _asList(map['notifications'], fieldName: 'notifications')
            .map(
              (notification) =>
                  _decodeNotification(notification, sessionId: sessionId),
            )
            .toList(growable: false),
    };

    return Session(
      id: sessionId,
      activeHost: Host(id: _asString(map, fieldName: 'activeHostId')),
      clients: clientIds.map((clientId) => Client(id: clientId)),
      promptThread: PromptThread(turns: turns),
      notifications: notifications,
    );
  }

  Map<String, Object?> _encodeTurn(Turn turn) {
    return <String, Object?>{
      'id': turn.id,
      'clientId': turn.clientId,
      'submittedText': turn.submittedText,
      'status': turn.status.name,
      'failureSummary': turn.failureSummary,
    };
  }

  Map<String, Object?> _encodeNotification(SessionNotification notification) {
    return <String, Object?>{
      'id': notification.id,
      'turnId': notification.turnId,
      'transition': notification.transition.name,
      'isAcknowledged': notification.isAcknowledged,
    };
  }

  Turn _decodeTurn(Object? payload) {
    final map = _asMap(payload, fieldName: 'turn');
    final id = _asString(map, fieldName: 'id');
    final clientId = _asString(map, fieldName: 'clientId');
    final submittedText = _asString(map, fieldName: 'submittedText');
    final status = _asString(map, fieldName: 'status');
    final failureSummary = map['failureSummary'];

    return switch (status) {
      'queued' when failureSummary == null => Turn.queued(
        id: id,
        clientId: clientId,
        submittedText: submittedText,
      ),
      'running' when failureSummary == null => Turn.running(
        id: id,
        clientId: clientId,
        submittedText: submittedText,
      ),
      'completed' when failureSummary == null => Turn.completed(
        id: id,
        clientId: clientId,
        submittedText: submittedText,
      ),
      'failed' when failureSummary is String => Turn.failed(
        id: id,
        clientId: clientId,
        submittedText: submittedText,
        failureSummary: failureSummary,
      ),
      _ => throw FormatException('Invalid turn payload for status: $status'),
    };
  }

  SessionNotification _decodeNotification(
    Object? payload, {
    required String sessionId,
  }) {
    final map = _asMap(payload, fieldName: 'notification');
    final id = _asString(map, fieldName: 'id');
    final turnId = _asString(map, fieldName: 'turnId');
    final transitionName = _asString(map, fieldName: 'transition');
    final isAcknowledged = _asBool(
      map['isAcknowledged'],
      fieldName: 'isAcknowledged',
    );
    final transition = SessionNotificationTransition.values.where(
      (value) => value.name == transitionName,
    );
    if (transition.isEmpty) {
      throw FormatException('Invalid notification transition: $transitionName');
    }

    final notification = SessionNotification.forTransition(
      sessionId: sessionId,
      turnId: turnId,
      transition: transition.single,
      isAcknowledged: isAcknowledged,
    );
    if (notification.id != id) {
      throw const FormatException(
        'Notification id does not match transition identity.',
      );
    }

    return notification;
  }

  Map<Object?, Object?> _asMap(Object? value, {required String fieldName}) {
    if (value is! Map<Object?, Object?>) {
      throw FormatException('$fieldName must be a JSON object.');
    }

    return value;
  }

  List<Object?> _asList(Object? value, {required String fieldName}) {
    if (value is! List<Object?>) {
      throw FormatException('$fieldName must be a JSON array.');
    }

    return value;
  }

  String _asString(Map<Object?, Object?> map, {required String fieldName}) {
    final value = map[fieldName];
    if (value is! String) {
      throw FormatException('$fieldName must be a string.');
    }

    return value;
  }

  List<String> _asStringList(Object? value, {required String fieldName}) {
    final list = _asList(value, fieldName: fieldName);

    return list
        .map((entry) {
          if (entry is! String) {
            throw FormatException('$fieldName entries must be strings.');
          }

          return entry;
        })
        .toList(growable: false);
  }

  bool _asBool(Object? value, {required String fieldName}) {
    if (value is! bool) {
      throw FormatException('$fieldName must be a bool.');
    }

    return value;
  }
}
