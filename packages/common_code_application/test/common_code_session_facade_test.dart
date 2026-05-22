import 'dart:async';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:test/test.dart';

void main() {
  group('CommonCodeSessionFacade', () {
    test('initialize emits loading then data from observed session', () async {
      final driver = _FakeCommonCodeSessionDriver();
      final facade = CommonCodeSessionFacade(
        driver: driver,
        attachedClientId: 'desktop-client',
      );

      final initializeFuture = facade.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(facade.state.status, CommonCodeSessionFacadeStatus.loading);
      expect(driver.ensureSessionCalls, 1);

      driver.emitSession(_bootstrapSession());
      await initializeFuture;

      expect(facade.state.status, CommonCodeSessionFacadeStatus.data);
      expect(facade.state.snapshot!.session.id, 'desktop-session');
      expect(facade.state.snapshot!.attachedClientId, 'desktop-client');

      await facade.dispose();
    });

    test('initialize emits empty when no session binding exists', () async {
      final driver = _FakeCommonCodeSessionDriver(
        binding: const CommonCodeSessionBinding.empty(),
      );
      final facade = CommonCodeSessionFacade(
        driver: driver,
        attachedClientId: 'desktop-client',
      );

      await facade.initialize();

      expect(facade.state.status, CommonCodeSessionFacadeStatus.empty);

      await facade.dispose();
    });

    test('refresh cancels the prior watch before replacement watch', () async {
      final driver = _FakeCommonCodeSessionDriver();
      final facade = CommonCodeSessionFacade(
        driver: driver,
        attachedClientId: 'desktop-client',
      );

      final initializeFuture = facade.initialize();
      await Future<void>.delayed(Duration.zero);
      driver.emitSession(_bootstrapSession());
      await initializeFuture;

      final refreshFuture = facade.refresh();
      await Future<void>.delayed(Duration.zero);
      driver.emitSession(_bootstrapSession());
      await refreshFuture;

      expect(driver.watchStarts, 2);
      expect(driver.watchCancels, 1);

      await facade.dispose();
    });

    test('submit keeps submission state until completion', () async {
      final driver = _FakeCommonCodeSessionDriver();
      final facade = CommonCodeSessionFacade(
        driver: driver,
        attachedClientId: 'desktop-client',
      );

      final initializeFuture = facade.initialize();
      await Future<void>.delayed(Duration.zero);
      driver.emitSession(_bootstrapSession());
      await initializeFuture;

      final submitFuture = facade.submitTurn(submittedText: 'queued turn');
      await Future<void>.delayed(Duration.zero);

      expect(facade.state.isSubmitting, isTrue);
      expect(driver.submittedTexts, ['queued turn']);

      driver.completeSubmit();
      await submitFuture;

      expect(facade.state.isSubmitting, isFalse);
      expect(facade.state.status, CommonCodeSessionFacadeStatus.data);

      await facade.dispose();
    });

    test('submit failure emits renderable error state', () async {
      final driver = _FakeCommonCodeSessionDriver()
        ..submitError = StateError('submit failed');
      final facade = CommonCodeSessionFacade(
        driver: driver,
        attachedClientId: 'desktop-client',
      );

      final initializeFuture = facade.initialize();
      await Future<void>.delayed(Duration.zero);
      driver.emitSession(_bootstrapSession());
      await initializeFuture;

      await expectLater(
        facade.submitTurn(submittedText: 'bad turn'),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(facade.state.isSubmitting, isFalse);
      expect(facade.state.status, CommonCodeSessionFacadeStatus.error);
      expect(facade.state.message, contains('submit failed'));

      await facade.dispose();
    });
  });
}

Session _bootstrapSession() {
  return Session(
    id: 'desktop-session',
    activeHost: const Host(id: 'desktop-host'),
  ).attachClient(const Client(id: 'desktop-client'));
}

final class _FakeCommonCodeSessionDriver implements CommonCodeSessionDriver {
  _FakeCommonCodeSessionDriver({
    this.binding = const CommonCodeSessionBinding.attached(
      sessionId: 'desktop-session',
    ),
  });

  final CommonCodeSessionBinding binding;
  final List<String> submittedTexts = <String>[];
  final List<StreamController<Session>> _controllers =
      <StreamController<Session>>[];

  int ensureSessionCalls = 0;
  int watchStarts = 0;
  int watchCancels = 0;
  Completer<void>? _pendingSubmit;
  Object? submitError;
  Session? _pendingSession;

  @override
  Future<CommonCodeSessionBinding> ensureSession() async {
    ensureSessionCalls += 1;
    return binding;
  }

  void emitSession(Session session) {
    if (_controllers.isEmpty) {
      _pendingSession = session;
      return;
    }

    _controllers.last.add(session);
  }

  @override
  Future<void> submitTurn({
    required String sessionId,
    required String attachedClientId,
    required String submittedText,
  }) {
    submittedTexts.add(submittedText);
    if (submitError case final Object error) {
      return Future<void>.error(error);
    }

    final completer = Completer<void>();
    _pendingSubmit = completer;
    return completer.future;
  }

  void completeSubmit() {
    _pendingSubmit?.complete();
    _pendingSubmit = null;
  }

  @override
  Stream<Session> watchSession(String sessionId) {
    watchStarts += 1;
    late final StreamController<Session> controller;
    controller = StreamController<Session>(
      sync: true,
      onListen: () {
        if (_pendingSession case final Session pendingSession) {
          controller.add(pendingSession);
          _pendingSession = null;
        }
      },
      onCancel: () {
        watchCancels += 1;
      },
    );
    _controllers.add(controller);
    return controller.stream;
  }
}
