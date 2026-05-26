// ignore_for_file: implementation_imports

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:host_core/host_core.dart';
import 'package:host_in_memory/host_in_memory.dart';

import 'desktop_session_runtime_constants.dart';
import 'desktop_session_runtime.dart';
import 'durable_local_host_service.dart';

CommonCodeSessionFacade createDesktopSessionFacade({
  CommonCodeSessionDriver? driver,
  CommonCodeSessionObservation? observation,
  HostGateway? hostGateway,
  String attachedClientId = desktopSessionRuntimeAttachedClientId,
  Object? hostService,
  Object? bootstrapPort,
  Object? persistSessionMutation,
  Object? snapshotStore,
  Object? durableStorage,
  Object? diagnosticsSink,
  String defaultSessionId = desktopSessionRuntimeDefaultSessionId,
  String hostId = desktopSessionRuntimeHostId,
}) {
  final SessionSnapshotStore effectiveSnapshotStore =
      (snapshotStore as SessionSnapshotStore?) ??
      SharedPreferencesSessionSnapshotStore();
  final CommonCodeSessionStore effectiveSessionStore =
      DurableLocalSessionStore.fromPersistenceComponents(
        legacySnapshotStore: effectiveSnapshotStore,
        durableStorage: durableStorage,
      );
  final HostService effectiveHostService;
  final CommonCodeSessionBootstrapPort? effectiveBootstrapPort;
  final void Function(Session session)? effectivePersistSessionMutation;
  if (hostService case final HostService providedHostService) {
    effectiveHostService = providedHostService;
    effectiveBootstrapPort = bootstrapPort as CommonCodeSessionBootstrapPort?;
    effectivePersistSessionMutation =
        persistSessionMutation as void Function(Session session)?;
  } else {
    final hostAdapter = InMemoryHostAdapter();
    final durableService = DurableLocalHostService.withAdapter(
      hostAdapter: hostAdapter,
      sessionStore: effectiveSessionStore,
      diagnosticsSink: diagnosticsSink as DurableLocalHostDiagnosticsSink?,
    );
    effectiveHostService = hostAdapter as HostService;
    effectiveBootstrapPort = durableService;
    effectivePersistSessionMutation = durableService.queueSessionPersistence;
  }

  final CommonCodeSessionDriver effectiveDriver =
      driver ??
      HostCoreDesktopSessionDriver(
        hostService: effectiveHostService,
        bootstrapPort: effectiveBootstrapPort,
        persistSessionMutation: effectivePersistSessionMutation,
        sessionStore: effectiveSessionStore,
        defaultSessionId: defaultSessionId,
        hostId: hostId,
        attachedClientId: attachedClientId,
      );
  final HostCoreDesktopSessionDriver? hostCoreDriver = switch (effectiveDriver) {
    HostCoreDesktopSessionDriver driver => driver,
    _ => null,
  };
  final effectiveGateway =
      hostGateway ??
      (hostCoreDriver == null
          ? (throw ArgumentError.value(
              driver,
              'driver',
              'hostGateway is required when driver is not a '
                  'HostCoreDesktopSessionDriver.',
            ))
          : _HostCoreDesktopHostGateway(
              serviceProvider: () => hostCoreDriver.sharedService,
              persistSessionMutation: () =>
                  hostCoreDriver.persistSessionMutation,
            ));

  return CommonCodeSessionFacade(
    driver: effectiveDriver,
    observation: observation ?? effectiveDriver as CommonCodeSessionObservation,
    hostGateway: effectiveGateway,
    attachedClientId: attachedClientId,
  );
}

HostDesktopSessionRuntime createDesktopSessionRuntime({
  HostService? hostService,
  CommonCodeSessionBootstrapPort? bootstrapPort,
  SessionSnapshotStore? snapshotStore,
  void Function(Session session)? persistSessionMutation,
  Object? durableStorage,
  DurableLocalHostDiagnosticsSink? diagnosticsSink,
  String defaultSessionId = desktopSessionRuntimeDefaultSessionId,
  String hostId = desktopSessionRuntimeHostId,
  String attachedClientId = desktopSessionRuntimeAttachedClientId,
}) {
  final effectiveSnapshotStore =
      snapshotStore ?? SharedPreferencesSessionSnapshotStore();

  if (hostService != null) {
    return HostDesktopSessionRuntime(
      hostService: hostService,
      bootstrapPort: bootstrapPort,
      snapshotStore: effectiveSnapshotStore,
      persistSessionMutation: persistSessionMutation,
      defaultSessionId: defaultSessionId,
      hostId: hostId,
      attachedClientId: attachedClientId,
    );
  }

  final hostAdapter = InMemoryHostAdapter();
  final durableService = DurableLocalHostService.withAdapter(
    hostAdapter: hostAdapter,
    sessionStore: DurableLocalSessionStore.fromPersistenceComponents(
      legacySnapshotStore: effectiveSnapshotStore,
      durableStorage: durableStorage,
    ),
    diagnosticsSink: diagnosticsSink,
  );
  return HostDesktopSessionRuntime(
    hostService: hostAdapter as HostService,
    bootstrapPort: durableService,
    snapshotStore: effectiveSnapshotStore,
    persistSessionMutation: durableService.queueSessionPersistence,
    defaultSessionId: defaultSessionId,
    hostId: hostId,
    attachedClientId: attachedClientId,
  );
}

final class HostCoreDesktopSessionDriver
    implements CommonCodeSessionDriver, CommonCodeSessionObservation {
  HostCoreDesktopSessionDriver({
    HostService? hostService,
    CommonCodeSessionBootstrapPort? bootstrapPort,
    void Function(Session session)? persistSessionMutation,
    CommonCodeSessionStore? sessionStore,
    String defaultSessionId = desktopSessionRuntimeDefaultSessionId,
    String hostId = desktopSessionRuntimeHostId,
    String attachedClientId = desktopSessionRuntimeAttachedClientId,
  }) : _hostService = hostService,
        _bootstrapPort = bootstrapPort,
        _persistSessionMutation = persistSessionMutation,
        _sessionStore = sessionStore ?? DurableLocalSessionStore(),
        _defaultSessionId = defaultSessionId,
        _hostId = hostId,
        _attachedClientId = attachedClientId;

  final HostService? _hostService;
  final CommonCodeSessionBootstrapPort? _bootstrapPort;
  final void Function(Session session)? _persistSessionMutation;
  final CommonCodeSessionStore _sessionStore;
  final String _defaultSessionId;
  final String _hostId;
  final String _attachedClientId;

  HostService? _service;
  CommonCodeSessionBootstrapPort? _resolvedBootstrapPort;
  void Function(Session session)? _resolvedPersistSessionMutation;
  bool _isBootstrapped = false;
  String? _currentSessionId;
  final CommonCodeSessionBootstrapLifecycle _bootstrapLifecycle =
      CommonCodeSessionBootstrapLifecycle();

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
    final service = _resolveService();
    await _bootstrapIfNeeded();

    final session = service.acknowledgeNotification(
      sessionId: sessionId,
      notificationId: notificationId,
    );
    persistSessionMutation?.call(session);
  }

  @override
  Future<void> submitTurn({
    required String sessionId,
    required String attachedClientId,
    required String submittedText,
  }) async {
    final service = _resolveService();
    await _bootstrapIfNeeded();

    final session = service.submitTurn(
      sessionId: sessionId,
      client: Client(id: attachedClientId),
      submittedText: submittedText,
    );
    persistSessionMutation?.call(session);
  }

  @override
  Stream<Session> watchSession(String sessionId) {
    final service = _resolveService();
    return service.watchSession(sessionId);
  }

  /// Returns the shared HostService instance used by this driver.
  HostService get sharedService => _resolveService();

  void Function(Session session)? get persistSessionMutation {
    _resolveService();
    return _resolvedPersistSessionMutation;
  }

  Future<void> _bootstrapIfNeeded() async {
    final service = _resolveService();
    if (_isBootstrapped) {
      return;
    }

    final CommonCodeSessionBootstrapPort? bootstrapPort =
        _resolvedBootstrapPort ??
        (service is CommonCodeSessionBootstrapPort
            ? service as CommonCodeSessionBootstrapPort
            : null);
    if (bootstrapPort != null) {
      final bootstrappedSession = await _bootstrapLifecycle.bootstrap(
        request: CommonCodeSessionBootstrapRequest(
          defaultSessionId: _defaultSessionId,
          hostId: _hostId,
          attachedClientId: _attachedClientId,
        ),
        port: bootstrapPort,
      );
      _currentSessionId = bootstrappedSession.id;
      _isBootstrapped = true;
      return;
    }

    final legacySeed = await _sessionStore.loadLegacySeedSession(
      attachedClientId: _attachedClientId,
    );
    final restoredSession = legacySeed.session;
    if (restoredSession != null) {
      try {
        // ignore: deprecated_member_use
        final session = service.restoreSession(restoredSession);
        persistSessionMutation?.call(session);
        _currentSessionId = restoredSession.id;
        _isBootstrapped = true;
        return;
      } catch (_) {
        // Fall back to the fresh desktop bootstrap path.
      }
    }

    // ignore: deprecated_member_use
    service.createSession(
      sessionId: _defaultSessionId,
      activeHost: Host(id: _hostId),
    );
    // ignore: deprecated_member_use
    final attachedSession = service.attachClient(
      sessionId: _defaultSessionId,
      client: Client(id: _attachedClientId),
    );
    persistSessionMutation?.call(attachedSession);
    _currentSessionId = _defaultSessionId;
    _isBootstrapped = true;
  }

  HostService _resolveService() {
    final existingService = _service;
    if (existingService != null) {
      return existingService;
    }

    final injectedService = _hostService;
    if (injectedService != null) {
      _resolvedBootstrapPort = _bootstrapPort;
      _resolvedPersistSessionMutation = _persistSessionMutation;
      return _service = injectedService;
    }

    throw StateError('HostCoreDesktopSessionDriver requires an injected HostService.');
  }
}

/// Host gateway adapter that delegates to HostService.submitTurn.
///
/// This is the desktop-specific implementation of [HostGateway] that
/// wraps the transitional HostService boundary.
final class _HostCoreDesktopHostGateway implements HostGateway {
  _HostCoreDesktopHostGateway({
    required HostService Function() serviceProvider,
    required void Function(Session session)? Function() persistSessionMutation,
  }) : _serviceProvider = serviceProvider,
       _persistSessionMutation = persistSessionMutation;

  final HostService Function() _serviceProvider;
  final void Function(Session session)? Function() _persistSessionMutation;

  @override
  Future<void> submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) async {
    final service = _serviceProvider();

    final session = service.submitTurn(
      sessionId: sessionId,
      client: client,
      submittedText: submittedText,
    );
    _persistSessionMutation()?.call(session);
  }
}
