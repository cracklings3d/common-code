import 'dart:async';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:host_core/host_core.dart';

import 'package:common_code_persistence/common_code_persistence.dart';

export 'desktop_session_runtime_constants.dart'
    show
        desktopSessionRuntimeAttachedClientId,
        desktopSessionRuntimeDefaultSessionId,
        desktopSessionRuntimeHostId,
        desktopSessionRuntimeIdentityId;

import 'desktop_session_runtime_constants.dart';

final class _RuntimeSessionContext {
  const _RuntimeSessionContext({
    required this.sessionId,
    required this.identity,
    required this.attachedClientId,
  });

  final String sessionId;
  final Identity identity;
  final String attachedClientId;
}

abstract interface class DesktopSessionRuntime {
  void bind({
    required void Function(Session session) onSnapshot,
    required void Function(Object error, StackTrace stackTrace) onWatchError,
  });

  Future<void> initialize();

  Future<void> refresh();

  Future<void> acknowledgeNotification({required String notificationId});

  Future<void> submitTurn({required String submittedText});

  Future<void> dispose();
}

final class HostDesktopSessionRuntime implements DesktopSessionRuntime {
  HostDesktopSessionRuntime({
    HostService? hostService,
    CommonCodeSessionBootstrapPort? bootstrapPort,
    SessionSnapshotStore? snapshotStore,
    void Function(Session session)? persistSessionMutation,
    Object? diagnosticsSink,
    String defaultSessionId = desktopSessionRuntimeDefaultSessionId,
    String hostId = desktopSessionRuntimeHostId,
    String attachedClientId = desktopSessionRuntimeAttachedClientId,
    String desktopIdentityId = desktopSessionRuntimeIdentityId,
  }) : _hostService = hostService,
       _bootstrapPort = bootstrapPort,
       _legacySnapshotStore =
           snapshotStore ?? SharedPreferencesSessionSnapshotStore(),
       _persistSessionMutation = persistSessionMutation,
       _defaultSessionId = defaultSessionId,
       _hostId = hostId,
       _attachedClientId = attachedClientId,
       _desktopIdentityId = desktopIdentityId;

  final HostService? _hostService;
  final CommonCodeSessionBootstrapPort? _bootstrapPort;
  final SessionSnapshotStore _legacySnapshotStore;
  final void Function(Session session)? _persistSessionMutation;
  final String _defaultSessionId;
  final String _hostId;
  final String _attachedClientId;
  final String _desktopIdentityId;

  void Function(Session session)? _onSnapshot;
  void Function(Object error, StackTrace stackTrace)? _onWatchError;
  HostService? _service;
  CommonCodeSessionBootstrapPort? _resolvedBootstrapPort;
  void Function(Session session)? _resolvedPersistSessionMutation;
  StreamSubscription<Session>? _watchSubscription;
  Future<void> _watchRestartSequence = Future<void>.value();
  bool _isBootstrapped = false;
  bool _isDisposed = false;
  String? _currentSessionId;
  _RuntimeSessionContext? _currentSessionContext;
  CommonCodeSessionBootstrapRequest? _currentBootstrapRequest;
  int _watchGeneration = 0;
  final CommonCodeSessionBootstrapLifecycle _bootstrapLifecycle =
      CommonCodeSessionBootstrapLifecycle();

  @visibleForTesting
  ({String sessionId, Identity identity, String attachedClientId})?
  get debugSessionContext {
    final context = _currentSessionContext;
    if (context == null) {
      return null;
    }

    return (
      sessionId: context.sessionId,
      identity: context.identity,
      attachedClientId: context.attachedClientId,
    );
  }

  @override
  void bind({
    required void Function(Session session) onSnapshot,
    required void Function(Object error, StackTrace stackTrace) onWatchError,
  }) {
    _onSnapshot = onSnapshot;
    _onWatchError = onWatchError;
  }

  @override
  Future<void> initialize() => _startSessionWatch();

  @override
  Future<void> refresh() => _startSessionWatch();

  @override
  Future<void> acknowledgeNotification({required String notificationId}) async {
    final service = _resolveService();
    final context = await _ensureSessionContext();

    final session = service.acknowledgeNotification(
      sessionId: context.sessionId,
      notificationId: notificationId,
    );
    _persistSessionMutationForResolvedService()?.call(session);
  }

  @override
  Future<void> submitTurn({required String submittedText}) async {
    final service = _resolveService();
    final context = await _ensureSessionContext();

    final session = service.submitTurn(
      sessionId: context.sessionId,
      client: Client(id: context.attachedClientId),
      submittedText: submittedText,
    );
    _persistSessionMutationForResolvedService()?.call(session);
  }

  Future<void> _startSessionWatch() {
    final scheduledRestart = _watchRestartSequence.then(
      (previous) => _performStartSessionWatch(),
    );
    _watchRestartSequence = scheduledRestart.catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      // Keep later refresh requests runnable even if a prior restart fails.
    });
    return scheduledRestart;
  }

  Future<void> _performStartSessionWatch() async {
    final generation = ++_watchGeneration;
    final existingWatch = _watchSubscription;
    _watchSubscription = null;
    if (existingWatch != null) {
      await existingWatch.cancel();
    }

    if (_isStaleGeneration(generation)) {
      return;
    }

    final firstOutcomeSettled = Completer<void>();

    try {
      final service = _resolveService();
      final context = await _ensureSessionContext();

      if (_isStaleGeneration(generation)) {
        return;
      }

      final watchStream = service.watchSession(context.sessionId);
      _watchSubscription = watchStream.listen(
        (session) {
          if (_isStaleGeneration(generation)) {
            return;
          }

          _onSnapshot?.call(session);
          _persistSessionMutationForResolvedService()?.call(session);
          if (!firstOutcomeSettled.isCompleted) {
            firstOutcomeSettled.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_isStaleGeneration(generation)) {
            return;
          }

          _onWatchError?.call(error, stackTrace);
          if (!firstOutcomeSettled.isCompleted) {
            firstOutcomeSettled.complete();
          }
        },
      );

      await firstOutcomeSettled.future;
    } catch (error, stackTrace) {
      if (!_isStaleGeneration(generation)) {
        _onWatchError?.call(error, stackTrace);
      }
      if (!firstOutcomeSettled.isCompleted) {
        firstOutcomeSettled.complete();
      }
    }
  }

  Future<_RuntimeSessionContext> _ensureSessionContext() async {
    final existingContext = _currentSessionContext;
    if (existingContext != null) {
      return existingContext;
    }

    await _bootstrapIfNeeded();

    final context = _RuntimeSessionContext(
      sessionId: _currentSessionId!,
      identity: _currentBootstrapRequest!.desktopIdentity,
      attachedClientId: _attachedClientId,
    );
    _currentSessionContext = context;
    return context;
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
      final request = CommonCodeSessionBootstrapRequest(
        defaultSessionId: _defaultSessionId,
        hostId: _hostId,
        attachedClientId: _attachedClientId,
        desktopIdentity: Identity(id: _desktopIdentityId),
      );
      final bootstrappedSession = await _bootstrapLifecycle.bootstrap(
        request: request,
        port: bootstrapPort,
      );
      _currentSessionId = bootstrappedSession.id;
      _currentBootstrapRequest = request;
      _isBootstrapped = true;
      return;
    }

    final restoredSession = await _legacySnapshotStore.readLatestSession(
      desktopClientId: _attachedClientId,
    );
    if (restoredSession != null) {
      try {
        final restored = service.restoreSession(restoredSession);
        _persistSessionMutationForResolvedService()?.call(restored);
        _currentSessionId = restoredSession.id;
        _currentBootstrapRequest = CommonCodeSessionBootstrapRequest(
          defaultSessionId: _defaultSessionId,
          hostId: _hostId,
          attachedClientId: _attachedClientId,
          desktopIdentity: Identity(id: _desktopIdentityId),
        );
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
    final attachedSession = service.attachClient(
      sessionId: _defaultSessionId,
      client: Client(id: _attachedClientId),
    );
    _persistSessionMutationForResolvedService()?.call(attachedSession);
    _currentSessionId = _defaultSessionId;
    _currentBootstrapRequest = CommonCodeSessionBootstrapRequest(
      defaultSessionId: _defaultSessionId,
      hostId: _hostId,
      attachedClientId: _attachedClientId,
      desktopIdentity: Identity(id: _desktopIdentityId),
    );
    _isBootstrapped = true;
  }

  HostService _resolveService() {
    final existingService = _service;
    if (existingService != null) {
      return existingService;
    }

    final injectedService = _hostService;
    if (injectedService == null) {
      throw StateError(
        'HostDesktopSessionRuntime requires an injected HostService.',
      );
    }

    _resolvedBootstrapPort = _bootstrapPort;
    _resolvedPersistSessionMutation = _persistSessionMutation;
    return _service = injectedService;
  }

  void Function(Session session)? _persistSessionMutationForResolvedService() {
    _resolveService();
    return _resolvedPersistSessionMutation;
  }

  bool _isStaleGeneration(int generation) {
    return _isDisposed || generation != _watchGeneration;
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _watchGeneration += 1;

    final watchSubscription = _watchSubscription;
    _watchSubscription = null;
    if (watchSubscription != null) {
      await watchSubscription.cancel();
    }
  }
}
