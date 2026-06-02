import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';

/// OpenCode-backed [HostGateway] implementation.
///
/// This gateway delegates turn submission to the underlying [HostService]
/// and triggers persistence continuation after each mutation.
///
/// The OpenCode-specific vocabulary and translation logic is contained
/// entirely within this adapter package and does not leak to public
/// contracts above the adapter boundary.
final class OpenCodeHostGateway implements HostGateway {
  const OpenCodeHostGateway({
    required HostService hostService,
    required void Function(Session session)? persistSessionMutation,
  }) : _hostService = hostService,
       _persistSessionMutation = persistSessionMutation;

  final HostService _hostService;
  final void Function(Session session)? _persistSessionMutation;

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

/// Creates an OpenCode host gateway instance.
///
/// This factory is used by desktop composition to create the gateway
/// without depending on internal adapter types.
OpenCodeHostGateway createOpenCodeHostGateway({
  required HostService hostService,
  required void Function(Session session)? persistSessionMutation,
}) =>
    OpenCodeHostGateway(
      hostService: hostService,
      persistSessionMutation: persistSessionMutation,
    );
