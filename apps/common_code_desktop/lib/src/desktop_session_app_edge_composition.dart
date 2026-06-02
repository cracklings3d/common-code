// ignore_for_file: implementation_imports

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_observability/common_code_observability.dart';
import 'package:common_code_persistence/common_code_persistence.dart';

import 'package:host_opencode/host_opencode.dart';

import 'desktop_session_facade_adapters.dart';
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
  String desktopIdentityId = desktopSessionRuntimeIdentityId,
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
      (hostService as HostService?) ??
      (OutOfProcessOpenCodeHostAdapter(
            connector: const OpenCodeHostProcessConnector(),
            launcher: const OpenCodeHostProcessLauncher(),
          )
          as HostService);
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
  final sessionGateway = OpenCodeHostGateway(
    hostService: effectiveHostService,
    persistSessionMutation: effectivePersistSessionMutation,
  );

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
        observation ??
        OpenCodePersistingHostServiceSessionObservation(
          observation: OpenCodeHostServiceSessionObservation(
            effectiveHostService,
          ),
          persistSessionMutation: effectivePersistSessionMutation,
        );
    effectiveDriver = DesktopSessionBootstrapDriver(
      bootstrapPort: effectiveBootstrapPort,
      mutationPort: HostGatewayDesktopSessionMutationPort(
        hostGateway: sessionGateway,
        hostService: effectiveHostService,
      ),
      observation: effectiveObservation,
      defaultSessionId: defaultSessionId,
      hostId: hostId,
      attachedClientId: attachedClientId,
      desktopIdentityId: desktopIdentityId,
      bootstrapRequest: CommonCodeSessionBootstrapRequest(
        defaultSessionId: defaultSessionId,
        hostId: hostId,
        attachedClientId: attachedClientId,
        desktopIdentity: Identity(id: desktopIdentityId),
      ),
    );
    effectiveGateway = hostGateway ?? sessionGateway;
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
  String desktopIdentityId = desktopSessionRuntimeIdentityId,
}) {
  final effectiveSnapshotStore =
      snapshotStore ?? SharedPreferencesSessionSnapshotStore();
  final diagnosticsPort = resolveDurableLocalHostDiagnosticsPort(
    diagnosticsSink,
  );
  final effectiveHostService =
      hostService ??
      (OutOfProcessOpenCodeHostAdapter(
            connector: const OpenCodeHostProcessConnector(),
            launcher: const OpenCodeHostProcessLauncher(),
          )
          as HostService);
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

  final bootstrapRequest = CommonCodeSessionBootstrapRequest(
    defaultSessionId: defaultSessionId,
    hostId: hostId,
    attachedClientId: attachedClientId,
    desktopIdentity: Identity(id: desktopIdentityId),
  );

  return HostDesktopSessionRuntime(
    hostService: effectiveHostService,
    bootstrapPort: effectiveBootstrapPort,
    snapshotStore: effectiveSnapshotStore,
    persistSessionMutation: effectivePersistSessionMutation,
    defaultSessionId: defaultSessionId,
    hostId: hostId,
    attachedClientId: attachedClientId,
    desktopIdentityId: desktopIdentityId,
    bootstrapRequest: bootstrapRequest,
  );
}
