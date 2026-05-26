import 'dart:async';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:test/test.dart';

void main() {
  group('DurableLocalSessionStore', () {
    test('durable read failures preserve error and stack trace', () async {
      final readError = StateError('read boom');
      final store = DurableLocalSessionStore(
        durableStorage: _FakeDurableSessionStore(readError: readError),
        legacySnapshotStore: _FakeSessionSnapshotStore(),
      );

      final result = await store.loadDurableSessionCandidate(
        attachedClientId: 'desktop-client',
      );

      expect(result.status, CommonCodeDurableBootstrapLoadStatus.readFailed);
      expect(result.error, same(readError));
      expect(result.stackTrace, isNotNull);
    });

    test('legacy seed failures preserve error and stack trace', () async {
      final eligibilityError = StateError('eligibility boom');
      final store = DurableLocalSessionStore(
        durableStorage: _FakeDurableSessionStore(
          eligibilityError: eligibilityError,
        ),
        legacySnapshotStore: _FakeSessionSnapshotStore(),
      );

      final result = await store.loadLegacySeedSession(
        attachedClientId: 'desktop-client',
      );

      expect(result.status, CommonCodeLegacySeedLoadStatus.failed);
      expect(result.error, same(eligibilityError));
      expect(result.stackTrace, isNotNull);
    });

    test('waitForPendingPersistence waits for queued writes', () async {
      final pendingWrite = Completer<void>();
      final durableStorage = _FakeDurableSessionStore(
        onWrite: (_) => pendingWrite.future,
      );
      final store = DurableLocalSessionStore(
        durableStorage: durableStorage,
        legacySnapshotStore: _FakeSessionSnapshotStore(),
      );

      unawaited(
        store.queueSessionPersistence(
          _session(),
          attachedClientId: 'desktop-client',
        ),
      );

      final waitFuture = store.waitForPendingPersistence();
      expect(waitFuture, doesNotComplete);

      pendingWrite.complete();
      await waitFuture;
      expect(durableStorage.disableLegacySeedCalls, 1);
    });
  });
}

Session _session() {
  return Session(
    id: 'session-1',
    activeHost: const Host(id: 'host-1'),
    clients: const <Client>[Client(id: 'desktop-client')],
  );
}

final class _FakeSessionSnapshotStore implements SessionSnapshotStore {
  @override
  Future<Session?> readLatestSession({required String desktopClientId}) async {
    return null;
  }

  @override
  Future<void> writeLatestSession(Session session) async {}
}

final class _FakeDurableSessionStore implements DurableSessionStore {
  _FakeDurableSessionStore({
    this.readError,
    this.eligibilityError,
    this.onWrite,
  });

  final Object? readError;
  final Object? eligibilityError;
  final Future<void> Function(String payload)? onWrite;

  int disableLegacySeedCalls = 0;

  @override
  Future<void> disableLegacySeed({required String desktopClientId}) async {
    disableLegacySeedCalls += 1;
  }

  @override
  Future<bool> isLegacySeedEnabled({required String desktopClientId}) async {
    if (eligibilityError case final Object error) {
      throw error;
    }

    return true;
  }

  @override
  Future<String?> readSessionPayload() async {
    if (readError case final Object error) {
      throw error;
    }

    return null;
  }

  @override
  Future<void> writeSessionPayload(String payload) async {
    await onWrite?.call(payload);
  }
}
