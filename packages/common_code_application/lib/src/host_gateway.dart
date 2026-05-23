import 'package:common_code_domain/common_code_domain.dart';

/// Application-owned host gateway contract for turn submission.
///
/// This port sits beneath the [CommonCodeSessionFacade] and is implemented
/// by an app-edge adapter that delegates to the concrete host service.
/// This separates the submission seam from the aggregate driver interface.
abstract interface class HostGateway {
  /// Submits a turn for processing.
  Future<void> submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  });
}