import 'dart:convert';

import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:test/test.dart';

void main() {
  group('SessionSnapshotCodec', () {
    const codec = SessionSnapshotCodec();
    // desktopClientId must be one of the clients in the session for decoding to work
    const desktopClientId = 'client-a';

    const host = Host(id: 'host-1');
    const clientA = Client(id: 'client-a');
    const clientB = Client(id: 'client-b');

    Session buildMinimalSession() {
      return Session(
        id: 'session-1',
        activeHost: host,
        clients: const [clientA, clientB],
      );
    }

    Session buildSessionWithTurns() {
      return Session(
        id: 'session-1',
        activeHost: host,
        clients: const [clientA, clientB],
      ).startTurn(
        turnId: 'turn-1',
        client: clientA,
        submittedText: 'Hello, world.',
      );
    }

    Session buildSessionWithCompletedTurn() {
      return Session(
        id: 'session-1',
        activeHost: host,
        clients: const [clientA, clientB],
      )
          .startTurn(
            turnId: 'turn-1',
            client: clientA,
            submittedText: 'Hello, world.',
          )
          .advanceActiveTurnToRunning()
          .completeActiveTurn();
    }

    Session buildSessionWithFailedTurn() {
      return Session(
        id: 'session-1',
        activeHost: host,
        clients: const [clientA, clientB],
      )
          .startTurn(
            turnId: 'turn-1',
            client: clientA,
            submittedText: 'Hello, world.',
          )
          .advanceActiveTurnToRunning()
          .failActiveTurn(failureSummary: 'Host crashed.');
    }

    // ========================================================================
    // Schema versioning tests
    // ========================================================================

    test('encodes with current schema version', () {
      final session = buildMinimalSession();
      final encoded = codec.encode(session);

      expect(encoded['schemaVersion'], sessionSnapshotSchemaVersion);
      expect(encoded['schemaVersion'], 2);
    });

    test('decode rejects unknown schema version', () {
      final payload = jsonEncode({
        'schemaVersion': 99,
        'sessionId': 'session-1',
        'activeHostId': 'host-1',
        'clientIds': [desktopClientId],
        'turns': <Map<String, Object?>>[],
        'notifications': <Map<String, Object?>>[],
      });

      expect(
        () => codec.decode(jsonDecode(payload), desktopClientId: desktopClientId),
        throwsA(isA<FormatException>()),
      );
    });

    test('decode accepts schema version 1 (legacy)', () {
      final payload = jsonEncode({
        'schemaVersion': 1,
        'sessionId': 'session-1',
        'activeHostId': 'host-1',
        'clientIds': [desktopClientId],
        'turns': <Map<String, Object?>>[],
      });

      final session = codec.decode(jsonDecode(payload), desktopClientId: desktopClientId);

      expect(session.id, 'session-1');
      expect(session.activeHost.id, 'host-1');
    });

    test('decode accepts current schema version', () {
      final session = buildMinimalSession();
      final encoded = codec.encode(session);

      final decoded = codec.decode(encoded, desktopClientId: desktopClientId);

      expect(decoded.id, session.id);
      expect(decoded.activeHost.id, session.activeHost.id);
    });

    // ========================================================================
    // Codec symmetry tests
    // ========================================================================

    test('round-trip preserves minimal session', () {
      final original = buildMinimalSession();
      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded, desktopClientId: desktopClientId);

      expect(decoded.id, original.id);
      expect(decoded.activeHost.id, original.activeHost.id);
      expect(decoded.clients.map((c) => c.id), original.clients.map((c) => c.id));
      expect(decoded.promptThread.turns, original.promptThread.turns);
      expect(decoded.notifications, original.notifications);
    });

    test('round-trip preserves session with queued turn', () {
      final original = buildSessionWithTurns();
      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded, desktopClientId: desktopClientId);

      expect(decoded.id, original.id);
      expect(decoded.activeTurn?.id, original.activeTurn?.id);
      expect(decoded.activeTurn?.status, original.activeTurn?.status);
      expect(decoded.activeTurn?.submittedText, original.activeTurn?.submittedText);
    });

    test('round-trip preserves session with completed turn', () {
      final original = buildSessionWithCompletedTurn();
      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded, desktopClientId: desktopClientId);

      expect(decoded.id, original.id);
      expect(decoded.promptThread.turns.length, 1);
      expect(decoded.promptThread.turns.first.status, TurnStatus.completed);
    });

    test('round-trip preserves session with failed turn', () {
      final original = buildSessionWithFailedTurn();
      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded, desktopClientId: desktopClientId);

      expect(decoded.id, original.id);
      expect(decoded.promptThread.turns.length, 1);
      expect(decoded.promptThread.turns.first.status, TurnStatus.failed);
      expect(
        decoded.promptThread.turns.first.failureSummary,
        'Host crashed.',
      );
    });

    test('round-trip preserves multiple clients', () {
      final original = Session(
        id: 'session-1',
        activeHost: host,
        clients: const [clientA, clientB],
      );
      final encoded = codec.encode(original);
      final decoded = codec.decode(encoded, desktopClientId: desktopClientId);

      expect(decoded.clients.length, 2);
      expect(decoded.clients.map((c) => c.id), ['client-a', 'client-b']);
    });

    test('round-trip preserves notifications in v2 schema', () {
      final session = buildSessionWithCompletedTurn();
      final encoded = codec.encode(session);
      final decoded = codec.decode(encoded, desktopClientId: desktopClientId);

      // Notifications are generated by the session state transitions
      expect(decoded.notifications, isNotEmpty);
    });

    test('v1 schema returns empty notifications on decode', () {
      final payload = jsonEncode({
        'schemaVersion': 1,
        'sessionId': 'session-1',
        'activeHostId': 'host-1',
        'clientIds': [desktopClientId],
        'turns': <Map<String, Object?>>[],
      });

      final session = codec.decode(jsonDecode(payload), desktopClientId: desktopClientId);

      expect(session.notifications, isEmpty);
    });

    // ========================================================================
    // Failure case tests
    // ========================================================================

    test('decode throws when snapshot is missing desktop client id', () {
      final payload = jsonEncode({
        'schemaVersion': 2,
        'sessionId': 'session-1',
        'activeHostId': 'host-1',
        'clientIds': ['other-client'], // Does not contain desktopClientId
        'turns': <Map<String, Object?>>[],
        'notifications': <Map<String, Object?>>[],
      });

      expect(
        () => codec.decode(jsonDecode(payload), desktopClientId: desktopClientId),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Stored snapshot is missing the desktop client id.',
          ),
        ),
      );
    });

    test('decode throws on invalid turn status', () {
      final payload = jsonEncode({
        'schemaVersion': 2,
        'sessionId': 'session-1',
        'activeHostId': 'host-1',
        'clientIds': [desktopClientId],
        'turns': [
          {
            'id': 'turn-1',
            'clientId': 'client-a',
            'submittedText': 'Hello',
            'status': 'invalid-status',
          },
        ],
        'notifications': <Map<String, Object?>>[],
      });

      expect(
        () => codec.decode(jsonDecode(payload), desktopClientId: desktopClientId),
        throwsA(isA<FormatException>()),
      );
    });

    test('decode throws on failed turn without failureSummary', () {
      final payload = jsonEncode({
        'schemaVersion': 2,
        'sessionId': 'session-1',
        'activeHostId': 'host-1',
        'clientIds': [desktopClientId],
        'turns': [
          {
            'id': 'turn-1',
            'clientId': 'client-a',
            'submittedText': 'Hello',
            'status': 'failed',
            // missing failureSummary
          },
        ],
        'notifications': <Map<String, Object?>>[],
      });

      expect(
        () => codec.decode(jsonDecode(payload), desktopClientId: desktopClientId),
        throwsA(isA<FormatException>()),
      );
    });

    test('decode throws on invalid notification transition', () {
      final payload = jsonEncode({
        'schemaVersion': 2,
        'sessionId': 'session-1',
        'activeHostId': 'host-1',
        'clientIds': [desktopClientId],
        'turns': <Map<String, Object?>>[],
        'notifications': [
          {
            'id': 'notif-1',
            'turnId': 'turn-1',
            'transition': 'invalid-transition',
            'isAcknowledged': false,
          },
        ],
      });

      expect(
        () => codec.decode(jsonDecode(payload), desktopClientId: desktopClientId),
        throwsA(isA<FormatException>()),
      );
    });

    test('decode throws when payload is not a map', () {
      expect(
        () => codec.decode('not a map', desktopClientId: desktopClientId),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => codec.decode(123, desktopClientId: desktopClientId),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => codec.decode(null, desktopClientId: desktopClientId),
        throwsA(isA<FormatException>()),
      );
    });

    test('decode throws on missing required fields', () {
      final payload = jsonEncode({
        'schemaVersion': 2,
        // missing sessionId
        'activeHostId': 'host-1',
        'clientIds': [desktopClientId],
        'turns': <Map<String, Object?>>[],
        'notifications': <Map<String, Object?>>[],
      });

      expect(
        () => codec.decode(jsonDecode(payload), desktopClientId: desktopClientId),
        throwsA(isA<FormatException>()),
      );
    });

    test('decode throws when clientIds is not a list', () {
      final payload = jsonEncode({
        'schemaVersion': 2,
        'sessionId': 'session-1',
        'activeHostId': 'host-1',
        'clientIds': 'not-a-list',
        'turns': <Map<String, Object?>>[],
        'notifications': <Map<String, Object?>>[],
      });

      expect(
        () => codec.decode(jsonDecode(payload), desktopClientId: desktopClientId),
        throwsA(isA<FormatException>()),
      );
    });

    test('decode throws when turns contains non-map entry', () {
      final payload = jsonEncode({
        'schemaVersion': 2,
        'sessionId': 'session-1',
        'activeHostId': 'host-1',
        'clientIds': [desktopClientId],
        'turns': ['not-a-map'],
        'notifications': <Map<String, Object?>>[],
      });

      expect(
        () => codec.decode(jsonDecode(payload), desktopClientId: desktopClientId),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
