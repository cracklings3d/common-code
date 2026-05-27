import 'dart:async';
import 'dart:convert';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';

import 'durable_session_store.dart';
import 'session_snapshot_codec.dart';
import 'session_snapshot_store.dart';

final class DurableLocalSessionStore implements CommonCodeSessionStore {
  DurableLocalSessionStore({
    SessionSnapshotStore? legacySnapshotStore,
    DurableSessionStore? durableStorage,
    SessionSnapshotCodec codec = const SessionSnapshotCodec(),
  }) : _legacySnapshotStore =
           legacySnapshotStore ?? SharedPreferencesSessionSnapshotStore(),
       _durableStorage =
           durableStorage ?? SharedPreferencesDurableSessionStore(),
       _codec = codec;

  factory DurableLocalSessionStore.fromPersistenceComponents({
    Object? legacySnapshotStore,
    Object? durableStorage,
    Object? codec,
  }) {
    return DurableLocalSessionStore(
      legacySnapshotStore: legacySnapshotStore as SessionSnapshotStore?,
      durableStorage: durableStorage as DurableSessionStore?,
      codec: (codec as SessionSnapshotCodec?) ?? const SessionSnapshotCodec(),
    );
  }

  final SessionSnapshotStore _legacySnapshotStore;
  final DurableSessionStore _durableStorage;
  final SessionSnapshotCodec _codec;

  Future<void> _writeSequence = Future<void>.value();

  @override
  Future<CommonCodeDurableBootstrapLoadResult> loadDurableSessionCandidate({
    required String attachedClientId,
  }) async {
    try {
      final encodedDurableSession = await _durableStorage.readSessionPayload();
      if (encodedDurableSession == null) {
        return const CommonCodeDurableBootstrapLoadResult.missing();
      }

      try {
        final decodedDurableSession = _codec.decode(
          jsonDecode(encodedDurableSession),
          desktopClientId: attachedClientId,
        );
        return CommonCodeDurableBootstrapLoadResult.available(
          decodedDurableSession,
        );
      } catch (_) {
        return const CommonCodeDurableBootstrapLoadResult.invalid();
      }
    } catch (error, stackTrace) {
      return CommonCodeDurableBootstrapLoadResult.readFailed(
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<CommonCodeLegacySeedLoadResult> loadLegacySeedSession({
    required String attachedClientId,
  }) async {
    try {
      final isLegacySeedEnabled = await _durableStorage.isLegacySeedEnabled(
        desktopClientId: attachedClientId,
      );
      if (!isLegacySeedEnabled) {
        return const CommonCodeLegacySeedLoadResult.disabled();
      }

      final legacySession = await _legacySnapshotStore.readLatestSession(
        desktopClientId: attachedClientId,
      );
      if (legacySession == null) {
        return const CommonCodeLegacySeedLoadResult.missing();
      }

      return CommonCodeLegacySeedLoadResult.available(legacySession);
    } catch (error, stackTrace) {
      return CommonCodeLegacySeedLoadResult.failed(
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> persistSession(
    Session session, {
    String? attachedClientId,
  }) async {
    await _durableStorage.writeSessionPayload(
      jsonEncode(_codec.encode(session)),
    );
    if (attachedClientId != null) {
      await _durableStorage.disableLegacySeed(
        desktopClientId: attachedClientId,
      );
    }
  }

  @override
  Future<void> queueSessionPersistence(
    Session session, {
    String? attachedClientId,
  }) {
    return _enqueuePersistence(
      session,
      attachedClientId: attachedClientId,
    );
  }

  void Function(Session session) createPersistenceContinuation({
    required String attachedClientId,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    return (Session session) {
      unawaited(
        _enqueuePersistence(
          session,
          attachedClientId: attachedClientId,
          onError: onError,
        ),
      );
    };
  }

  Future<void> _enqueuePersistence(
    Session session, {
    String? attachedClientId,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    final pendingWrite = _writeSequence.then(
      (_) => persistSession(session, attachedClientId: attachedClientId),
    );
    _writeSequence = pendingWrite.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        onError?.call(error, stackTrace);
      },
    );
    return pendingWrite;
  }

  @override
  Future<void> waitForPendingPersistence() => _writeSequence;
}
