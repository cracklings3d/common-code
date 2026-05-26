// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_observability/common_code_observability.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:host_core/host_core.dart';
import 'package:host_in_memory/host_in_memory.dart';

// Re-export diagnostics types for backwards compatibility with consumers
// that import from DurableLocalHostService.
export 'package:common_code_observability/common_code_observability.dart';

class DurableLocalHostService
    implements HostService, CommonCodeSessionBootstrapPort {
  /// Creates a [DurableLocalHostService] with an injected [hostAdapter].
  ///
  /// Use this factory for new composition code.
  factory DurableLocalHostService.withAdapter({
    required InMemoryHostAdapter hostAdapter,
    CommonCodeSessionStore? sessionStore,
    Object? legacySnapshotStore,
    Object? durableStorage,
    Object? codec,
    DurableLocalHostDiagnosticsSink? diagnosticsSink,
  }) {
    return DurableLocalHostService._(
      hostAdapter: hostAdapter,
      sessionStore:
          sessionStore ??
          DurableLocalSessionStore.fromPersistenceComponents(
            legacySnapshotStore: legacySnapshotStore,
            durableStorage: durableStorage,
            codec: codec,
          ),
      diagnosticsSink: diagnosticsSink,
    );
  }

  /// Creates a [DurableLocalHostService] with an internal [InMemoryHostAdapter].
  ///
  /// For backward compatibility with existing tests and composition.
  DurableLocalHostService({
    CommonCodeSessionStore? sessionStore,
    Object? legacySnapshotStore,
    Object? durableStorage,
    Object? codec,
    HostExecutionSimulationPolicy simulationPolicy =
        const HostExecutionSimulationPolicy(),
    DurableLocalHostDiagnosticsSink? diagnosticsSink,
  }) : _hostAdapter = InMemoryHostAdapter(simulationPolicy: simulationPolicy),
       sessionStore =
            sessionStore ??
            DurableLocalSessionStore.fromPersistenceComponents(
              legacySnapshotStore: legacySnapshotStore,
             durableStorage: durableStorage,
             codec: codec,
           ),
       _diagnosticsSink = diagnosticsSink;

  DurableLocalHostService._({
    required InMemoryHostAdapter hostAdapter,
    required this.sessionStore,
    required DurableLocalHostDiagnosticsSink? diagnosticsSink,
  }) : _hostAdapter = hostAdapter,
       _diagnosticsSink = diagnosticsSink;

  final InMemoryHostAdapter _hostAdapter;
  @override
  final CommonCodeSessionStore sessionStore;
  final DurableLocalHostDiagnosticsSink? _diagnosticsSink;

  String? _desktopClientIdForDurableWrites;

  Future<void> flushPendingWrites() => sessionStore.waitForPendingPersistence();

  @override
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
    final legacySeed = await sessionStore.loadLegacySeedSession(
      attachedClientId: attachedClientId,
    );
    switch (legacySeed.status) {
      case CommonCodeLegacySeedLoadStatus.available:
        _emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.legacySeedActivated,
          ),
        );
        return legacySeed;
      case CommonCodeLegacySeedLoadStatus.disabled:
        _emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.legacySeedSkipped,
          ),
        );
        return legacySeed;
      case CommonCodeLegacySeedLoadStatus.missing:
        _emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.legacySeedActivated,
          ),
        );
        _emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.legacySeedFailed,
          ),
        );
        return legacySeed;
      case CommonCodeLegacySeedLoadStatus.failed:
        _emit(
          DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.legacySeedFailed,
            error: legacySeed.error,
            stackTrace: legacySeed.stackTrace,
          ),
        );
        return legacySeed;
    }
  }

  Future<CommonCodeDurableBootstrapLoadResult> loadDurableSessionCandidate({
    required String attachedClientId,
  }) async {
    final durableCandidate = await sessionStore.loadDurableSessionCandidate(
      attachedClientId: attachedClientId,
    );
    switch (durableCandidate.status) {
      case CommonCodeDurableBootstrapLoadStatus.available:
        return durableCandidate;
      case CommonCodeDurableBootstrapLoadStatus.missing:
        _emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.durableReadMissing,
          ),
        );
        return durableCandidate;
      case CommonCodeDurableBootstrapLoadStatus.invalid:
        _emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.durableReadCorruptOrInvalid,
          ),
        );
        return durableCandidate;
      case CommonCodeDurableBootstrapLoadStatus.readFailed:
        _emit(
          DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.durableReadFailed,
            error: durableCandidate.error,
            stackTrace: durableCandidate.stackTrace,
          ),
        );
        return durableCandidate;
    }
  }

  @override
  Future<Session> restoreLegacySeededSession({
    required Session session,
    required String attachedClientId,
  }) async {
    _desktopClientIdForDurableWrites = attachedClientId;
    var emittedLegacySeedFailure = false;

    try {
      final restoredSession = _hostAdapter.restoreSession(session);
      try {
        await _persistBootstrapSession(
          restoredSession,
          attachedClientId: attachedClientId,
        );
      } catch (error, stackTrace) {
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

  @override
  Session restoreDurableSession(Session session) {
    try {
      final restoredSession = _hostAdapter.restoreSession(session);
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
    final session = _hostAdapter.attachClient(
      sessionId: sessionId,
      client: client,
    );
    _enqueueDurableWrite(session);
    return session;
  }

  @override
  Session acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  }) {
    final session = _hostAdapter.acknowledgeNotification(
      sessionId: sessionId,
      notificationId: notificationId,
    );
    _enqueueDurableWrite(session);
    return session;
  }

  @override
  Session createSession({required String sessionId, required Host activeHost}) {
    final session = _hostAdapter.createSession(
      sessionId: sessionId,
      activeHost: activeHost,
    );
    _enqueueDurableWrite(session);
    return session;
  }

  @override
  Session readSession(String sessionId) => _hostAdapter.readSession(sessionId);

  @override
  Session restoreSession(Session session) {
    final restored = _hostAdapter.restoreSession(session);
    _enqueueDurableWrite(restored);
    return restored;
  }

  @override
  Session submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) {
    final session = _hostAdapter.submitTurn(
      sessionId: sessionId,
      client: client,
      submittedText: submittedText,
    );
    _enqueueDurableWrite(session);
    return session;
  }

  @override
  Stream<Session> watchSession(String sessionId) {
    return _hostAdapter.watchSession(sessionId);
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

    final createdSession = _hostAdapter.createSession(
      sessionId: defaultSessionId,
      activeHost: Host(id: hostId),
    );
    final attachedSession = _hostAdapter.attachClient(
      sessionId: createdSession.id,
      client: Client(id: desktopClientId),
    );

    try {
      await _persistBootstrapSession(
        attachedSession,
        attachedClientId: desktopClientId,
      );
    } catch (_) {
      // Durable bootstrap write failures remain non-fatal to the live session.
    }

    return attachedSession;
  }

  void _emit(DurableLocalHostDiagnostic diagnostic) {
    _diagnosticsSink?.call(diagnostic);
  }

  void _enqueueDurableWrite(Session session) {
    unawaited(
      sessionStore
          .queueSessionPersistence(
            session,
            attachedClientId: _desktopClientIdForDurableWrites,
          )
          .catchError((Object error, StackTrace stackTrace) {
          _emit(
            DurableLocalHostDiagnostic(
              DurableLocalHostDiagnosticCode.durableWriteFailed,
              error: error,
              stackTrace: stackTrace,
            ),
          );
          }),
    );
  }

  Future<void> _persistBootstrapSession(
    Session session, {
    required String attachedClientId,
  }) async {
    try {
      await sessionStore.persistSession(
        session,
        attachedClientId: attachedClientId,
      );
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
}
