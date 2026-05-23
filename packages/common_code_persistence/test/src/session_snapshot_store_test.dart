import 'dart:convert';

import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  group('SessionSnapshotStore', () {
    const desktopClientId = 'client-a';

    const host = Host(id: 'host-1');
    const clientA = Client(id: 'client-a');
    const clientB = Client(id: 'client-b');

    late SharedPreferencesSessionSnapshotStore store;
    late SharedPreferences prefs;

    setUp(() async {
      // Set up mock values before getting the instance
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      store = SharedPreferencesSessionSnapshotStore(
        sharedPreferencesFactory: () async => prefs,
      );
    });

    Session buildMinimalSession() {
      return Session(
        id: 'session-1',
        activeHost: host,
        clients: const [clientA, clientB],
      );
    }

    // ========================================================================
    // Round-trip tests
    // ========================================================================

    test('writeLatestSession and readLatestSession round-trips successfully', () async {
      final session = buildMinimalSession();

      await store.writeLatestSession(session);
      final retrieved = await store.readLatestSession(desktopClientId: desktopClientId);

      expect(retrieved, isNotNull);
      expect(retrieved!.id, session.id);
      expect(retrieved.activeHost.id, session.activeHost.id);
    });

    test('readLatestSession returns null when no session written', () async {
      final retrieved = await store.readLatestSession(desktopClientId: desktopClientId);

      expect(retrieved, isNull);
    });

    test('writeLatestSession overwrites previous session', () async {
      final session1 = Session(
        id: 'session-1',
        activeHost: host,
        clients: const [clientA],
      );
      final session2 = Session(
        id: 'session-2',
        activeHost: host,
        clients: const [clientA],
      );

      await store.writeLatestSession(session1);
      await store.writeLatestSession(session2);

      final retrieved = await store.readLatestSession(desktopClientId: desktopClientId);

      expect(retrieved!.id, 'session-2');
    });

    // ========================================================================
    // Legacy v1/v2 normalization tests
    // ========================================================================

    test('readLatestSession handles v1 schema (no notifications)', () async {
      // Simulate legacy v1 data written directly to storage
      // Note: desktopClientId must be in the clientIds list for decoding to work
      final v1Payload = jsonEncode({
        'schemaVersion': 1,
        'sessionId': 'legacy-session',
        'activeHostId': 'host-1',
        'clientIds': ['client-a'], // desktopClientId must be in the list
        'turns': <Map<String, Object?>>[],
      });

      SharedPreferences.setMockInitialValues({});
      final testPrefs = await SharedPreferences.getInstance();
      await testPrefs.setString(
        SharedPreferencesSessionSnapshotStore.storageKey,
        v1Payload,
      );

      final legacyStore = SharedPreferencesSessionSnapshotStore(
        sharedPreferencesFactory: () async => testPrefs,
      );

      final retrieved = await legacyStore.readLatestSession(desktopClientId: 'client-a');

      expect(retrieved, isNotNull);
      expect(retrieved!.id, 'legacy-session');
      // v1 has no notifications by design
      expect(retrieved.notifications, isEmpty);
    });

    test('readLatestSession handles v2 schema', () async {
      final session = buildMinimalSession();
      await store.writeLatestSession(session);

      final retrieved = await store.readLatestSession(desktopClientId: desktopClientId);

      expect(retrieved, isNotNull);
      expect(retrieved!.id, session.id);
    });

    test('readLatestSession returns null on decode failure', () async {
      // Write corrupt data directly to storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SharedPreferencesSessionSnapshotStore.storageKey,
        'not valid json{',
      );

      final corruptStore = SharedPreferencesSessionSnapshotStore(
        sharedPreferencesFactory: () async => prefs,
      );

      final retrieved = await corruptStore.readLatestSession(desktopClientId: desktopClientId);

      expect(retrieved, isNull);
    });

    test('readLatestSession returns null when snapshot missing desktop client id', () async {
      // Write a session that doesn't contain the requesting desktop client
      final v2Payload = jsonEncode({
        'schemaVersion': 2,
        'sessionId': 'session-other-client',
        'activeHostId': 'host-1',
        'clientIds': ['other-client'], // Different client
        'turns': <Map<String, Object?>>[],
        'notifications': <Map<String, Object?>>[],
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SharedPreferencesSessionSnapshotStore.storageKey,
        v2Payload,
      );

      final otherClientStore = SharedPreferencesSessionSnapshotStore(
        sharedPreferencesFactory: () async => prefs,
      );

      final retrieved = await otherClientStore.readLatestSession(desktopClientId: desktopClientId);

      expect(retrieved, isNull);
    });

    // ========================================================================
    // Failure case tests
    // ========================================================================

    test('readLatestSession returns null on corrupt storage data', () async {
      // Write corrupt/invalid JSON data directly
      SharedPreferences.setMockInitialValues({});
      final testPrefs = await SharedPreferences.getInstance();
      await testPrefs.setString(
        SharedPreferencesSessionSnapshotStore.storageKey,
        'not valid json{',
      );

      final store = SharedPreferencesSessionSnapshotStore(
        sharedPreferencesFactory: () async => testPrefs,
      );

      final retrieved = await store.readLatestSession(desktopClientId: desktopClientId);

      // decode failure returns null (caught by try-catch in store)
      expect(retrieved, isNull);
    });
  });

  group('SharedPreferencesSessionSnapshotStore', () {
    test('uses correct storage key', () {
      expect(
        SharedPreferencesSessionSnapshotStore.storageKey,
        'common_code.desktop.latest_session_snapshot.v1',
      );
    });
  });
}
