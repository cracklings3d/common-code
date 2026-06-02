library;

/// Exports the minimal public construction surface for desktop composition.
///
/// This package provides the OpenCode-specific host adapter for the desktop
/// application edge. OpenCode-specific gateway, session observation, and
/// mapping logic remain internal to this package via `src/` libraries.
///
/// Desktop composition imports this file to access:
/// - [OpenCodeHostAdapter] - the host service adapter for OpenCode sessions
/// - [OpenCodeHostGateway] - the host gateway implementation
/// - [OpenCodePersistingHostServiceSessionObservation] - the persisting observation
/// - [OpenCodeHostServiceSessionObservation] - the base observation
///
/// Types from `src/` (mapping helpers) are intentionally not re-exported;
/// they remain internal to the adapter boundary.
export 'src/opencode_host_adapter.dart';
export 'src/opencode_host_gateway.dart';
export 'src/opencode_session_observation.dart';
