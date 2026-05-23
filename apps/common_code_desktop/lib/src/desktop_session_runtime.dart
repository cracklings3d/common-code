import 'dart:async';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';

import 'desktop_session_app_edge_composition.dart';
import 'desktop_session_runtime_constants.dart';

export 'desktop_session_runtime_constants.dart';

abstract interface class DesktopSessionRuntime {
  void bind({
    required void Function(Session session) onSnapshot,
    required void Function(Object error, StackTrace stackTrace) onWatchError,
  });

  Stream<CommonCodeSessionFacadeState> get states;

  CommonCodeSessionFacadeState get state;

  Future<void> initialize();

  Future<void> refresh();

  Future<void> acknowledgeNotification({required String notificationId});

  Future<void> submitTurn({required String submittedText});

  Future<void> dispose();
}

final class HostDesktopSessionRuntime implements DesktopSessionRuntime {
  HostDesktopSessionRuntime({
    CommonCodeSessionFacade? facade,
    Object? hostService,
    Object? snapshotStore,
    Object? durableStorage,
    Object Function()? hostServiceFactory,
    Object? diagnosticsSink,
    String defaultSessionId = desktopSessionRuntimeDefaultSessionId,
    String hostId = desktopSessionRuntimeHostId,
    String attachedClientId = desktopSessionRuntimeAttachedClientId,
  }) : _facade =
           facade ??
           createDesktopSessionFacade(
             hostService: hostService,
             snapshotStore: snapshotStore,
             durableStorage: durableStorage,
             hostServiceFactory: hostServiceFactory,
             diagnosticsSink: diagnosticsSink,
             defaultSessionId: defaultSessionId,
             hostId: hostId,
             attachedClientId: attachedClientId,
           );

  final CommonCodeSessionFacade _facade;
  StreamSubscription<CommonCodeSessionFacadeState>? _compatibilitySubscription;

  @override
  void bind({
    required void Function(Session session) onSnapshot,
    required void Function(Object error, StackTrace stackTrace) onWatchError,
  }) {
    _compatibilitySubscription?.cancel();
    _compatibilitySubscription = states.listen((state) {
      switch (state.status) {
        case CommonCodeSessionFacadeStatus.data:
          onSnapshot(state.snapshot!.session);
        case CommonCodeSessionFacadeStatus.error:
          onWatchError(StateError(state.message!), StackTrace.current);
        case CommonCodeSessionFacadeStatus.loading:
        case CommonCodeSessionFacadeStatus.empty:
          break;
      }
    });
  }

  @override
  Stream<CommonCodeSessionFacadeState> get states => _facade.states;

  @override
  CommonCodeSessionFacadeState get state => _facade.state;

  @override
  Future<void> initialize() => _facade.initialize();

  @override
  Future<void> refresh() => _facade.refresh();

  @override
  Future<void> acknowledgeNotification({required String notificationId}) =>
      _facade.acknowledgeNotification(notificationId: notificationId);

  @override
  Future<void> submitTurn({required String submittedText}) =>
      _facade.submitTurn(submittedText: submittedText);

  @override
  Future<void> dispose() async {
    await _compatibilitySubscription?.cancel();
    await _facade.dispose();
  }
}
