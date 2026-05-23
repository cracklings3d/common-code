import 'dart:async';

import 'package:common_code_domain/common_code_domain.dart';

/// Application-owned session observation port.
///
/// This interface abstracts the session watch behavior away from the aggregate
/// driver/host-service watch seam, making observation an explicit boundary
/// beneath the facade.
///
/// Implementations are adapter-side (e.g., desktop app-edge) and delegate
/// to the current HostService.watchSession(...) as a transitional detail.
abstract interface class CommonCodeSessionObservation {
  /// Watch session changes for [sessionId].
  ///
  /// Emits the current session state immediately on listen, then subsequent
  /// session changes as they occur.
  ///
  /// Completes with an error if observation fails.
  /// The stream may emit [Session] snapshots and error events.
  Stream<Session> watchSession(String sessionId);
}