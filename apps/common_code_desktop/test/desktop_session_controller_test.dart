import 'dart:async';

import 'package:common_code_desktop/src/desktop_session_controller.dart';
import 'package:common_code_desktop/src/desktop_session_runtime.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopSessionController', () {
    test(
      'initialize emits loading state before runtime work settles',
      () async {
        final runtime = _FakeDesktopSessionRuntime();
        final controller = DesktopSessionController(runtime: runtime);

        controller.emitState(DesktopSessionControllerState.data(_snapshot));

        final initializeFuture = controller.initialize();

        expect(controller.state.status, DesktopSessionControllerStatus.loading);

        runtime.emitSnapshot(_bootstrapSession());
        await initializeFuture;

        expect(controller.state.status, DesktopSessionControllerStatus.data);
      },
    );

    test('refresh emits loading state before runtime work settles', () async {
      final runtime = _FakeDesktopSessionRuntime();
      final controller = DesktopSessionController(runtime: runtime);

      controller.emitState(DesktopSessionControllerState.data(_snapshot));

      final refreshFuture = controller.refresh();

      expect(controller.state.status, DesktopSessionControllerStatus.loading);

      runtime.emitSnapshot(_bootstrapSession());
      await refreshFuture;

      expect(controller.state.status, DesktopSessionControllerStatus.data);
    });

    test('runtime snapshots map to data state', () {
      final runtime = _FakeDesktopSessionRuntime();
      final controller = DesktopSessionController(runtime: runtime);

      runtime.emitSnapshot(_bootstrapSession());

      expect(controller.state.status, DesktopSessionControllerStatus.data);
      expect(controller.state.snapshot, isNotNull);
      expect(controller.state.snapshot!.session.id, 'desktop-session');
    });

    test('runtime watch errors map to renderable error state', () {
      final runtime = _FakeDesktopSessionRuntime();
      final controller = DesktopSessionController(runtime: runtime);

      runtime.emitWatchError(StateError('watch boom'));

      expect(controller.state.status, DesktopSessionControllerStatus.error);
      expect(controller.state.message, contains('watch boom'));
    });

    test('submit toggles submission state and clears it on success', () async {
      final runtime = _FakeDesktopSessionRuntime();
      final controller = DesktopSessionController(runtime: runtime);

      runtime.emitSnapshot(_bootstrapSession());

      final submitFuture = controller.submitTurn(submittedText: 'queued turn');

      expect(controller.state.isSubmitting, isTrue);
      expect(runtime.submittedTexts, ['queued turn']);

      runtime.completeSubmit();
      await submitFuture;

      expect(controller.state.isSubmitting, isFalse);
      expect(controller.state.status, DesktopSessionControllerStatus.data);
    });

    test(
      'submit failure surfaces as renderable error state and clears flag',
      () async {
        final runtime = _FakeDesktopSessionRuntime()
          ..submitError = StateError('submit failed');
        final controller = DesktopSessionController(runtime: runtime);

        runtime.emitSnapshot(_bootstrapSession());

        await expectLater(
          controller.submitTurn(submittedText: 'bad turn'),
          throwsA(isA<StateError>()),
        );

        expect(controller.state.isSubmitting, isFalse);
        expect(controller.state.status, DesktopSessionControllerStatus.error);
        expect(controller.state.message, contains('submit failed'));
      },
    );

    test('controller ignores late runtime events after disposal', () async {
      final runtime = _FakeDesktopSessionRuntime();
      final controller = DesktopSessionController(runtime: runtime);

      runtime.emitSnapshot(_bootstrapSession());
      controller.dispose();

      runtime.emitSnapshot(
        _bootstrapSession().startTurn(
          turnId: 'turn-1',
          client: const Client(id: 'desktop-client'),
          submittedText: 'late event',
        ),
      );
      runtime.emitWatchError(StateError('late watch boom'));

      expect(controller.state.status, DesktopSessionControllerStatus.data);
      expect(controller.state.snapshot!.session.activeTurn, isNull);
    });
  });
}

final _snapshot = DesktopSessionSnapshot(
  session: Session(
    id: 'desktop-session',
    activeHost: const Host(id: 'desktop-host'),
    clients: const [Client(id: 'desktop-client')],
  ),
  attachedClientId: 'desktop-client',
);

Session _bootstrapSession() {
  return Session(
    id: 'desktop-session',
    activeHost: const Host(id: 'desktop-host'),
  ).attachClient(const Client(id: 'desktop-client'));
}

final class _FakeDesktopSessionRuntime implements DesktopSessionRuntime {
  void Function(Session session)? _onSnapshot;
  void Function(Object error, StackTrace stackTrace)? _onWatchError;

  final List<String> submittedTexts = <String>[];
  Completer<void>? _pendingInitialize;
  Completer<void>? _pendingRefresh;
  Completer<void>? _pendingSubmit;
  Object? submitError;

  @override
  void bind({
    required void Function(Session session) onSnapshot,
    required void Function(Object error, StackTrace stackTrace) onWatchError,
  }) {
    _onSnapshot = onSnapshot;
    _onWatchError = onWatchError;
  }

  @override
  Future<void> initialize() {
    final completer = Completer<void>();
    _pendingInitialize = completer;
    return completer.future;
  }

  @override
  Future<void> refresh() {
    final completer = Completer<void>();
    _pendingRefresh = completer;
    return completer.future;
  }

  @override
  Future<void> submitTurn({required String submittedText}) {
    submittedTexts.add(submittedText);
    if (submitError case final Object error) {
      return Future<void>.error(error);
    }

    final completer = Completer<void>();
    _pendingSubmit = completer;
    return completer.future;
  }

  void emitSnapshot(Session session) {
    _onSnapshot?.call(session);
    _pendingInitialize?.complete();
    _pendingInitialize = null;
    _pendingRefresh?.complete();
    _pendingRefresh = null;
  }

  void emitWatchError(Object error) {
    _onWatchError?.call(error, StackTrace.current);
    _pendingInitialize?.complete();
    _pendingInitialize = null;
    _pendingRefresh?.complete();
    _pendingRefresh = null;
  }

  void completeSubmit() {
    _pendingSubmit?.complete();
    _pendingSubmit = null;
  }

  @override
  Future<void> dispose() async {
    _pendingInitialize?.complete();
    _pendingRefresh?.complete();
    _pendingSubmit?.complete();
  }
}
