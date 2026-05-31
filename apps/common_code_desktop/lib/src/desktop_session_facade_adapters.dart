import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:host_core/host_core.dart';

import 'desktop_session_runtime.dart'
    show desktopSessionRuntimeIdentityId;

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
    String desktopIdentityId = desktopSessionRuntimeIdentityId,
    CommonCodeSessionBootstrapRequest? bootstrapRequest,
  }) : _bootstrapPort = bootstrapPort,
       _mutationPort = mutationPort,
       _observation = observation,
       _defaultSessionId = defaultSessionId,
       _hostId = hostId,
       _attachedClientId = attachedClientId,
       _desktopIdentityId = desktopIdentityId,
       _bootstrapRequest = bootstrapRequest;

  final CommonCodeSessionBootstrapPort _bootstrapPort;
  final DesktopSessionMutationPort _mutationPort;
  final CommonCodeSessionObservation _observation;
  final String _defaultSessionId;
  final String _hostId;
  final String _attachedClientId;
  final String _desktopIdentityId;
  final CommonCodeSessionBootstrapRequest? _bootstrapRequest;

  String? _currentSessionId;
  CommonCodeSessionBootstrapRequest? _currentBootstrapRequest;
  final CommonCodeSessionBootstrapLifecycle _bootstrapLifecycle =
      CommonCodeSessionBootstrapLifecycle();

  @override
  Future<CommonCodeSessionBinding> ensureSession() async {
    final currentSessionId = _currentSessionId;
    if (currentSessionId != null) {
      return CommonCodeSessionBinding.attached(sessionId: currentSessionId);
    }

    final request = _bootstrapRequest ??
        CommonCodeSessionBootstrapRequest(
          defaultSessionId: _defaultSessionId,
          hostId: _hostId,
          attachedClientId: _attachedClientId,
          desktopIdentity: Identity(id: _desktopIdentityId),
        );
    final bootstrappedSession = await _bootstrapLifecycle.bootstrap(
      request: request,
      port: _bootstrapPort,
    );
    _currentSessionId = bootstrappedSession.id;
    _currentBootstrapRequest = request;
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

/// Thin delegation bridge that adapts [HostGateway] and [HostService] to [DesktopSessionMutationPort].
///
/// This bridge translates the desktop-local mutation protocol onto the application
/// [HostGateway] interface. The [HostService] is needed because [HostGateway] does not
/// expose the acknowledgeNotification method.
final class HostGatewayDesktopSessionMutationPort implements DesktopSessionMutationPort {
  const HostGatewayDesktopSessionMutationPort({
    required HostGateway hostGateway,
    required HostService hostService,
  }) : _hostGateway = hostGateway,
       _hostService = hostService;

  final HostGateway _hostGateway;
  final HostService _hostService;

  @override
  Future<void> acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  }) async {
    _hostService.acknowledgeNotification(
      sessionId: sessionId,
      notificationId: notificationId,
    );
  }

  @override
  Future<void> submitTurnForClient({
    required String sessionId,
    required String attachedClientId,
    required String submittedText,
  }) {
    return _hostGateway.submitTurn(
      sessionId: sessionId,
      client: Client(id: attachedClientId),
      submittedText: submittedText,
    );
  }
}
