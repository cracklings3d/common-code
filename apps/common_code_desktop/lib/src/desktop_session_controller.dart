import 'dart:async';

import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:host_core/host_core.dart';

import 'desktop_session_runtime.dart';
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
  static const Object _unset = Object();

  const DesktopSessionControllerState._({
    required this.status,
    this.snapshot,
    this.message,
    required this.isSubmitting,
    required this.isAcknowledgingNotification,
    this.acknowledgementErrorMessage,
  });

  const DesktopSessionControllerState.loading({bool isSubmitting = false})
    : this._(
        status: DesktopSessionControllerStatus.loading,
        isSubmitting: isSubmitting,
        isAcknowledgingNotification: false,
      );

  const DesktopSessionControllerState.empty({bool isSubmitting = false})
    : this._(
        status: DesktopSessionControllerStatus.empty,
        isSubmitting: isSubmitting,
        isAcknowledgingNotification: false,
      );

  const DesktopSessionControllerState.data(
    DesktopSessionSnapshot this.snapshot, {
    this.isSubmitting = false,
    this.isAcknowledgingNotification = false,
    this.acknowledgementErrorMessage,
  }) : status = DesktopSessionControllerStatus.data,
       message = null;

  const DesktopSessionControllerState.error(
    String this.message, {
    this.isSubmitting = false,
    this.isAcknowledgingNotification = false,
  }) : status = DesktopSessionControllerStatus.error,
       acknowledgementErrorMessage = null,
       snapshot = null;

  final DesktopSessionControllerStatus status;
  final DesktopSessionSnapshot? snapshot;
  final String? message;
  final bool isSubmitting;
  final bool isAcknowledgingNotification;
  final String? acknowledgementErrorMessage;

  DesktopSessionControllerState copyWithSubmitting(bool isSubmitting) {
    return copyWith(isSubmitting: isSubmitting);
  }

  DesktopSessionControllerState copyWith({
    bool? isSubmitting,
    bool? isAcknowledgingNotification,
    Object? acknowledgementErrorMessage = _unset,
  }) {
    return switch (status) {
      DesktopSessionControllerStatus.loading =>
        DesktopSessionControllerState.loading(
          isSubmitting: isSubmitting ?? this.isSubmitting,
        ),
      DesktopSessionControllerStatus.empty =>
        DesktopSessionControllerState.empty(
          isSubmitting: isSubmitting ?? this.isSubmitting,
        ),
      DesktopSessionControllerStatus.data => DesktopSessionControllerState.data(
        snapshot!,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        isAcknowledgingNotification:
            isAcknowledgingNotification ?? this.isAcknowledgingNotification,
        acknowledgementErrorMessage:
            identical(acknowledgementErrorMessage, _unset)
            ? this.acknowledgementErrorMessage
            : acknowledgementErrorMessage as String?,
      ),
      DesktopSessionControllerStatus.error =>
        DesktopSessionControllerState.error(
          message!,
          isSubmitting: isSubmitting ?? this.isSubmitting,
          isAcknowledgingNotification:
              isAcknowledgingNotification ?? this.isAcknowledgingNotification,
        ),
    };
  }
}

class DesktopSessionController extends ChangeNotifier {
  DesktopSessionController({
    DesktopSessionRuntime? runtime,
    HostService? hostService,
    DesktopSessionSnapshotStore? snapshotStore,
  }) : _runtime =
           runtime ??
           HostDesktopSessionRuntime(
             hostService: hostService,
             snapshotStore: snapshotStore,
           ) {
    _runtime.bind(
      onSnapshot: _handleRuntimeSnapshot,
      onWatchError: _handleRuntimeWatchError,
    );
  }

  static const attachedClientId = desktopSessionRuntimeAttachedClientId;

  final DesktopSessionRuntime _runtime;

  DesktopSessionControllerState _state =
      const DesktopSessionControllerState.loading();
  bool _isDisposed = false;

  DesktopSessionControllerState get state => _state;

  Future<void> initialize() async {
    _emitState(const DesktopSessionControllerState.loading());
    await _runtime.initialize();
  }

  Future<void> refresh() async {
    _emitState(const DesktopSessionControllerState.loading());
    await _runtime.refresh();
  }

  Future<void> acknowledgeNotification({required String notificationId}) async {
    _emitState(
      _state.copyWith(
        isAcknowledgingNotification: true,
        acknowledgementErrorMessage: null,
      ),
    );

    try {
      await _runtime.acknowledgeNotification(notificationId: notificationId);
    } catch (error) {
      _emitState(
        _state.copyWith(
          isAcknowledgingNotification: false,
          acknowledgementErrorMessage: error.toString(),
        ),
      );
      rethrow;
    }

    _emitState(
      _state.copyWith(
        isAcknowledgingNotification: false,
        acknowledgementErrorMessage: null,
      ),
    );
  }

  @protected
  @visibleForTesting
  void emitState(DesktopSessionControllerState state) => _emitState(state);

  Future<void> submitTurn({required String submittedText}) async {
    _emitState(_state.copyWithSubmitting(true));

    try {
      await _runtime.submitTurn(submittedText: submittedText);
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

  void _handleRuntimeSnapshot(Session session) {
    _emitState(
      DesktopSessionControllerState.data(
        DesktopSessionSnapshot(
          session: session,
          attachedClientId: attachedClientId,
        ),
        isSubmitting: _state.isSubmitting,
        isAcknowledgingNotification: _state.isAcknowledgingNotification,
      ),
    );
  }

  void _handleRuntimeWatchError(Object error, StackTrace stackTrace) {
    _emitState(
      DesktopSessionControllerState.error(
        error.toString(),
        isSubmitting: false,
      ),
    );
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
    unawaited(_runtime.dispose());
    super.dispose();
  }
}
