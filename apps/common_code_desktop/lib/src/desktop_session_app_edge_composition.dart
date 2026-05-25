// ignore_for_file: implementation_imports

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_application/src/common_code_session_bootstrap.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_observability/common_code_observability.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:host_core/host_core.dart';

import 'desktop_session_runtime_constants.dart';
import 'durable_local_host_service.dart';

CommonCodeSessionFacade createDesktopSessionFacade({
  CommonCodeSessionDriver? driver,
  CommonCodeSessionObservation? observation,
  HostGateway? hostGateway,
  String attachedClientId = desktopSessionRuntimeAttachedClientId,
  String identityId = desktopSessionRuntimeIdentityId,
  Object? hostService,
  Object? snapshotStore,
  Object? durableStorage,
  Object Function()? hostServiceFactory,
  Object? diagnosticsSink,
  String defaultSessionId = desktopSessionRuntimeDefaultSessionId,
  String hostId = desktopSessionRuntimeHostId,
}) {
  final effectiveDriver =
      driver ??
      HostCoreDesktopSessionDriver(
        hostService: hostService as HostService?,
        snapshotStore: snapshotStore as SessionSnapshotStore?,
        durableStorage: durableStorage as DurableSessionStore?,
        hostServiceFactory: hostServiceFactory == null
            ? null
            : () => hostServiceFactory() as HostService,
        diagnosticsSink: diagnosticsSink as DurableLocalHostDiagnosticsSink?,
        defaultSessionId: defaultSessionId,
        hostId: hostId,
        identityId: identityId,
        attachedClientId: attachedClientId,
      );
  final effectiveGateway =
      hostGateway ??
      _HostCoreDesktopHostGateway(
        serviceProvider: () =>
            (effectiveDriver as HostCoreDesktopSessionDriver).sharedService,
      );

  return CommonCodeSessionFacade(
    driver: effectiveDriver,
    observation: observation ?? effectiveDriver as CommonCodeSessionObservation,
    hostGateway: effectiveGateway,
    attachedClientId: attachedClientId,
  );
}

final class HostCoreDesktopSessionDriver
    implements CommonCodeSessionDriver, CommonCodeSessionObservation {
  HostCoreDesktopSessionDriver({
    HostService? hostService,
    SessionSnapshotStore? snapshotStore,
    DurableSessionStore? durableStorage,
    HostService Function()? hostServiceFactory,
    DurableLocalHostDiagnosticsSink? diagnosticsSink,
    String defaultSessionId = desktopSessionRuntimeDefaultSessionId,
    String hostId = desktopSessionRuntimeHostId,
    String identityId = desktopSessionRuntimeIdentityId,
    String attachedClientId = desktopSessionRuntimeAttachedClientId,
  }) : _hostService = hostService,
       _legacySnapshotStore =
           snapshotStore ?? SharedPreferencesSessionSnapshotStore(),
       _durableStorage =
           durableStorage ?? SharedPreferencesDurableSessionStore(),
       _hostServiceFactory =
           hostServiceFactory ??
           (() => DurableLocalHostService(
             legacySnapshotStore:
                 snapshotStore ?? SharedPreferencesSessionSnapshotStore(),
             durableStorage:
                 durableStorage ?? SharedPreferencesDurableSessionStore(),
             diagnosticsSink: diagnosticsSink,
           )),
       _defaultSessionId = defaultSessionId,
       _hostId = hostId,
       _identityId = identityId,
       _attachedClientId = attachedClientId;

  final HostService? _hostService;
  final SessionSnapshotStore _legacySnapshotStore;
  final DurableSessionStore _durableStorage;
  final HostService Function() _hostServiceFactory;
  final String _defaultSessionId;
  final String _hostId;
  final String _identityId;
  final String _attachedClientId;

  HostService? _service;
  bool _isBootstrapped = false;
  String? _currentSessionId;
  static const CommonCodeSessionBootstrapOrchestrator _bootstrapOrchestrator =
      CommonCodeSessionBootstrapOrchestrator();

  @override
  Future<CommonCodeSessionBinding> ensureSession() async {
    await _bootstrapIfNeeded();
    return CommonCodeSessionBinding.attached(
      sessionId: _currentSessionId!,
      identity: Identity(id: _identityId),
      attachedClientId: _attachedClientId,
    );
  }

  @override
  Future<void> acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  }) async {
    final service = _service ??= _hostService ?? _hostServiceFactory();
    await _bootstrapIfNeeded();

    service.acknowledgeNotification(
      sessionId: sessionId,
      notificationId: notificationId,
    );
  }

  @override
  Future<void> submitTurn({
    required String sessionId,
    required String attachedClientId,
    required String submittedText,
  }) async {
    final service = _service ??= _hostService ?? _hostServiceFactory();
    await _bootstrapIfNeeded();

    service.submitTurn(
      sessionId: sessionId,
      client: Client(id: attachedClientId),
      submittedText: submittedText,
    );
  }

  @override
  Stream<Session> watchSession(String sessionId) {
    final service = _service ??= _hostService ?? _hostServiceFactory();
    return service.watchSession(sessionId);
  }

  /// Returns the shared HostService instance used by this driver.
  HostService get sharedService =>
      _service ??= _hostService ?? _hostServiceFactory();

  Future<void> _bootstrapIfNeeded() async {
    final service = _service ??= _hostService ?? _hostServiceFactory();
    if (_isBootstrapped) {
      return;
    }

    if (service case final DurableLocalHostService durableService) {
      final bootstrappedSession = await _bootstrapOrchestrator.bootstrap(
        request: CommonCodeSessionBootstrapRequest(
          defaultSessionId: _defaultSessionId,
          hostId: _hostId,
          attachedClientId: _attachedClientId,
        ),
        isBootstrapped: durableService.isBootstrapped,
        readBootstrappedSession: durableService.readBootstrappedSession,
        loadDurableSessionCandidate: durableService.loadDurableSessionCandidate,
        restoreDurableSession: durableService.restoreDurableSession,
        loadLegacySeedSession: durableService.loadLegacySeedSession,
        restoreLegacySeededSession: durableService.restoreLegacySeededSession,
        createFreshSession: durableService.createFreshSession,
      );
      _currentSessionId = bootstrappedSession.id;
      _isBootstrapped = true;
      return;
    }

    final restoredSession = await _legacySnapshotStore.readLatestSession(
      desktopClientId: _attachedClientId,
    );
    if (restoredSession != null) {
      try {
        service.restoreSession(restoredSession);
        _currentSessionId = restoredSession.id;
        _isBootstrapped = true;
        return;
      } catch (_) {
        // Fall back to the fresh desktop bootstrap path.
      }
    }

    service.createSession(
      sessionId: _defaultSessionId,
      activeHost: Host(id: _hostId),
    );
    service.attachClient(
      sessionId: _defaultSessionId,
      client: Client(id: _attachedClientId),
    );
    _currentSessionId = _defaultSessionId;
    _isBootstrapped = true;
  }
}

/// Host gateway adapter that delegates to HostService.submitTurn.
///
/// This is the desktop-specific implementation of [HostGateway] that
/// wraps the transitional HostService boundary.
final class _HostCoreDesktopHostGateway implements HostGateway {
  _HostCoreDesktopHostGateway({required HostService Function() serviceProvider})
    : _serviceProvider = serviceProvider;

  final HostService Function() _serviceProvider;

  @override
  Future<void> submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) async {
    final service = _serviceProvider();

    service.submitTurn(
      sessionId: sessionId,
      client: client,
      submittedText: submittedText,
    );
  }
}
