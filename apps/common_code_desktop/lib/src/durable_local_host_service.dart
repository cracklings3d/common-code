// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';

import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_observability/common_code_observability.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:common_code_application/common_code_application.dart';
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
    SessionSnapshotStore? legacySnapshotStore,
    DurableSessionStore? durableStorage,
    SessionSnapshotCodec codec = const SessionSnapshotCodec(),
    DurableLocalHostDiagnosticsSink? diagnosticsSink,
  }) {
    return DurableLocalHostService._(
      hostAdapter: hostAdapter,
      legacySnapshotStore:
          legacySnapshotStore ?? SharedPreferencesSessionSnapshotStore(),
      durableStorage: durableStorage ?? SharedPreferencesDurableSessionStore(),
      codec: codec,
      diagnosticsSink: diagnosticsSink,
    );
  }

  /// Creates a [DurableLocalHostService] with an internal [InMemoryHostAdapter].
  ///
  /// For backward compatibility with existing tests and composition.
  DurableLocalHostService({
    SessionSnapshotStore? legacySnapshotStore,
    DurableSessionStore? durableStorage,
    SessionSnapshotCodec codec = const SessionSnapshotCodec(),
    HostExecutionSimulationPolicy simulationPolicy =
        const HostExecutionSimulationPolicy(),
    DurableLocalHostDiagnosticsSink? diagnosticsSink,
  }) : _hostAdapter = InMemoryHostAdapter(simulationPolicy: simulationPolicy),
       _legacySnapshotStore =
           legacySnapshotStore ?? SharedPreferencesSessionSnapshotStore(),
       _durableStorage =
           durableStorage ?? SharedPreferencesDurableSessionStore(),
       _codec = codec,
       _diagnosticsSink = diagnosticsSink;

  DurableLocalHostService._({
    required InMemoryHostAdapter hostAdapter,
    required SessionSnapshotStore legacySnapshotStore,
    required DurableSessionStore durableStorage,
    required SessionSnapshotCodec codec,
    required DurableLocalHostDiagnosticsSink? diagnosticsSink,
  }) : _hostAdapter = hostAdapter,
       _legacySnapshotStore = legacySnapshotStore,
       _durableStorage = durableStorage,
       _codec = codec,
       _diagnosticsSink = diagnosticsSink;

  final InMemoryHostAdapter _hostAdapter;
  final SessionSnapshotStore _legacySnapshotStore;
  final DurableSessionStore _durableStorage;
  final SessionSnapshotCodec _codec;
  final DurableLocalHostDiagnosticsSink? _diagnosticsSink;

  Future<void> _writeSequence = Future<void>.value();
  String? _desktopClientIdForDurableWrites;

  Future<void> flushPendingWrites() => _writeSequence;

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

  @override
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

  @override
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
        await _persistBootstrapSession(restoredSession);
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
