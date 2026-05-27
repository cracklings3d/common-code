// ignore_for_file: implementation_imports

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_observability/common_code_observability.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:host_core/host_core.dart';
import 'package:host_in_memory/host_in_memory.dart';

import 'desktop_session_runtime.dart';

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
  final diagnosticsPort = resolveDurableLocalHostDiagnosticsPort(
    diagnosticsSink,
  );
  final effectiveSnapshotStore =
      (snapshotStore as SessionSnapshotStore?) ??
      SharedPreferencesSessionSnapshotStore();
  final effectiveSessionStore =
      DurableLocalSessionStore.fromPersistenceComponents(
        legacySnapshotStore: effectiveSnapshotStore,
        durableStorage: durableStorage,
      );
  final effectiveHostService =
      (hostService as HostService?) ?? (InMemoryHostAdapter() as HostService);
  final effectiveBootstrapPort =
      (bootstrapPort as CommonCodeSessionBootstrapPort?) ??
      CommonCodeSessionBootstrapPortAdapter(
        sessionStore: effectiveSessionStore,
        host: CommonCodeSessionBootstrapHost(
          restoreSession: effectiveHostService.restoreSession,
          createSession: effectiveHostService.createSession,
          attachClient: effectiveHostService.attachClient,
        ),
        diagnosticsPort: diagnosticsPort,
      );
  final effectivePersistSessionMutation =
      (persistSessionMutation as void Function(Session session)?) ??
      effectiveSessionStore.createPersistenceContinuation(
        attachedClientId: attachedClientId,
        onError: createDurableWriteFailureReporter(diagnosticsPort),
      );

  final CommonCodeSessionDriver effectiveDriver;
  final CommonCodeSessionObservation effectiveObservation;
  final HostGateway effectiveGateway;

  if (driver != null) {
    effectiveDriver = driver;
    effectiveObservation =
        observation ??
        switch (driver) {
          CommonCodeSessionObservation observation => observation,
          _ => throw ArgumentError.value(
            driver,
            'driver',
            'observation is required when driver does not implement '
                'CommonCodeSessionObservation.',
          ),
        };
    effectiveGateway =
        hostGateway ??
        (throw ArgumentError.value(
          driver,
          'driver',
          'hostGateway is required when providing a custom driver.',
        ));
  } else {
    effectiveObservation =
        observation ?? _DesktopSessionObservation(effectiveHostService);
    effectiveDriver = _DesktopSessionDriver(
      hostService: effectiveHostService,
      bootstrapPort: effectiveBootstrapPort,
      observation: effectiveObservation,
      persistSessionMutation: effectivePersistSessionMutation,
      defaultSessionId: defaultSessionId,
      hostId: hostId,
      attachedClientId: attachedClientId,
    );
    effectiveGateway =
        hostGateway ??
        _DesktopSessionHostGateway(
          hostService: effectiveHostService,
          persistSessionMutation: effectivePersistSessionMutation,
        );
  }

  return CommonCodeSessionFacade(
    driver: effectiveDriver,
    observation: effectiveObservation,
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
  Object? diagnosticsSink,
  String defaultSessionId = desktopSessionRuntimeDefaultSessionId,
  String hostId = desktopSessionRuntimeHostId,
  String attachedClientId = desktopSessionRuntimeAttachedClientId,
}) {
  final effectiveSnapshotStore =
      snapshotStore ?? SharedPreferencesSessionSnapshotStore();
  final diagnosticsPort = resolveDurableLocalHostDiagnosticsPort(
    diagnosticsSink,
  );
  final effectiveHostService =
      hostService ?? (InMemoryHostAdapter() as HostService);
  final sessionStore = DurableLocalSessionStore.fromPersistenceComponents(
    legacySnapshotStore: effectiveSnapshotStore,
    durableStorage: durableStorage,
  );
  final effectiveBootstrapPort =
      bootstrapPort ??
      CommonCodeSessionBootstrapPortAdapter(
        sessionStore: sessionStore,
        host: CommonCodeSessionBootstrapHost(
          restoreSession: effectiveHostService.restoreSession,
          createSession: effectiveHostService.createSession,
          attachClient: effectiveHostService.attachClient,
        ),
        diagnosticsPort: diagnosticsPort,
      );
  final effectivePersistSessionMutation =
      persistSessionMutation ??
      sessionStore.createPersistenceContinuation(
        attachedClientId: attachedClientId,
        onError: createDurableWriteFailureReporter(diagnosticsPort),
      );

  return HostDesktopSessionRuntime(
    hostService: effectiveHostService,
    bootstrapPort: effectiveBootstrapPort,
    snapshotStore: effectiveSnapshotStore,
    persistSessionMutation: effectivePersistSessionMutation,
    defaultSessionId: defaultSessionId,
    hostId: hostId,
    attachedClientId: attachedClientId,
  );
}

final class _DesktopSessionDriver implements CommonCodeSessionDriver {
  _DesktopSessionDriver({
    required HostService hostService,
    required CommonCodeSessionBootstrapPort bootstrapPort,
    required CommonCodeSessionObservation observation,
    required void Function(Session session)? persistSessionMutation,
    required String defaultSessionId,
    required String hostId,
    required String attachedClientId,
  }) : _hostService = hostService,
       _bootstrapPort = bootstrapPort,
       _observation = observation,
       _persistSessionMutation = persistSessionMutation,
       _defaultSessionId = defaultSessionId,
       _hostId = hostId,
       _attachedClientId = attachedClientId;

  final HostService _hostService;
  final CommonCodeSessionBootstrapPort _bootstrapPort;
  final CommonCodeSessionObservation _observation;
  final void Function(Session session)? _persistSessionMutation;
  final String _defaultSessionId;
  final String _hostId;
  final String _attachedClientId;

  String? _currentSessionId;
  final CommonCodeSessionBootstrapLifecycle _bootstrapLifecycle =
      CommonCodeSessionBootstrapLifecycle();

  @override
  Future<CommonCodeSessionBinding> ensureSession() async {
    final currentSessionId = _currentSessionId;
    if (currentSessionId != null) {
      return CommonCodeSessionBinding.attached(sessionId: currentSessionId);
    }

    final bootstrappedSession = await _bootstrapLifecycle.bootstrap(
      request: CommonCodeSessionBootstrapRequest(
        defaultSessionId: _defaultSessionId,
        hostId: _hostId,
        attachedClientId: _attachedClientId,
      ),
      port: _bootstrapPort,
    );
    _currentSessionId = bootstrappedSession.id;
    return CommonCodeSessionBinding.attached(sessionId: bootstrappedSession.id);
  }

  @override
  Future<void> acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  }) async {
    await ensureSession();
    final session = _hostService.acknowledgeNotification(
      sessionId: sessionId,
      notificationId: notificationId,
    );
    _persistSessionMutation?.call(session);
  }

  @override
  Future<void> submitTurn({
    required String sessionId,
    required String attachedClientId,
    required String submittedText,
  }) async {
    final session = _hostService.submitTurn(
      sessionId: sessionId,
      client: Client(id: attachedClientId),
      submittedText: submittedText,
    );
    _persistSessionMutation?.call(session);
  }

  @override
  Stream<Session> watchSession(String sessionId) {
    return _observation.watchSession(sessionId);
  }
}

final class _DesktopSessionObservation implements CommonCodeSessionObservation {
  const _DesktopSessionObservation(this._hostService);

  final HostService _hostService;

  @override
  Stream<Session> watchSession(String sessionId) {
    return _hostService.watchSession(sessionId);
  }
}

final class _DesktopSessionHostGateway implements HostGateway {
  const _DesktopSessionHostGateway({
    required HostService hostService,
    required void Function(Session session)? persistSessionMutation,
  }) : _hostService = hostService,
       _persistSessionMutation = persistSessionMutation;

  final HostService _hostService;
  final void Function(Session session)? _persistSessionMutation;

  @override
  Future<void> submitTurn({
    required String sessionId,
    required Client client,
    required String submittedText,
  }) async {
    final session = _hostService.submitTurn(
      sessionId: sessionId,
      client: client,
      submittedText: submittedText,
    );
    _persistSessionMutation?.call(session);
  }
}
