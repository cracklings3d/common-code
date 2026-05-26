// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:host_core/host_core.dart';
import 'package:host_in_memory/host_in_memory.dart';

class DurableLocalHostService implements CommonCodeSessionBootstrapPort {
  /// Creates a [DurableLocalHostService] with an injected [hostAdapter].
  ///
  /// Use this factory for new composition code.
  DurableLocalHostService.withAdapter({
    required InMemoryHostAdapter hostAdapter,
    CommonCodeSessionStore? sessionStore,
    Object? legacySnapshotStore,
    Object? durableStorage,
    Object? codec,
    DurableLocalHostDiagnosticsPort? diagnosticsPort,
  }) : this.internal(
         hostAdapter: hostAdapter,
         sessionStore: sessionStore,
         legacySnapshotStore: legacySnapshotStore,
         durableStorage: durableStorage,
         codec: codec,
         diagnosticsPort: diagnosticsPort,
       );

  DurableLocalHostService.internal({
    required InMemoryHostAdapter hostAdapter,
    CommonCodeSessionStore? sessionStore,
    Object? legacySnapshotStore,
    Object? durableStorage,
    Object? codec,
    DurableLocalHostDiagnosticsPort? diagnosticsPort,
  }) : _hostAdapter = hostAdapter,
       sessionStore =
           sessionStore ??
           DurableLocalSessionStore.fromPersistenceComponents(
             legacySnapshotStore: legacySnapshotStore,
             durableStorage: durableStorage,
             codec: codec,
           ),
       _diagnosticsPort = diagnosticsPort;

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
    DurableLocalHostDiagnosticsPort? diagnosticsPort,
  }) : _hostAdapter = InMemoryHostAdapter(simulationPolicy: simulationPolicy),
       sessionStore =
           sessionStore ??
           DurableLocalSessionStore.fromPersistenceComponents(
             legacySnapshotStore: legacySnapshotStore,
             durableStorage: durableStorage,
             codec: codec,
           ),
       _diagnosticsPort = diagnosticsPort;

  final InMemoryHostAdapter _hostAdapter;

  @override
  final CommonCodeSessionStore sessionStore;

  final DurableLocalHostDiagnosticsPort? _diagnosticsPort;

  String? _desktopClientIdForDurableWrites;

  Future<void> flushPendingWrites() => sessionStore.waitForPendingPersistence();

  void queueSessionPersistence(Session session) {
    _enqueueDurableWrite(session);
  }

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
        _diagnosticsPort?.emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.legacySeedActivated,
          ),
        );
        return legacySeed;
      case CommonCodeLegacySeedLoadStatus.disabled:
        _diagnosticsPort?.emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.legacySeedSkipped,
          ),
        );
        return legacySeed;
      case CommonCodeLegacySeedLoadStatus.missing:
        _diagnosticsPort?.emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.legacySeedActivated,
          ),
        );
        _diagnosticsPort?.emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.legacySeedFailed,
          ),
        );
        return legacySeed;
      case CommonCodeLegacySeedLoadStatus.failed:
        _diagnosticsPort?.emit(
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
        _diagnosticsPort?.emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.durableReadMissing,
          ),
        );
        return durableCandidate;
      case CommonCodeDurableBootstrapLoadStatus.invalid:
        _diagnosticsPort?.emit(
          const DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.durableReadCorruptOrInvalid,
          ),
        );
        return durableCandidate;
      case CommonCodeDurableBootstrapLoadStatus.readFailed:
        _diagnosticsPort?.emit(
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
        _diagnosticsPort?.emit(
          DurableLocalHostDiagnostic(
            DurableLocalHostDiagnosticCode.legacySeedFailed,
            error: error,
            stackTrace: stackTrace,
          ),
        );
        emittedLegacySeedFailure = true;
        rethrow;
      }

      _diagnosticsPort?.emit(
        const DurableLocalHostDiagnostic(
          DurableLocalHostDiagnosticCode.legacySeedSucceeded,
        ),
      );
      return restoredSession;
    } catch (error, stackTrace) {
      if (!emittedLegacySeedFailure) {
        _diagnosticsPort?.emit(
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
      _diagnosticsPort?.emit(
        const DurableLocalHostDiagnostic(
          DurableLocalHostDiagnosticCode.durableReadRestored,
        ),
      );
      return restoredSession;
    } catch (error, stackTrace) {
      _diagnosticsPort?.emit(
        DurableLocalHostDiagnostic(
          DurableLocalHostDiagnosticCode.durableRestoreFailed,
          error: error,
          stackTrace: stackTrace,
        ),
      );
      rethrow;
    }
  }

  Future<Session> _createFreshSession({
    required String defaultSessionId,
    required String hostId,
    required String desktopClientId,
  }) async {
    _diagnosticsPort?.emit(
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

  void _enqueueDurableWrite(Session session) {
    unawaited(
      sessionStore
          .queueSessionPersistence(
            session,
            attachedClientId: _desktopClientIdForDurableWrites,
          )
          .catchError((Object error, StackTrace stackTrace) {
            _diagnosticsPort?.emit(
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
      _diagnosticsPort?.emit(
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
