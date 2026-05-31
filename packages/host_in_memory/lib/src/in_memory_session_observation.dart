import 'dart:async';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:host_core/host_core.dart';

/// Observation adapter that delegates directly to [HostService.watchSession].
///
/// This is the base observation layer for in-memory session observation.
final class HostServiceSessionObservation
    implements CommonCodeSessionObservation {
  const HostServiceSessionObservation(this._hostService);

  final HostService _hostService;

  @override
  Stream<Session> watchSession(String sessionId) {
    return _hostService.watchSession(sessionId);
  }
}

/// Observation adapter that decorates a base [CommonCodeSessionObservation]
/// with persistence side-effects triggered on each session emission.
final class PersistingHostServiceSessionObservation
    implements CommonCodeSessionObservation {
  const PersistingHostServiceSessionObservation({
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
