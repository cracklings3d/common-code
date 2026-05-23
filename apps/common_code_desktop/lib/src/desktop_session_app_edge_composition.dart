// ignore_for_file: implementation_imports

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_application/src/common_code_session_bootstrap.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:host_core/host_core.dart';

import 'desktop_session_runtime_constants.dart';
import 'desktop_session_snapshot_store.dart';
import 'durable_local_host_service.dart';

CommonCodeSessionFacade createDesktopSessionFacade({
  CommonCodeSessionDriver? driver,
  String attachedClientId = desktopSessionRuntimeAttachedClientId,
  Object? hostService,
  Object? snapshotStore,
  Object Function()? hostServiceFactory,
  Object? diagnosticsSink,
  String defaultSessionId = desktopSessionRuntimeDefaultSessionId,
  String hostId = desktopSessionRuntimeHostId,
}) {
  return CommonCodeSessionFacade(
    driver:
        driver ??
        HostCoreDesktopSessionDriver(
          hostService: hostService as HostService?,
          snapshotStore: snapshotStore as DesktopSessionSnapshotStore?,
          hostServiceFactory: hostServiceFactory == null
              ? null
              : () => hostServiceFactory() as HostService,
          diagnosticsSink: diagnosticsSink as DurableLocalHostDiagnosticsSink?,
          defaultSessionId: defaultSessionId,
          hostId: hostId,
          attachedClientId: attachedClientId,
        ),
    attachedClientId: attachedClientId,
  );
}

final class HostCoreDesktopSessionDriver implements CommonCodeSessionDriver {
  HostCoreDesktopSessionDriver({
    HostService? hostService,
    DesktopSessionSnapshotStore? snapshotStore,
    HostService Function()? hostServiceFactory,
    DurableLocalHostDiagnosticsSink? diagnosticsSink,
    String defaultSessionId = desktopSessionRuntimeDefaultSessionId,
    String hostId = desktopSessionRuntimeHostId,
    String attachedClientId = desktopSessionRuntimeAttachedClientId,
  }) : _hostService = hostService,
       _legacySnapshotStore =
           snapshotStore ?? SharedPreferencesDesktopSessionSnapshotStore(),
       _hostServiceFactory =
           hostServiceFactory ??
           (() => DurableLocalHostService(
             legacySnapshotStore:
                 snapshotStore ??
                 SharedPreferencesDesktopSessionSnapshotStore(),
             diagnosticsSink: diagnosticsSink,
           )),
       _defaultSessionId = defaultSessionId,
       _hostId = hostId,
       _attachedClientId = attachedClientId;

  final HostService? _hostService;
  final DesktopSessionSnapshotStore _legacySnapshotStore;
  final HostService Function() _hostServiceFactory;
  final String _defaultSessionId;
  final String _hostId;
  final String _attachedClientId;

  HostService? _service;
  bool _isBootstrapped = false;
  String? _currentSessionId;
  static const CommonCodeSessionBootstrapOrchestrator _bootstrapOrchestrator =
      CommonCodeSessionBootstrapOrchestrator();

  @override
  Future<CommonCodeSessionBinding> ensureSession() async {
    await _bootstrapIfNeeded();
    return CommonCodeSessionBinding.attached(sessionId: _currentSessionId!);
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
