import 'dart:convert';

import 'package:common_code_domain/common_code_domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_snapshot_codec.dart';

abstract interface class SessionSnapshotStore {
  Future<Session?> readLatestSession({required String desktopClientId});

  Future<void> writeLatestSession(Session session);
}

final class SharedPreferencesSessionSnapshotStore
    implements SessionSnapshotStore {
  SharedPreferencesSessionSnapshotStore({
    SessionSnapshotCodec codec = const SessionSnapshotCodec(),
    Future<SharedPreferences> Function()? sharedPreferencesFactory,
  }) : _codec = codec,
       _sharedPreferencesFactory =
           sharedPreferencesFactory ?? SharedPreferences.getInstance;

  static const storageKey = 'common_code.desktop.latest_session_snapshot.v1';

  final SessionSnapshotCodec _codec;
  final Future<SharedPreferences> Function() _sharedPreferencesFactory;
  Future<SharedPreferences>? _sharedPreferences;

  @override
  Future<Session?> readLatestSession({required String desktopClientId}) async {
    final preferences = await _getPreferences();
    final encodedSnapshot = preferences.getString(storageKey);
    if (encodedSnapshot == null) {
      return null;
    }

    try {
      return _codec.decode(
        jsonDecode(encodedSnapshot),
        desktopClientId: desktopClientId,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeLatestSession(Session session) async {
    final preferences = await _getPreferences();
    final didPersist = await preferences.setString(
      storageKey,
      jsonEncode(_codec.encode(session)),
    );
    if (!didPersist) {
      throw StateError('Failed to persist the latest desktop session snapshot.');
    }
  }

  Future<SharedPreferences> _getPreferences() {
    return _sharedPreferences ??= _sharedPreferencesFactory();
  }
}
