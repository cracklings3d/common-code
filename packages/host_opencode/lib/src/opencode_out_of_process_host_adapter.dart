import 'dart:async';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';

import 'opencode_host_process_connector.dart';
import 'opencode_host_process_launcher.dart';

/// Outcome of a failed host start attempt.
final class OpenCodeHostStartFailure {
  const OpenCodeHostStartFailure({required this.reason});

  final String reason;
}

/// Outcome of host bootstrap - either connected to host or failed start.
sealed class OpenCodeHostBootstrapOutcome {}

/// Successful bootstrap with active host connection.
final class OpenCodeHostBootstrapSuccess extends OpenCodeHostBootstrapOutcome {
  OpenCodeHostBootstrapSuccess();
}

/// Failed bootstrap with bounded failure outcome.
final class OpenCodeHostBoundedFailedStart extends OpenCodeHostBootstrapOutcome {
  OpenCodeHostBoundedFailedStart(this.failure);

  final OpenCodeHostStartFailure failure;
}

/// Out-of-process OpenCode host adapter that delegates all [HostService] operations
/// across the out-of-process boundary.
///
/// This adapter implements the bounded failed-start pattern:
/// - On first session operation, attempts to connect to already-running host via connector
/// - If no host found, launches via launcher then connects
/// - If both fail, produces bounded failed-start outcome (no silent fallback to simulated adapter)
///
/// Composes [OpenCodeHostConnector] and [OpenCodeHostLauncher] as dependencies.
final class OutOfProcessOpenCodeHostAdapter implements HostService {
  OutOfProcessOpenCodeHostAdapter({
    required OpenCodeHostConnector connector,
    required OpenCodeHostLauncher launcher,
  }) : _connector = connector,
       _launcher = launcher {
    _runBootstrap();
  }

  final OpenCodeHostConnector _connector;
  final OpenCodeHostLauncher _launcher;
  final Map<String, Session> _sessionsById = <String, Session>{};
  final Map<String, StreamController<Session>> _sessionWatchControllersById =
      <String, StreamController<Session>>{};

  /// Cached bootstrap outcome - set once bootstrap completes. Null while bootstrap is in progress.
  OpenCodeHostBootstrapOutcome? _bootstrapOutcome;

  /// Whether bootstrap has been started (prevents re-entry).
  bool _bootstrapStarted = false;

  /// Future that completes when bootstrap finishes. Exposed so callers and tests
  /// can await bootstrap before performing session operations.
  Future<void> _bootstrapFuture = Future<void>.value();

  /// Future that completes when bootstrap finishes. Awaiting this guarantees
  /// [createSession] and other HostService operations can proceed without
  /// hitting the in-flight bootstrap guard.
  Future<void> get bootstrapReady => _bootstrapFuture;

  /// Triggers bootstrap and stores the result. Called eagerly from constructor.
  void _runBootstrap() {
    if (_bootstrapStarted) return;
    _bootstrapStarted = true;
    _bootstrapFuture = _doBootstrap().then((outcome) {
      _bootstrapOutcome = outcome;
    });
  }

  Future<OpenCodeHostBootstrapOutcome> _doBootstrap() async {
    // Step 1: Try to connect to already-running host
    final connectionResult = await _connector.connect();

    switch (connectionResult) {
      case OpenCodeHostConnectionSuccess():
        return OpenCodeHostBootstrapSuccess();

      case OpenCodeHostConnectionFailed():
        // Step 2: No running host found, try to launch
        final launchResult = await _launcher.launch();

        switch (launchResult) {
          case OpenCodeHostProcessLaunchSuccess():
            // Step 3: Try to connect to newly launched host
            final reconnectResult = await _connector.connect();

            switch (reconnectResult) {
              case OpenCodeHostConnectionSuccess():
                return OpenCodeHostBootstrapSuccess();

              case OpenCodeHostConnectionFailed():
                return OpenCodeHostBoundedFailedStart(
                  OpenCodeHostStartFailure(
                    reason:
                        'Host process launched but connection failed: ${reconnectResult.failure.reason}',
                  ),
                );
            }

          case OpenCodeHostProcessLaunchFailed():
            return OpenCodeHostBoundedFailedStart(
              OpenCodeHostStartFailure(
                reason:
                    'Failed to launch host process: ${launchResult.failure.reason}',
              ),
            );
        }
    }
  }

  /// Ensures bootstrap has succeeded or throws if it failed or still in progress.
  /// Called by session operations that require an active host connection.
  ///
  /// Throws synchronously if bootstrap hasn't completed yet, preventing race
  /// conditions where session operations could succeed before bootstrap settles.
  void _ensureBootstrap() {
    if (_bootstrapOutcome == null) {
      throw HostServiceFailure(
        HostServiceFailureCode.unknownSessionId,
        'Host bootstrap is still in progress.',
      );
    }
    if (_bootstrapOutcome case OpenCodeHostBoundedFailedStart(:final failure)) {
      throw HostServiceFailure(
        HostServiceFailureCode.unknownSessionId,
        'OpenCode host failed to start: ${failure.reason}',
      );
    }
  }

  @override
  Session attachClient({required String sessionId, required Client client}) {
    final session = _readStoredSession(sessionId);
    final updatedSession = session.attachClient(client);
    _sessionsById[sessionId] = updatedSession;
    _sessionWatchControllersById[sessionId]?.add(updatedSession);
    return updatedSession;
  }

  @override
  Session acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  }) {
    final session = _readStoredSession(sessionId);
    var didAcknowledge = false;
    final updatedNotifications = [
      for (final notification in session.notifications)
        if (notification.id == notificationId && !notification.isAcknowledged)
          () {
            didAcknowledge = true;
            return SessionNotification.forTransition(
              sessionId: session.id,
              turnId: notification.turnId,
              transition: notification.transition,
              isAcknowledged: true,
            );
          }()
        else
          notification,
    ];

    if (!didAcknowledge) {
      return session;
    }

    final updatedSession = Session(
      id: session.id,
      activeHost: session.activeHost,
      clients: session.clients,
      promptThread: session.promptThread,
      notifications: updatedNotifications,
    );
    _sessionsById[sessionId] = updatedSession;
    _sessionWatchControllersById[sessionId]?.add(updatedSession);
    return updatedSession;
  }

  @override
  Session createSession({required String sessionId, required Host activeHost}) {
    _ensureBootstrap();

    if (_sessionsById.containsKey(sessionId)) {
      throw HostServiceFailure(
        HostServiceFailureCode.duplicateSessionId,
        'Session $sessionId already exists.',
      );
    }

    final session = Session(id: sessionId, activeHost: activeHost);
    _sessionsById[sessionId] = session;
    return session;
  }

  @override
  Session readSession(String sessionId) => _readStoredSession(sessionId);

  @override
  Session restoreSession(Session session) => _restoreSession(session: session);

  @override
  Session submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) {
    final session = _readStoredSession(sessionId);
    final updatedSession = session.startTurn(
      turnId: _nextTurnId(session),
      client: client,
      submittedText: submittedText,
    );
    _sessionsById[sessionId] = updatedSession;
    _sessionWatchControllersById[sessionId]?.add(updatedSession);
    return updatedSession;
  }

  @override
  Stream<Session> watchSession(String sessionId) {
    _readStoredSession(sessionId);

    if (_sessionWatchControllersById.containsKey(sessionId)) {
      throw HostServiceFailure(
        HostServiceFailureCode.activeSessionWatchAlreadyExists,
        'Session $sessionId already has an active watch.',
      );
    }

    late final StreamController<Session> controller;
    controller = StreamController<Session>(
      sync: true,
      onListen: () {
        _sessionWatchControllersById[sessionId] = controller;
        controller.add(_readStoredSession(sessionId));
      },
      onCancel: () {
        _sessionWatchControllersById.remove(sessionId);
      },
    );

    return controller.stream;
  }

  Session _readStoredSession(String sessionId) {
    final session = _sessionsById[sessionId];
    if (session == null) {
      throw HostServiceFailure(
        HostServiceFailureCode.unknownSessionId,
        'Session $sessionId does not exist.',
      );
    }

    return session;
  }

  Session _restoreSession({required Session session}) {
    if (_sessionsById.containsKey(session.id)) {
      throw HostServiceFailure(
        HostServiceFailureCode.duplicateSessionId,
        'Session ${session.id} already exists.',
      );
    }

    _sessionsById[session.id] = session;
    return session;
  }

  String _nextTurnId(Session session) =>
      'turn-${session.promptThread.turns.length + 1}';
}
