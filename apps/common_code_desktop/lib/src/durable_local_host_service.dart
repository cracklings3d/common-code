// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';

import 'package:common_code_application/src/common_code_session_bootstrap.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:common_code_application/common_code_application.dart';
import 'package:host_core/host_core.dart';

enum DurableLocalHostDiagnosticCode {
  durableReadRestored,
  durableReadMissing,
  durableReadCorruptOrInvalid,
  durableReadFailed,
  legacySeedActivated,
  legacySeedSkipped,
  legacySeedSucceeded,
  legacySeedFailed,
  durableRestoreFailed,
  durableWriteFailed,
  freshBootstrapActivated,
}

final class DurableLocalHostDiagnostic {
  const DurableLocalHostDiagnostic(this.code, {this.error, this.stackTrace});

  final DurableLocalHostDiagnosticCode code;
  final Object? error;
  final StackTrace? stackTrace;
}

typedef DurableLocalHostDiagnosticsSink =
    void Function(DurableLocalHostDiagnostic diagnostic);

class DurableLocalHostService implements HostService {
  DurableLocalHostService({
    SessionSnapshotStore? legacySnapshotStore,
    DurableSessionStore? durableStorage,
    SessionSnapshotCodec codec = const SessionSnapshotCodec(),
    HostExecutionSimulationPolicy simulationPolicy =
        const HostExecutionSimulationPolicy(),
    DurableLocalHostDiagnosticsSink? diagnosticsSink,
  }) : _legacySnapshotStore =
           legacySnapshotStore ?? SharedPreferencesSessionSnapshotStore(),
       _durableStorage =
           durableStorage ?? SharedPreferencesDurableSessionStore(),
       _codec = codec,
       _simulationPolicy = simulationPolicy,
       _diagnosticsSink = diagnosticsSink;

  final SessionSnapshotStore _legacySnapshotStore;
  final DurableSessionStore _durableStorage;
  final SessionSnapshotCodec _codec;
  final HostExecutionSimulationPolicy _simulationPolicy;
  final DurableLocalHostDiagnosticsSink? _diagnosticsSink;

  final Map<String, Session> _sessionsById = <String, Session>{};
  final Map<String, StreamController<Session>> _sessionWatchControllersById =
      <String, StreamController<Session>>{};

  Future<void> _writeSequence = Future<void>.value();
  String? _bootstrappedSessionId;
  String? _desktopClientIdForDurableWrites;
  bool _isBootstrapped = false;

  Future<Session> bootstrap({
    required String defaultSessionId,
    required String hostId,
    required String desktopClientId,
  }) async {
    return const CommonCodeSessionBootstrapOrchestrator().bootstrap(
      request: CommonCodeSessionBootstrapRequest(
        defaultSessionId: defaultSessionId,
        hostId: hostId,
        attachedClientId: desktopClientId,
      ),
      isBootstrapped: isBootstrapped,
      readBootstrappedSession: readBootstrappedSession,
      loadDurableSessionCandidate: loadDurableSessionCandidate,
      restoreDurableSession: restoreDurableSession,
      loadLegacySeedSession: loadLegacySeedSession,
      restoreLegacySeededSession: restoreLegacySeededSession,
      createFreshSession: createFreshSession,
    );
  }

  Future<void> flushPendingWrites() => _writeSequence;

  bool get isBootstrapped => _isBootstrapped;

  Future<Session> createFreshSession(
    CommonCodeSessionBootstrapRequest request,
  ) {
    return _createFreshSession(
      defaultSessionId: request.defaultSessionId,
      hostId: request.hostId,
      desktopClientId: request.attachedClientId,
    );
  }

  Future<CommonCodeLegacySeedLoadResult> loadLegacySeedSession({
    required String attachedClientId,
  }) async {
    _desktopClientIdForDurableWrites = attachedClientId;

    try {
      final isLegacySeedEnabled = await _durableStorage.isLegacySeedEnabled(
        desktopClientId: attachedClientId,
      );
      if (!isLegacySeedEnabled) {
        _emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.legacySeedSkipped,
          ),
        );
        return const CommonCodeLegacySeedLoadResult.disabled();
      }

      _emit(
        const DurableLocalHostDiagnostic(
          DurableLocalHostDiagnosticCode.legacySeedActivated,
        ),
      );

      final legacySession = await _legacySnapshotStore.readLatestSession(
        desktopClientId: attachedClientId,
      );
      if (legacySession == null) {
        _emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.legacySeedFailed,
          ),
        );
        return const CommonCodeLegacySeedLoadResult.missing();
      }

      return CommonCodeLegacySeedLoadResult.available(legacySession);
    } catch (error, stackTrace) {
      _emit(
        DurableLocalHostDiagnostic(
          DurableLocalHostDiagnosticCode.legacySeedFailed,
          error: error,
          stackTrace: stackTrace,
        ),
      );
      return const CommonCodeLegacySeedLoadResult.failed();
    }
  }

  Future<CommonCodeDurableBootstrapLoadResult> loadDurableSessionCandidate({
    required String attachedClientId,
  }) async {
    _desktopClientIdForDurableWrites = attachedClientId;

    try {
      final encodedDurableSession = await _durableStorage.readSessionPayload();
      if (encodedDurableSession == null) {
        _emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.durableReadMissing,
          ),
        );
        return const CommonCodeDurableBootstrapLoadResult.missing();
      }

      Session? decodedDurableSession;
      try {
        decodedDurableSession = _codec.decode(
          jsonDecode(encodedDurableSession),
          desktopClientId: attachedClientId,
        );
      } catch (_) {
        // Decoding failed, will fall through to seedOrCreateFresh
      }
      if (decodedDurableSession == null) {
        _emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.durableReadCorruptOrInvalid,
          ),
        );
        return const CommonCodeDurableBootstrapLoadResult.invalid();
      }

      return CommonCodeDurableBootstrapLoadResult.available(
        decodedDurableSession,
      );
    } catch (error, stackTrace) {
      _emit(
        DurableLocalHostDiagnostic(
          DurableLocalHostDiagnosticCode.durableReadFailed,
          error: error,
          stackTrace: stackTrace,
        ),
      );
      return const CommonCodeDurableBootstrapLoadResult.readFailed();
    }
  }

  Session readBootstrappedSession() {
    return readSession(_bootstrappedSessionId!);
  }

  Future<Session> restoreLegacySeededSession({
    required Session session,
    required String attachedClientId,
  }) async {
    _desktopClientIdForDurableWrites = attachedClientId;
    var emittedLegacySeedFailure = false;

    try {
      final restoredSession = _restoreSession(session: session);
      try {
        await _persistBootstrapSession(restoredSession);
      } catch (error, stackTrace) {
        _sessionsById.remove(restoredSession.id);
        _emit(
          DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.legacySeedFailed,
            error: error,
            stackTrace: stackTrace,
          ),
        );
        emittedLegacySeedFailure = true;
        rethrow;
      }

      _bootstrappedSessionId = restoredSession.id;
      _isBootstrapped = true;
      _emit(
        const DurableLocalHostDiagnostic(
          DurableLocalHostDiagnosticCode.legacySeedSucceeded,
        ),
      );
      return restoredSession;
    } catch (error, stackTrace) {
      if (!emittedLegacySeedFailure) {
        _emit(
          DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.legacySeedFailed,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
      rethrow;
    }
  }

  Session restoreDurableSession(Session session) {
    try {
      final restoredSession = restoreBootstrappedSession(session);
      _bootstrappedSessionId = restoredSession.id;
      _isBootstrapped = true;
      _emit(
        const DurableLocalHostDiagnostic(
          DurableLocalHostDiagnosticCode.durableReadRestored,
        ),
      );
      return restoredSession;
    } catch (error, stackTrace) {
      _emit(
        DurableLocalHostDiagnostic(
          DurableLocalHostDiagnosticCode.durableRestoreFailed,
          error: error,
          stackTrace: stackTrace,
        ),
      );
      rethrow;
    }
  }

  @override
  Session attachClient({required String sessionId, required Client client}) {
    final session = _readStoredSession(sessionId);
    final updatedSession = session.attachClient(client);
    _persistSession(sessionId, updatedSession);
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
    _persistSession(sessionId, updatedSession);
    return updatedSession;
  }

  @override
  Session createSession({required String sessionId, required Host activeHost}) {
    if (_sessionsById.containsKey(sessionId)) {
      throw HostServiceFailure(
        HostServiceFailureCode.duplicateSessionId,
        'Session $sessionId already exists.',
      );
    }

    final session = Session(id: sessionId, activeHost: activeHost);
    _persistSession(sessionId, session);
    return session;
  }

  @override
  Session readSession(String sessionId) => _readStoredSession(sessionId);

  @override
  Session restoreSession(Session session) {
    return _restoreSession(session: session, scheduleDurableWrite: true);
  }

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
    _persistSession(sessionId, updatedSession);
    _scheduleSimulatedExecution(
      sessionId: sessionId,
      turnId: updatedSession.activeTurn!.id,
    );
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

  Future<Session> _createFreshSession({
    required String defaultSessionId,
    required String hostId,
    required String desktopClientId,
  }) async {
    _emit(
      const DurableLocalHostDiagnostic(
        DurableLocalHostDiagnosticCode.freshBootstrapActivated,
      ),
    );

    final createdSession = createSession(
      sessionId: defaultSessionId,
      activeHost: Host(id: hostId),
    );
    final attachedSession = attachClient(
      sessionId: createdSession.id,
      client: Client(id: desktopClientId),
    );
    _bootstrappedSessionId = attachedSession.id;
    _isBootstrapped = true;

    try {
      await _persistBootstrapSession(attachedSession);
    } catch (_) {
      // Durable bootstrap write failures remain non-fatal to the live session.
    }

    return attachedSession;
  }

  void _emit(DurableLocalHostDiagnostic diagnostic) {
    _diagnosticsSink?.call(diagnostic);
  }

  void _enqueueDurableWrite(Session session) {
    final encodedSession = jsonEncode(_codec.encode(session));
    _writeSequence = _writeSequence
        .then((_) => _writeDurableSessionPayload(encodedSession))
        .catchError((Object error, StackTrace stackTrace) {
          _emit(
            DurableLocalHostDiagnostic(
              DurableLocalHostDiagnosticCode.durableWriteFailed,
              error: error,
              stackTrace: stackTrace,
            ),
          );
        });
  }

  void _persistSession(String sessionId, Session session) {
    _sessionsById[sessionId] = session;
    _sessionWatchControllersById[sessionId]?.add(session);
    _enqueueDurableWrite(session);
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

  Session _restoreSession({
    required Session session,
    bool scheduleDurableWrite = false,
  }) {
    if (_sessionsById.containsKey(session.id)) {
      throw HostServiceFailure(
        HostServiceFailureCode.duplicateSessionId,
        'Session ${session.id} already exists.',
      );
    }

    _sessionsById[session.id] = session;
    if (scheduleDurableWrite) {
      _enqueueDurableWrite(session);
    }
    return session;
  }

  Session restoreBootstrappedSession(Session session) {
    return _restoreSession(session: session);
  }

  void _scheduleSimulatedExecution({
    required String sessionId,
    required String turnId,
  }) {
    Timer(_simulationPolicy.queuedToRunningDelay, () {
      final runningSession = _advanceTurnIfStillActive(
        sessionId: sessionId,
        turnId: turnId,
        expectedStatus: TurnStatus.queued,
        update: (session) => session.advanceActiveTurnToRunning(),
      );

      if (runningSession == null) {
        return;
      }

      Timer(_simulationPolicy.runningToTerminalDelay, () {
        _advanceTurnIfStillActive(
          sessionId: sessionId,
          turnId: turnId,
          expectedStatus: TurnStatus.running,
          update: (session) => switch (_simulationPolicy.terminalOutcome) {
            SimulatedTurnTerminalOutcome.completed =>
              session.completeActiveTurn(),
            SimulatedTurnTerminalOutcome.failed => session.failActiveTurn(
              failureSummary: _simulationPolicy.failureSummary,
            ),
          },
        );
      });
    });
  }

  Session? _advanceTurnIfStillActive({
    required String sessionId,
    required String turnId,
    required TurnStatus expectedStatus,
    required Session Function(Session session) update,
  }) {
    final session = _sessionsById[sessionId];
    final currentTurn = session?.activeTurn;
    if (session == null ||
        currentTurn == null ||
        currentTurn.id != turnId ||
        currentTurn.status != expectedStatus) {
      return null;
    }

    final updatedSession = update(session);
    _persistSession(sessionId, updatedSession);
    return updatedSession;
  }

  String _nextTurnId(Session session) =>
      'turn-${session.promptThread.turns.length + 1}';

  Future<void> _persistBootstrapSession(Session session) async {
    try {
      await _writeDurableSessionPayload(jsonEncode(_codec.encode(session)));
    } catch (error, stackTrace) {
      _emit(
        DurableLocalHostDiagnostic(
          DurableLocalHostDiagnosticCode.durableWriteFailed,
          error: error,
          stackTrace: stackTrace,
        ),
      );
      rethrow;
    }
  }

  Future<void> _writeDurableSessionPayload(String encodedSession) async {
    await _durableStorage.writeSessionPayload(encodedSession);
    final desktopClientId = _desktopClientIdForDurableWrites;
    if (desktopClientId != null) {
      await _durableStorage.disableLegacySeed(desktopClientId: desktopClientId);
    }
  }
}
