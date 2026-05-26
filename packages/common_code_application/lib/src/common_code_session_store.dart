import 'package:common_code_domain/common_code_domain.dart';

import 'common_code_session_bootstrap.dart';

abstract interface class CommonCodeSessionStore {
  Future<CommonCodeDurableBootstrapLoadResult> loadDurableSessionCandidate({
    required String attachedClientId,
  });

  Future<CommonCodeLegacySeedLoadResult> loadLegacySeedSession({
    required String attachedClientId,
  });

  Future<void> persistSession(Session session, {String? attachedClientId});

  Future<void> queueSessionPersistence(
    Session session, {
    String? attachedClientId,
  });

  Future<void> waitForPendingPersistence();
}
