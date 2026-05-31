import 'package:common_code_domain/common_code_domain.dart';

import 'common_code_diagnostics.dart';
import 'common_code_session_store.dart';

abstract interface class CommonCodeSessionBootstrapPort {
  CommonCodeSessionStore get sessionStore;

  Future<CommonCodeDurableBootstrapLoadResult> loadDurableSessionCandidate({
    required String attachedClientId,
  });

  Future<CommonCodeLegacySeedLoadResult> loadLegacySeedSession({
    required String attachedClientId,
  });

  Session restoreDurableSession(Session session);

  Future<Session> restoreLegacySeededSession({
    required Session session,
    required String attachedClientId,
  });

  Future<Session> createFreshSession(CommonCodeSessionBootstrapRequest request);
}

final class CommonCodeSessionBootstrapHost {
  const CommonCodeSessionBootstrapHost({
    required this.restoreSession,
    required this.createSession,
    required this.attachClient,
  });

  final Session Function(Session session) restoreSession;
  final Session Function({required String sessionId, required Host activeHost})
  createSession;
  final Session Function({required String sessionId, required Client client})
  attachClient;
}

class CommonCodeSessionBootstrapPortAdapter
    implements CommonCodeSessionBootstrapPort {
  CommonCodeSessionBootstrapPortAdapter({
    required this.sessionStore,
    required CommonCodeSessionBootstrapHost host,
    DurableLocalHostDiagnosticsPort? diagnosticsPort,
  }) : _host = host,
       _diagnosticsPort = diagnosticsPort;

  @override
  final CommonCodeSessionStore sessionStore;

  final CommonCodeSessionBootstrapHost _host;
  final DurableLocalHostDiagnosticsPort? _diagnosticsPort;

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
  Future<Session> restoreLegacySeededSession({
    required Session session,
    required String attachedClientId,
  }) async {
    var emittedLegacySeedFailure = false;

    try {
      final restoredSession = _host.restoreSession(session);
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
      final restoredSession = _host.restoreSession(session);
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

    final createdSession = _host.createSession(
      sessionId: defaultSessionId,
      activeHost: Host(id: hostId),
    );
    final attachedSession = _host.attachClient(
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

final class CommonCodeSessionBootstrapRequest {
  const CommonCodeSessionBootstrapRequest({
    required this.defaultSessionId,
    required this.hostId,
    required this.attachedClientId,
    this.desktopIdentity = const Identity(id: 'desktop-app-edge-default'),
  });

  final String defaultSessionId;
  final String hostId;
  final String attachedClientId;
  final Identity desktopIdentity;
}

enum CommonCodeDurableBootstrapLoadStatus {
  available,
  missing,
  invalid,
  readFailed,
}

final class CommonCodeDurableBootstrapLoadResult {
  const CommonCodeDurableBootstrapLoadResult._({
    required this.status,
    this.session,
    this.error,
    this.stackTrace,
  });

  const CommonCodeDurableBootstrapLoadResult.available(Session session)
    : this._(
        status: CommonCodeDurableBootstrapLoadStatus.available,
        session: session,
      );

  const CommonCodeDurableBootstrapLoadResult.missing()
    : this._(status: CommonCodeDurableBootstrapLoadStatus.missing);

  const CommonCodeDurableBootstrapLoadResult.invalid()
    : this._(status: CommonCodeDurableBootstrapLoadStatus.invalid);

  const CommonCodeDurableBootstrapLoadResult.readFailed({
    Object? error,
    StackTrace? stackTrace,
  }) : this._(
         status: CommonCodeDurableBootstrapLoadStatus.readFailed,
         error: error,
         stackTrace: stackTrace,
       );

  final CommonCodeDurableBootstrapLoadStatus status;
  final Session? session;
  final Object? error;
  final StackTrace? stackTrace;
}

enum CommonCodeLegacySeedLoadStatus { available, disabled, missing, failed }

final class CommonCodeLegacySeedLoadResult {
  const CommonCodeLegacySeedLoadResult._({
    required this.status,
    this.session,
    this.error,
    this.stackTrace,
  });

  const CommonCodeLegacySeedLoadResult.available(Session session)
    : this._(
        status: CommonCodeLegacySeedLoadStatus.available,
        session: session,
      );

  const CommonCodeLegacySeedLoadResult.disabled()
    : this._(status: CommonCodeLegacySeedLoadStatus.disabled);

  const CommonCodeLegacySeedLoadResult.missing()
    : this._(status: CommonCodeLegacySeedLoadStatus.missing);

  const CommonCodeLegacySeedLoadResult.failed({
    Object? error,
    StackTrace? stackTrace,
  }) : this._(
         status: CommonCodeLegacySeedLoadStatus.failed,
         error: error,
         stackTrace: stackTrace,
       );

  final CommonCodeLegacySeedLoadStatus status;
  final Session? session;
  final Object? error;
  final StackTrace? stackTrace;
}

final class CommonCodeSessionBootstrapOrchestrator {
  const CommonCodeSessionBootstrapOrchestrator();

  Future<Session> bootstrap({
    required CommonCodeSessionBootstrapRequest request,
    required bool isBootstrapped,
    required Session Function() readBootstrappedSession,
    required Future<CommonCodeDurableBootstrapLoadResult> Function({
      required String attachedClientId,
    })
    loadDurableSessionCandidate,
    required Session Function(Session session) restoreDurableSession,
    required Future<CommonCodeLegacySeedLoadResult> Function({
      required String attachedClientId,
    })
    loadLegacySeedSession,
    required Future<Session> Function({
      required Session session,
      required String attachedClientId,
    })
    restoreLegacySeededSession,
    required Future<Session> Function(CommonCodeSessionBootstrapRequest request)
    createFreshSession,
  }) async {
    if (isBootstrapped) {
      return readBootstrappedSession();
    }

    final durableCandidate = await loadDurableSessionCandidate(
      attachedClientId: request.attachedClientId,
    );

    switch (durableCandidate.status) {
      case CommonCodeDurableBootstrapLoadStatus.available:
        try {
          return restoreDurableSession(durableCandidate.session!);
        } catch (_) {
          return createFreshSession(request);
        }
      case CommonCodeDurableBootstrapLoadStatus.missing:
      case CommonCodeDurableBootstrapLoadStatus.invalid:
      case CommonCodeDurableBootstrapLoadStatus.readFailed:
        return _bootstrapFromLegacySeedOrFresh(
          request: request,
          loadLegacySeedSession: loadLegacySeedSession,
          restoreLegacySeededSession: restoreLegacySeededSession,
          createFreshSession: createFreshSession,
        );
    }
  }

  Future<Session> _bootstrapFromLegacySeedOrFresh({
    required CommonCodeSessionBootstrapRequest request,
    required Future<CommonCodeLegacySeedLoadResult> Function({
      required String attachedClientId,
    })
    loadLegacySeedSession,
    required Future<Session> Function({
      required Session session,
      required String attachedClientId,
    })
    restoreLegacySeededSession,
    required Future<Session> Function(CommonCodeSessionBootstrapRequest request)
    createFreshSession,
  }) async {
    final legacySeed = await loadLegacySeedSession(
      attachedClientId: request.attachedClientId,
    );

    switch (legacySeed.status) {
      case CommonCodeLegacySeedLoadStatus.available:
        try {
          return await restoreLegacySeededSession(
            session: legacySeed.session!,
            attachedClientId: request.attachedClientId,
          );
        } catch (_) {
          return createFreshSession(request);
        }
      case CommonCodeLegacySeedLoadStatus.disabled:
      case CommonCodeLegacySeedLoadStatus.missing:
      case CommonCodeLegacySeedLoadStatus.failed:
        return createFreshSession(request);
    }
  }
}

final class CommonCodeSessionBootstrapLifecycle {
  CommonCodeSessionBootstrapLifecycle({
    CommonCodeSessionBootstrapOrchestrator orchestrator =
        const CommonCodeSessionBootstrapOrchestrator(),
  }) : _orchestrator = orchestrator;

  static final Expando<CommonCodeSessionBootstrapLifecycle> _lifecycles =
      Expando<CommonCodeSessionBootstrapLifecycle>(
        'commonCodeSessionBootstrapLifecycle',
      );

  static CommonCodeSessionBootstrapLifecycle of(Object owner) {
    return _lifecycles[owner] ??= CommonCodeSessionBootstrapLifecycle();
  }

  final CommonCodeSessionBootstrapOrchestrator _orchestrator;

  Session? _bootstrappedSession;

  bool get isBootstrapped => _bootstrappedSession != null;

  Session readBootstrappedSession() {
    final session = _bootstrappedSession;
    if (session == null) {
      throw StateError('Session has not been bootstrapped.');
    }

    return session;
  }

  void rememberBootstrappedSession(Session session) {
    _bootstrappedSession = session;
  }

  Future<Session> bootstrap({
    required CommonCodeSessionBootstrapRequest request,
    required CommonCodeSessionBootstrapPort port,
  }) async {
    final session = await _orchestrator.bootstrap(
      request: request,
      isBootstrapped: isBootstrapped,
      readBootstrappedSession: readBootstrappedSession,
      loadDurableSessionCandidate: port.loadDurableSessionCandidate,
      restoreDurableSession: port.restoreDurableSession,
      loadLegacySeedSession: port.loadLegacySeedSession,
      restoreLegacySeededSession: port.restoreLegacySeededSession,
      createFreshSession: port.createFreshSession,
    );
    rememberBootstrappedSession(session);
    return session;
  }
}
