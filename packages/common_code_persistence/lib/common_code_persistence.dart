import 'src/durable_session_store.dart';
import 'src/session_snapshot_codec.dart';
import 'src/session_snapshot_store.dart';

export 'src/durable_local_session_store.dart';
export 'src/durable_session_store.dart';
export 'src/session_snapshot_store.dart';
export 'src/session_snapshot_codec.dart';

typedef SharedPreferencesDurableLocalHostStorage =
    SharedPreferencesDurableSessionStore;
typedef SharedPreferencesDesktopSessionSnapshotStore =
    SharedPreferencesSessionSnapshotStore;
typedef DesktopSessionSnapshotJsonCodec = SessionSnapshotCodec;
