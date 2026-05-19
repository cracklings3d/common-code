import 'dart:async';

import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:host_core/host_core.dart';

import 'desktop_session_snapshot_store.dart';

final class DesktopSessionSnapshot {
  const DesktopSessionSnapshot({
    required this.session,
    required this.attachedClientId,
  });

  final Session session;
  final String attachedClientId;
}

enum DesktopSessionControllerStatus { loading, empty, data, error }

final class DesktopSessionControllerState {
  const DesktopSessionControllerState._({
    required this.status,
    this.snapshot,
    this.message,
    required this.isSubmitting,
  });

  const DesktopSessionControllerState.loading({bool isSubmitting = false})
    : this._(
        status: DesktopSessionControllerStatus.loading,
        isSubmitting: isSubmitting,
      );

  const DesktopSessionControllerState.empty({bool isSubmitting = false})
    : this._(
        status: DesktopSessionControllerStatus.empty,
        isSubmitting: isSubmitting,
      );

  const DesktopSessionControllerState.data(
    DesktopSessionSnapshot this.snapshot, {
    bool isSubmitting = false,
  }) : status = DesktopSessionControllerStatus.data,
       message = null,
       isSubmitting = isSubmitting;

  const DesktopSessionControllerState.error(
    String this.message, {
    bool isSubmitting = false,
  }) : status = DesktopSessionControllerStatus.error,
       snapshot = null,
       isSubmitting = isSubmitting;

  final DesktopSessionControllerStatus status;
  final DesktopSessionSnapshot? snapshot;
  final String? message;
  final bool isSubmitting;

  DesktopSessionControllerState copyWithSubmitting(bool isSubmitting) {
    return switch (status) {
      DesktopSessionControllerStatus.loading =>
        DesktopSessionControllerState.loading(isSubmitting: isSubmitting),
      DesktopSessionControllerStatus.empty =>
        DesktopSessionControllerState.empty(isSubmitting: isSubmitting),
      DesktopSessionControllerStatus.data => DesktopSessionControllerState.data(
        snapshot!,
        isSubmitting: isSubmitting,
      ),
      DesktopSessionControllerStatus.error =>
        DesktopSessionControllerState.error(
          message!,
          isSubmitting: isSubmitting,
        ),
    };
  }
}

class DesktopSessionController extends ChangeNotifier {
  DesktopSessionController({
    HostService? hostService,
    DesktopSessionSnapshotStore? snapshotStore,
  }) : _hostService = hostService,
       _snapshotStore =
           snapshotStore ?? SharedPreferencesDesktopSessionSnapshotStore();

  static const defaultSessionId = 'desktop-session';
  static const hostId = 'desktop-host';
  static const attachedClientId = 'desktop-client';

  final HostService? _hostService;
  final DesktopSessionSnapshotStore _snapshotStore;

  DesktopSessionControllerState _state =
      const DesktopSessionControllerState.loading();
  HostService? _service;
  StreamSubscription<Session>? _watchSubscription;
  Future<void> _watchRestartSequence = Future<void>.value();
  bool _isBootstrapped = false;
  bool _isDisposed = false;
  String? _currentSessionId;

  DesktopSessionControllerState get state => _state;

  Future<void> initialize() => _startSessionWatch();

  Future<void> refresh() => _startSessionWatch();

  @protected
  @visibleForTesting
  void emitState(DesktopSessionControllerState state) => _emitState(state);

  Future<void> submitTurn({required String submittedText}) async {
    _emitState(_state.copyWithSubmitting(true));

    try {
      final service = _service ??= _hostService ?? createInMemoryHostService();
      await _bootstrapIfNeeded();

      service.submitTurn(
        sessionId: _currentSessionId!,
        client: const Client(id: attachedClientId),
        submittedText: submittedText,
      );
    } catch (error) {
      _emitState(
        DesktopSessionControllerState.error(
          error.toString(),
          isSubmitting: false,
        ),
      );
      rethrow;
    }

    _emitState(_state.copyWithSubmitting(false));
  }

  Future<void> _startSessionWatch() {
    final scheduledRestart = _watchRestartSequence.then(
      (_) => _performStartSessionWatch(),
    );
    _watchRestartSequence = scheduledRestart.catchError((
      Object _,
      StackTrace __,
    ) {
      // Keep later refresh requests runnable even if a prior restart fails.
    });
    return scheduledRestart;
  }

  Future<void> _performStartSessionWatch() async {
    final existingWatch = _watchSubscription;
    _watchSubscription = null;
    if (existingWatch != null) {
      await existingWatch.cancel();
    }

    _emitState(const DesktopSessionControllerState.loading());
    final firstStateSettled = Completer<void>();

    try {
      final service = _service ??= _hostService ?? createInMemoryHostService();
      await _bootstrapIfNeeded();

      final watchStream = service.watchSession(_currentSessionId!);
      _watchSubscription = watchStream.listen(
        (session) {
          _emitState(
            DesktopSessionControllerState.data(
              DesktopSessionSnapshot(
                session: session,
                attachedClientId: attachedClientId,
              ),
              isSubmitting: _state.isSubmitting,
            ),
          );
          if (!firstStateSettled.isCompleted) {
            firstStateSettled.complete();
          }
          unawaited(_persistSnapshot(session));
        },
        onError: (Object error, StackTrace stackTrace) {
          _emitState(
            DesktopSessionControllerState.error(
              error.toString(),
              isSubmitting: false,
            ),
          );
          if (!firstStateSettled.isCompleted) {
            firstStateSettled.complete();
          }
        },
      );
      await firstStateSettled.future;
    } catch (error) {
      _emitState(
        DesktopSessionControllerState.error(
          error.toString(),
          isSubmitting: false,
        ),
      );
      if (!firstStateSettled.isCompleted) {
        firstStateSettled.complete();
      }
    }
  }

  Future<void> _bootstrapIfNeeded() async {
    final service = _service ??= _hostService ?? createInMemoryHostService();
    if (_isBootstrapped) {
      return;
    }

    final restoredSession = await _snapshotStore.readLatestSession(
      desktopClientId: attachedClientId,
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
      sessionId: defaultSessionId,
      activeHost: const Host(id: hostId),
    );
    service.attachClient(
      sessionId: defaultSessionId,
      client: const Client(id: attachedClientId),
    );
    _currentSessionId = defaultSessionId;
    _isBootstrapped = true;
  }

  Future<void> _persistSnapshot(Session session) async {
    try {
      await _snapshotStore.writeLatestSession(session);
    } catch (_) {
      // Persisting the mirror snapshot must not break the live host-backed UI.
    }
  }

  void _emitState(DesktopSessionControllerState state) {
    if (_isDisposed) {
      return;
    }

    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    final watchSubscription = _watchSubscription;
    _watchSubscription = null;
    if (watchSubscription != null) {
      unawaited(watchSubscription.cancel());
    }
    super.dispose();
  }
}
