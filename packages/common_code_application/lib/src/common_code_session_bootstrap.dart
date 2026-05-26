import 'package:common_code_domain/common_code_domain.dart';

import 'common_code_session_store.dart';

abstract interface class CommonCodeSessionBootstrapPort {
  CommonCodeSessionStore get sessionStore;

  Session restoreDurableSession(Session session);

  Future<Session> restoreLegacySeededSession({
    required Session session,
    required String attachedClientId,
  });

  Future<Session> createFreshSession(CommonCodeSessionBootstrapRequest request);
}

final class CommonCodeSessionBootstrapRequest {
  const CommonCodeSessionBootstrapRequest({
    required this.defaultSessionId,
    required this.hostId,
    required this.attachedClientId,
  });

  final String defaultSessionId;
  final String hostId;
  final String attachedClientId;
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
      loadDurableSessionCandidate: port.sessionStore.loadDurableSessionCandidate,
      restoreDurableSession: port.restoreDurableSession,
      loadLegacySeedSession: port.sessionStore.loadLegacySeedSession,
      restoreLegacySeededSession: port.restoreLegacySeededSession,
      createFreshSession: port.createFreshSession,
    );
    rememberBootstrappedSession(session);
    return session;
  }
}
