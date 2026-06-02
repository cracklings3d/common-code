import 'dart:async';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';

/// OpenCode-backed [CommonCodeSessionObservation] that delegates to [HostService.watchSession].
///
/// This is the base observation layer for OpenCode session observation,
/// providing the bridge between the host service's watch stream and
/// the application's observation interface.
final class OpenCodeHostServiceSessionObservation
    implements CommonCodeSessionObservation {
  const OpenCodeHostServiceSessionObservation(this._hostService);

  final HostService _hostService;

  @override
  Stream<Session> watchSession(String sessionId) {
    return _hostService.watchSession(sessionId);
  }
}

/// OpenCode-backed observation adapter that decorates a base
/// [CommonCodeSessionObservation] with persistence side-effects
/// triggered on each session emission.
///
/// This mirrors the [PersistingHostServiceSessionObservation] pattern
/// but is scoped to the OpenCode adapter package.
final class OpenCodePersistingHostServiceSessionObservation
    implements CommonCodeSessionObservation {
  const OpenCodePersistingHostServiceSessionObservation({
    required CommonCodeSessionObservation observation,
    required void Function(Session session)? persistSessionMutation,
  }) : _observation = observation,
       _persistSessionMutation = persistSessionMutation;

  final CommonCodeSessionObservation _observation;
  final void Function(Session session)? _persistSessionMutation;

  @override
  Stream<Session> watchSession(String sessionId) {
    final baseStream = _observation.watchSession(sessionId);
    return baseStream.map((session) {
      _persistSessionMutation?.call(session);
      return session;
    });
  }
}

/// Creates an OpenCode session observation instance wrapping the given host service.
OpenCodeHostServiceSessionObservation createOpenCodeSessionObservation(
  HostService hostService,
) =>
    OpenCodeHostServiceSessionObservation(hostService);

/// Creates an OpenCode persisting session observation with persistence continuation.
OpenCodePersistingHostServiceSessionObservation
    createOpenCodePersistingSessionObservation({
  required CommonCodeSessionObservation observation,
  required void Function(Session session)? persistSessionMutation,
}) =>
    OpenCodePersistingHostServiceSessionObservation(
      observation: observation,
      persistSessionMutation: persistSessionMutation,
    );
