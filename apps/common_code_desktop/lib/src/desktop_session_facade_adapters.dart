import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:host_core/host_core.dart';

import 'desktop_session_runtime.dart'
    show desktopSessionRuntimeIdentityId;

// Re-export domain types needed for presentation switch expressions.
// This allows presentation files to use domain enums without directly importing the domain package.
export 'package:common_code_domain/common_code_domain.dart'
    show TurnStatus, SessionNotificationTransition;

/// Presentation model for a turn - used to render prompt thread cards.
/// Does not expose raw domain [Turn] type.
final class TurnData {
  const TurnData({
    required this.id,
    required this.clientId,
    required this.submittedText,
    required this.status,
    this.failureSummary,
  });

  final String id;
  final String clientId;
  final String submittedText;
  final TurnStatus status;
  final String? failureSummary;

  static TurnData fromTurn(Turn turn) {
    return TurnData(
      id: turn.id,
      clientId: turn.clientId,
      submittedText: turn.submittedText,
      status: turn.status,
      failureSummary: turn.failureSummary,
    );
  }
}

/// Presentation model for a notification - used to render snackbars.
/// Does not expose raw domain [SessionNotification] type.
final class NotificationData {
  const NotificationData({
    required this.notificationId,
    required this.turnId,
    required this.transition,
    required this.isAcknowledged,
  });

  final String notificationId;
  final String turnId;
  final SessionNotificationTransition transition;
  final bool isAcknowledged;

  static NotificationData fromNotification(SessionNotification notification) {
    return NotificationData(
      notificationId: notification.id,
      turnId: notification.turnId,
      transition: notification.transition,
      isAcknowledged: notification.isAcknowledged,
    );
  }
}

/// Presentation model for an attached client - used to render client chips.
/// Does not expose raw domain [Client] type beyond id.
final class ClientData {
  const ClientData({
    required this.id,
    required this.isLocal,
    required this.isInput,
  });

  final String id;
  final bool isLocal;
  final bool isInput;
}

/// Presentation model for session context chrome.
/// Does not expose raw domain [Session] type.
final class SessionContextData {
  const SessionContextData({
    required this.attachedClientId,
    required this.inputClientId,
    required this.clients,
  });

  final String attachedClientId;
  final String? inputClientId;
  final List<ClientData> clients;
}

/// Maps a domain [Session] to presentation-ready data structures.
SessionContextData mapSessionToContextData(Session session, String attachedClientId) {
  final inputClientId = session.inputClient?.id;
  return SessionContextData(
    attachedClientId: attachedClientId,
    inputClientId: inputClientId,
    clients: [
      for (final client in session.clients)
        ClientData(
          id: client.id,
          isLocal: client.id == attachedClientId,
          isInput: client.id == inputClientId,
        ),
    ],
  );
}

/// Maps a domain [Session] to a list of [TurnData].
List<TurnData> mapSessionToTurns(Session session) {
  return [
    for (final turn in session.promptThread.turns) TurnData.fromTurn(turn),
  ];
}

/// Maps a domain [Session] to unacknowledged [NotificationData] items.
List<NotificationData> mapSessionToUnacknowledgedNotifications(Session session) {
  return [
    for (final notification in session.notifications)
      if (!notification.isAcknowledged)
        NotificationData.fromNotification(notification),
  ];
}

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

    // The app-edge-supplied bootstrapRequest is authoritative for the
    // current desktop/in-memory path. Use it directly when available;
    // the null-coalesce fallback exists only for direct constructor
    // callers not going through the app-edge composition seam.
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
