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
import 'durable_local_host_service.dart';

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

  Future<void> submitTurn({required String submittedText});

  Future<void> dispose();
}

final class HostDesktopSessionRuntime implements DesktopSessionRuntime {
  HostDesktopSessionRuntime({
    HostService? hostService,
    SessionSnapshotStore? snapshotStore,
    HostService Function()? hostServiceFactory,
    DurableLocalHostDiagnosticsSink? diagnosticsSink,
    String defaultSessionId = desktopSessionRuntimeDefaultSessionId,
    String hostId = desktopSessionRuntimeHostId,
    String attachedClientId = desktopSessionRuntimeAttachedClientId,
  }) : _hostService = hostService,
       _legacySnapshotStore =
           snapshotStore ?? SharedPreferencesSessionSnapshotStore(),
       _hostServiceFactory =
           hostServiceFactory ??
           (() => DurableLocalHostService(
             legacySnapshotStore:
                 snapshotStore ?? SharedPreferencesSessionSnapshotStore(),
             diagnosticsSink: diagnosticsSink,
           )),
       _defaultSessionId = defaultSessionId,
       _hostId = hostId,
       _attachedClientId = attachedClientId;

  final HostService? _hostService;
  final SessionSnapshotStore _legacySnapshotStore;
  final HostService Function() _hostServiceFactory;
  final String _defaultSessionId;
  final String _hostId;
  final String _attachedClientId;

  void Function(Session session)? _onSnapshot;
  void Function(Object error, StackTrace stackTrace)? _onWatchError;
  HostService? _service;
  StreamSubscription<Session>? _watchSubscription;
  Future<void> _watchRestartSequence = Future<void>.value();
  bool _isBootstrapped = false;
  bool _isDisposed = false;
  String? _currentSessionId;
  _RuntimeSessionContext? _currentSessionContext;
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
  Future<void> submitTurn({required String submittedText}) async {
    final service = _service ??= _hostService ?? _hostServiceFactory();
    final context = await _ensureSessionContext();

    service.submitTurn(
      sessionId: context.sessionId,
      client: Client(id: context.attachedClientId),
      submittedText: submittedText,
    );
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
      final service = _service ??= _hostService ?? _hostServiceFactory();
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
      identity: const Identity(id: desktopSessionRuntimeIdentityId),
      attachedClientId: _attachedClientId,
    );
    _currentSessionContext = context;
    return context;
  }

  Future<void> _bootstrapIfNeeded() async {
    final service = _service ??= _hostService ?? _hostServiceFactory();
    if (_isBootstrapped) {
      return;
    }

    if (service case final CommonCodeSessionBootstrapPort bootstrapPort) {
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
