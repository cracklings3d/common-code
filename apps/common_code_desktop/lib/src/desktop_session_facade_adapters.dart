import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:host_core/host_core.dart';

abstract interface class DesktopSessionMutationPort {
  Future<void> acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  });

  Future<void> submitTurnForClient({
    required String sessionId,
    required String attachedClientId,
    required String submittedText,
  });
}

final class DesktopSessionBootstrapDriver implements CommonCodeSessionDriver {
  DesktopSessionBootstrapDriver({
    required CommonCodeSessionBootstrapPort bootstrapPort,
    required DesktopSessionMutationPort mutationPort,
    required CommonCodeSessionObservation observation,
    required String defaultSessionId,
    required String hostId,
    required String attachedClientId,
  }) : _bootstrapPort = bootstrapPort,
       _mutationPort = mutationPort,
       _observation = observation,
       _defaultSessionId = defaultSessionId,
       _hostId = hostId,
       _attachedClientId = attachedClientId;

  final CommonCodeSessionBootstrapPort _bootstrapPort;
  final DesktopSessionMutationPort _mutationPort;
  final CommonCodeSessionObservation _observation;
  final String _defaultSessionId;
  final String _hostId;
  final String _attachedClientId;

  String? _currentSessionId;
  final CommonCodeSessionBootstrapLifecycle _bootstrapLifecycle =
      CommonCodeSessionBootstrapLifecycle();

  @override
  Future<CommonCodeSessionBinding> ensureSession() async {
    final currentSessionId = _currentSessionId;
    if (currentSessionId != null) {
      return CommonCodeSessionBinding.attached(sessionId: currentSessionId);
    }

    final bootstrappedSession = await _bootstrapLifecycle.bootstrap(
      request: CommonCodeSessionBootstrapRequest(
        defaultSessionId: _defaultSessionId,
        hostId: _hostId,
        attachedClientId: _attachedClientId,
      ),
      port: _bootstrapPort,
    );
    _currentSessionId = bootstrappedSession.id;
    return CommonCodeSessionBinding.attached(sessionId: bootstrappedSession.id);
  }

  @override
  Future<void> acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  }) {
    return _mutationPort.acknowledgeNotification(
      sessionId: sessionId,
      notificationId: notificationId,
    );
  }

  @override
  Future<void> submitTurn({
    required String sessionId,
    required String attachedClientId,
    required String submittedText,
  }) {
    return _mutationPort.submitTurnForClient(
      sessionId: sessionId,
      attachedClientId: attachedClientId,
      submittedText: submittedText,
    );
  }

  @override
  Stream<Session> watchSession(String sessionId) {
    return _observation.watchSession(sessionId);
  }
}

final class HostServiceSessionObservation
    implements CommonCodeSessionObservation {
  const HostServiceSessionObservation(this._hostService);

  final HostService _hostService;

  @override
  Stream<Session> watchSession(String sessionId) {
    return _hostService.watchSession(sessionId);
  }
}

final class PersistingHostServiceSessionMutations
    implements DesktopSessionMutationPort, HostGateway {
  const PersistingHostServiceSessionMutations({
    required HostService hostService,
    required void Function(Session session)? persistSessionMutation,
  }) : _hostService = hostService,
       _persistSessionMutation = persistSessionMutation;

  final HostService _hostService;
  final void Function(Session session)? _persistSessionMutation;

  @override
  Future<void> acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  }) async {
    final session = _hostService.acknowledgeNotification(
      sessionId: sessionId,
      notificationId: notificationId,
    );
    _persistSessionMutation?.call(session);
  }

  @override
  Future<void> submitTurnForClient({
    required String sessionId,
    required String attachedClientId,
    required String submittedText,
  }) {
    return submitTurn(
      sessionId: sessionId,
      client: Client(id: attachedClientId),
      submittedText: submittedText,
    );
  }

  @override
  Future<void> submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) async {
    final session = _hostService.submitTurn(
      sessionId: sessionId,
      client: client,
      submittedText: submittedText,
    );
    _persistSessionMutation?.call(session);
  }
}
