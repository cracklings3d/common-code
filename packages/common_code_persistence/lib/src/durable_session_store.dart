import 'package:shared_preferences/shared_preferences.dart';

abstract interface class DurableSessionStore {
  Future<String?> readSessionPayload();

  Future<void> writeSessionPayload(String payload);

  Future<bool> isLegacySeedEnabled({required String desktopClientId});

  Future<void> disableLegacySeed({required String desktopClientId});
}

final class SharedPreferencesDurableSessionStore
    implements DurableSessionStore {
  SharedPreferencesDurableSessionStore({
    Future<SharedPreferences> Function()? sharedPreferencesFactory,
  }) : _sharedPreferencesFactory =
           sharedPreferencesFactory ?? SharedPreferences.getInstance;

  static const sessionStorageKey =
      'common_code.desktop.durable_local_host.session.v1';
  static const legacySeedMarkerKeyPrefix =
      'common_code.desktop.durable_local_host.legacy_seed_enabled';

  final Future<SharedPreferences> Function() _sharedPreferencesFactory;
  Future<SharedPreferences>? _sharedPreferences;

  @override
  Future<void> disableLegacySeed({required String desktopClientId}) async {
    final preferences = await _getPreferences();
    final didPersist = await preferences.setBool(
      _legacySeedMarkerKey(desktopClientId),
      false,
    );
    if (!didPersist) {
      throw StateError('Failed to persist the legacy seed marker.');
    }
  }

  @override
  Future<bool> isLegacySeedEnabled({required String desktopClientId}) async {
    final preferences = await _getPreferences();
    return preferences.getBool(_legacySeedMarkerKey(desktopClientId)) ?? true;
  }

  @override
  Future<String?> readSessionPayload() async {
    final preferences = await _getPreferences();
    return preferences.getString(sessionStorageKey);
  }

  @override
  Future<void> writeSessionPayload(String payload) async {
    final preferences = await _getPreferences();
    final didPersist = await preferences.setString(sessionStorageKey, payload);
    if (!didPersist) {
      throw StateError('Failed to persist the durable local session payload.');
    }
  }

  Future<SharedPreferences> _getPreferences() {
    return _sharedPreferences ??= _sharedPreferencesFactory();
  }

  static String legacySeedMarkerKeyFor(String desktopClientId) {
    return _legacySeedMarkerKey(desktopClientId);
  }

  static String _legacySeedMarkerKey(String desktopClientId) {
    return '$legacySeedMarkerKeyPrefix.$desktopClientId.v1';
  }
}
