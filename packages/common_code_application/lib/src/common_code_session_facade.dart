import 'dart:async';

import 'package:common_code_domain/common_code_domain.dart';

final class CommonCodeSessionBinding {
  const CommonCodeSessionBinding.attached({required this.sessionId});

  const CommonCodeSessionBinding.empty() : sessionId = null;

  final String? sessionId;

  bool get hasSession => sessionId != null;
}

final class CommonCodeSessionSnapshot {
  const CommonCodeSessionSnapshot({
    required this.session,
    required this.attachedClientId,
  });

  final Session session;
  final String attachedClientId;
}

enum CommonCodeSessionFacadeStatus { loading, empty, data, error }

final class CommonCodeSessionFacadeState {
  const CommonCodeSessionFacadeState._({
    required this.status,
    this.snapshot,
    this.message,
    required this.isSubmitting,
  });

  const CommonCodeSessionFacadeState.loading({bool isSubmitting = false})
    : this._(
        status: CommonCodeSessionFacadeStatus.loading,
        isSubmitting: isSubmitting,
      );

  const CommonCodeSessionFacadeState.empty({bool isSubmitting = false})
    : this._(
        status: CommonCodeSessionFacadeStatus.empty,
        isSubmitting: isSubmitting,
      );

  const CommonCodeSessionFacadeState.data(
    CommonCodeSessionSnapshot this.snapshot, {
    this.isSubmitting = false,
  }) : status = CommonCodeSessionFacadeStatus.data,
       message = null;

  const CommonCodeSessionFacadeState.error(
    String this.message, {
    this.isSubmitting = false,
  }) : status = CommonCodeSessionFacadeStatus.error,
       snapshot = null;

  final CommonCodeSessionFacadeStatus status;
  final CommonCodeSessionSnapshot? snapshot;
  final String? message;
  final bool isSubmitting;

  CommonCodeSessionFacadeState copyWithSubmitting(bool isSubmitting) {
    return switch (status) {
      CommonCodeSessionFacadeStatus.loading =>
        CommonCodeSessionFacadeState.loading(isSubmitting: isSubmitting),
      CommonCodeSessionFacadeStatus.empty => CommonCodeSessionFacadeState.empty(
        isSubmitting: isSubmitting,
      ),
      CommonCodeSessionFacadeStatus.data => CommonCodeSessionFacadeState.data(
        snapshot!,
        isSubmitting: isSubmitting,
      ),
      CommonCodeSessionFacadeStatus.error => CommonCodeSessionFacadeState.error(
        message!,
        isSubmitting: isSubmitting,
      ),
    };
  }
}

abstract interface class CommonCodeSessionDriver {
  Future<CommonCodeSessionBinding> ensureSession();

  Stream<Session> watchSession(String sessionId);

  FutureOr<void> submitTurn({
    required String sessionId,
    required String attachedClientId,
    required String submittedText,
  });
}

final class CommonCodeSessionFacade {
  CommonCodeSessionFacade({
    required CommonCodeSessionDriver driver,
    required String attachedClientId,
  }) : _driver = driver,
       _attachedClientId = attachedClientId;

  final CommonCodeSessionDriver _driver;
  final String _attachedClientId;
  final StreamController<CommonCodeSessionFacadeState> _states =
      StreamController<CommonCodeSessionFacadeState>.broadcast(sync: true);

  CommonCodeSessionFacadeState _state =
      const CommonCodeSessionFacadeState.loading();
  StreamSubscription<Session>? _watchSubscription;
  Future<void> _watchRestartSequence = Future<void>.value();
  bool _isDisposed = false;
  String? _currentSessionId;
  int _watchGeneration = 0;

  Stream<CommonCodeSessionFacadeState> get states => _states.stream;

  CommonCodeSessionFacadeState get state => _state;

  Future<void> initialize() async {
    _emitState(const CommonCodeSessionFacadeState.loading());
    await _startSessionWatch();
  }

  Future<void> refresh() async {
    _emitState(const CommonCodeSessionFacadeState.loading());
    await _startSessionWatch();
  }

  Future<void> submitTurn({required String submittedText}) async {
    _emitState(_state.copyWithSubmitting(true));

    try {
      final sessionId = await _ensureSessionId();
      if (sessionId == null) {
        throw StateError('No session available.');
      }

      await Future.sync(
        () => _driver.submitTurn(
          sessionId: sessionId,
          attachedClientId: _attachedClientId,
          submittedText: submittedText,
        ),
      );
    } catch (error) {
      _emitState(
        CommonCodeSessionFacadeState.error(
          error.toString(),
          isSubmitting: false,
        ),
      );
      rethrow;
    }

    _emitState(_state.copyWithSubmitting(false));
  }

  Future<void> dispose() async {
    _isDisposed = true;
    _watchGeneration += 1;

    final watchSubscription = _watchSubscription;
    _watchSubscription = null;
    if (watchSubscription != null) {
      await watchSubscription.cancel();
    }

    await _states.close();
  }

  Future<String?> _ensureSessionId() async {
    if (_currentSessionId != null) {
      return _currentSessionId;
    }

    final binding = await _driver.ensureSession();
    if (!binding.hasSession) {
      return null;
    }

    _currentSessionId = binding.sessionId;
    return _currentSessionId;
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
      final sessionId = await _ensureSessionId();
      if (_isStaleGeneration(generation)) {
        return;
      }

      if (sessionId == null) {
        _emitState(
          CommonCodeSessionFacadeState.empty(isSubmitting: _state.isSubmitting),
        );
        firstOutcomeSettled.complete();
        await firstOutcomeSettled.future;
        return;
      }

      final watchStream = _driver.watchSession(sessionId);
      _watchSubscription = watchStream.listen(
        (session) {
          if (_isStaleGeneration(generation)) {
            return;
          }

          _emitState(
            CommonCodeSessionFacadeState.data(
              CommonCodeSessionSnapshot(
                session: session,
                attachedClientId: _attachedClientId,
              ),
              isSubmitting: _state.isSubmitting,
            ),
          );
          if (!firstOutcomeSettled.isCompleted) {
            firstOutcomeSettled.complete();
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_isStaleGeneration(generation)) {
            return;
          }

          _emitState(
            CommonCodeSessionFacadeState.error(
              error.toString(),
              isSubmitting: false,
            ),
          );
          if (!firstOutcomeSettled.isCompleted) {
            firstOutcomeSettled.complete();
          }
        },
      );

      await firstOutcomeSettled.future;
    } catch (error) {
      if (!_isStaleGeneration(generation)) {
        _emitState(
          CommonCodeSessionFacadeState.error(
            error.toString(),
            isSubmitting: false,
          ),
        );
      }
      if (!firstOutcomeSettled.isCompleted) {
        firstOutcomeSettled.complete();
      }
    }
  }

  bool _isStaleGeneration(int generation) {
    return _isDisposed || generation != _watchGeneration;
  }

  void _emitState(CommonCodeSessionFacadeState state) {
    if (_isDisposed) {
      return;
    }

    _state = state;
    _states.add(state);
  }
}
