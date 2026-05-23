import 'package:common_code_domain/common_code_domain.dart';

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

  const CommonCodeDurableBootstrapLoadResult.readFailed()
    : this._(status: CommonCodeDurableBootstrapLoadStatus.readFailed);

  final CommonCodeDurableBootstrapLoadStatus status;
  final Session? session;
}

enum CommonCodeLegacySeedLoadStatus { available, disabled, missing, failed }

final class CommonCodeLegacySeedLoadResult {
  const CommonCodeLegacySeedLoadResult._({required this.status, this.session});

  const CommonCodeLegacySeedLoadResult.available(Session session)
    : this._(
        status: CommonCodeLegacySeedLoadStatus.available,
        session: session,
      );

  const CommonCodeLegacySeedLoadResult.disabled()
    : this._(status: CommonCodeLegacySeedLoadStatus.disabled);

  const CommonCodeLegacySeedLoadResult.missing()
    : this._(status: CommonCodeLegacySeedLoadStatus.missing);

  const CommonCodeLegacySeedLoadResult.failed()
    : this._(status: CommonCodeLegacySeedLoadStatus.failed);

  final CommonCodeLegacySeedLoadStatus status;
  final Session? session;
}

abstract interface class CommonCodeSessionBootstrapPort {
  bool get isBootstrapped;

  Session readBootstrappedSession();

  Future<CommonCodeDurableBootstrapLoadResult> loadDurableSessionCandidate({
    required String attachedClientId,
  });

  Session restoreDurableSession(Session session);

  Future<CommonCodeLegacySeedLoadResult> loadLegacySeedSession({
    required String attachedClientId,
  });

  Future<Session> restoreLegacySeededSession({
    required Session session,
    required String attachedClientId,
  });

  Future<Session> createFreshSession(CommonCodeSessionBootstrapRequest request);
}

final class CommonCodeSessionBootstrapOrchestrator {
  const CommonCodeSessionBootstrapOrchestrator();

  Future<Session> bootstrap({
    required CommonCodeSessionBootstrapPort port,
    required CommonCodeSessionBootstrapRequest request,
  }) async {
    if (port.isBootstrapped) {
      return port.readBootstrappedSession();
    }

    final durableCandidate = await port.loadDurableSessionCandidate(
      attachedClientId: request.attachedClientId,
    );

    switch (durableCandidate.status) {
      case CommonCodeDurableBootstrapLoadStatus.available:
        try {
          return port.restoreDurableSession(durableCandidate.session!);
        } catch (_) {
          return port.createFreshSession(request);
        }
      case CommonCodeDurableBootstrapLoadStatus.missing:
      case CommonCodeDurableBootstrapLoadStatus.invalid:
      case CommonCodeDurableBootstrapLoadStatus.readFailed:
        return _bootstrapFromLegacySeedOrFresh(port: port, request: request);
    }
  }

  Future<Session> _bootstrapFromLegacySeedOrFresh({
    required CommonCodeSessionBootstrapPort port,
    required CommonCodeSessionBootstrapRequest request,
  }) async {
    final legacySeed = await port.loadLegacySeedSession(
      attachedClientId: request.attachedClientId,
    );

    switch (legacySeed.status) {
      case CommonCodeLegacySeedLoadStatus.available:
        try {
          return await port.restoreLegacySeededSession(
            session: legacySeed.session!,
            attachedClientId: request.attachedClientId,
          );
        } catch (_) {
          return port.createFreshSession(request);
        }
      case CommonCodeLegacySeedLoadStatus.disabled:
      case CommonCodeLegacySeedLoadStatus.missing:
      case CommonCodeLegacySeedLoadStatus.failed:
        return port.createFreshSession(request);
    }
  }
}
