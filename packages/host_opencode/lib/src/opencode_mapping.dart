// ignore_for_file: comment_markup

import 'package:common_code_domain/common_code_domain.dart';

/// Adapter-local translation layer between CommonCode contracts and OpenCode-specific vocabulary.
///
/// This file contains mappings and translations that stay internal to the
/// `host_opencode` package boundary. OpenCode-specific identifiers, handles,
/// and vocabulary do not leak to public contracts above the adapter seam.
///
/// The mapping conventions here mirror the patterns established in
/// `host_in_memory` but are scoped specifically to OpenCode's
/// vocabulary and handle conventions.

/// Translates a CommonCode [Host] to an OpenCode host handle.
String translateHostToOpenCodeHandle(Host host) => host.id;

/// Translates an OpenCode host handle to a CommonCode [Host].
Host translateOpenCodeHandleToHost(String handle) => Host(id: handle);

/// Translates a session ID to an OpenCode session identifier format.
String translateSessionIdToOpenCodeFormat(String sessionId) => sessionId;

/// Translates an OpenCode session identifier to a standard session ID.
String translateOpenCodeSessionIdToStandard(String openCodeSessionId) =>
    openCodeSessionId;
