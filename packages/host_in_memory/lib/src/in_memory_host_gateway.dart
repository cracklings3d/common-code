import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_application/common_code_application.dart';

/// Host gateway adapter that implements [HostGateway] with persistence continuation.
///
/// This is the default in-memory [HostGateway] implementation that:
/// - Delegates turn submission to the underlying [HostService]
/// - Triggers persistence continuation after each mutation
final class PersistingHostServiceSessionMutations implements HostGateway {
  const PersistingHostServiceSessionMutations({
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
