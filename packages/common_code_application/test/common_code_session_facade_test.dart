import 'dart:async';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_application/src/common_code_session_bootstrap.dart';
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

    test('acknowledgement delegates to driver for current session', () async {
      final driver = _FakeCommonCodeSessionDriver();
      final facade = CommonCodeSessionFacade(
        driver: driver,
        attachedClientId: 'desktop-client',
      );

      final initializeFuture = facade.initialize();
      await Future<void>.delayed(Duration.zero);
      driver.emitSession(_bootstrapSessionWithNotification());
      await initializeFuture;

      final notificationId =
          facade.state.snapshot!.session.notifications.single.id;
      await facade.acknowledgeNotification(notificationId: notificationId);

      expect(driver.acknowledgedNotificationIds, [notificationId]);

      await facade.dispose();
    });
  });

  group('CommonCodeSessionBootstrapOrchestrator', () {
    test('returns current session when port is already bootstrapped', () async {
      final existingSession = _bootstrapSession();
      final port = _FakeBootstrapPort(
        isBootstrapped: true,
        bootstrappedSession: existingSession,
      );

      final session = await const CommonCodeSessionBootstrapOrchestrator()
          .bootstrap(
            request: const CommonCodeSessionBootstrapRequest(
              defaultSessionId: 'desktop-session',
              hostId: 'desktop-host',
              attachedClientId: 'desktop-client',
            ),
            isBootstrapped: port.isBootstrapped,
            readBootstrappedSession: port.readBootstrappedSession,
            loadDurableSessionCandidate: port.loadDurableSessionCandidate,
            restoreDurableSession: port.restoreDurableSession,
            loadLegacySeedSession: port.loadLegacySeedSession,
            restoreLegacySeededSession: port.restoreLegacySeededSession,
            createFreshSession: port.createFreshSession,
          );

      expect(session, same(existingSession));
      expect(port.loadDurableCalls, 0);
      expect(port.loadLegacyCalls, 0);
      expect(port.createFreshCalls, 0);
    });

    test(
      'durable missing falls through to successful legacy seed restore',
      () async {
        final legacySession = _bootstrapSession();
        final port = _FakeBootstrapPort(
          durableResult: const CommonCodeDurableBootstrapLoadResult.missing(),
          legacyResult: CommonCodeLegacySeedLoadResult.available(legacySession),
          restoredLegacySession: legacySession,
        );

        final session = await const CommonCodeSessionBootstrapOrchestrator()
            .bootstrap(
              request: const CommonCodeSessionBootstrapRequest(
                defaultSessionId: 'desktop-session',
                hostId: 'desktop-host',
                attachedClientId: 'desktop-client',
              ),
              isBootstrapped: port.isBootstrapped,
              readBootstrappedSession: port.readBootstrappedSession,
              loadDurableSessionCandidate: port.loadDurableSessionCandidate,
              restoreDurableSession: port.restoreDurableSession,
              loadLegacySeedSession: port.loadLegacySeedSession,
              restoreLegacySeededSession: port.restoreLegacySeededSession,
              createFreshSession: port.createFreshSession,
            );

        expect(session, same(legacySession));
        expect(port.loadDurableCalls, 1);
        expect(port.loadLegacyCalls, 1);
        expect(port.restoreLegacyCalls, 1);
        expect(port.createFreshCalls, 0);
      },
    );

    test(
      'durable read failure still consults legacy seed before fresh fallback',
      () async {
        final freshSession = _bootstrapSession();
        final port = _FakeBootstrapPort(
          durableResult:
              const CommonCodeDurableBootstrapLoadResult.readFailed(),
          legacyResult: const CommonCodeLegacySeedLoadResult.failed(),
          freshSession: freshSession,
        );

        final session = await const CommonCodeSessionBootstrapOrchestrator()
            .bootstrap(
              request: const CommonCodeSessionBootstrapRequest(
                defaultSessionId: 'desktop-session',
                hostId: 'desktop-host',
                attachedClientId: 'desktop-client',
              ),
              isBootstrapped: port.isBootstrapped,
              readBootstrappedSession: port.readBootstrappedSession,
              loadDurableSessionCandidate: port.loadDurableSessionCandidate,
              restoreDurableSession: port.restoreDurableSession,
              loadLegacySeedSession: port.loadLegacySeedSession,
              restoreLegacySeededSession: port.restoreLegacySeededSession,
              createFreshSession: port.createFreshSession,
            );

        expect(session, same(freshSession));
        expect(port.loadDurableCalls, 1);
        expect(port.loadLegacyCalls, 1);
        expect(port.createFreshCalls, 1);
      },
    );

    test('legacy restore failure falls back to fresh bootstrap', () async {
      final freshSession = _bootstrapSession();
      final port = _FakeBootstrapPort(
        durableResult: const CommonCodeDurableBootstrapLoadResult.invalid(),
        legacyResult: CommonCodeLegacySeedLoadResult.available(
          _bootstrapSession(),
        ),
        restoreLegacyError: StateError('legacy restore failed'),
        freshSession: freshSession,
      );

      final session = await const CommonCodeSessionBootstrapOrchestrator()
          .bootstrap(
            request: const CommonCodeSessionBootstrapRequest(
              defaultSessionId: 'desktop-session',
              hostId: 'desktop-host',
              attachedClientId: 'desktop-client',
            ),
            isBootstrapped: port.isBootstrapped,
            readBootstrappedSession: port.readBootstrappedSession,
            loadDurableSessionCandidate: port.loadDurableSessionCandidate,
            restoreDurableSession: port.restoreDurableSession,
            loadLegacySeedSession: port.loadLegacySeedSession,
            restoreLegacySeededSession: port.restoreLegacySeededSession,
            createFreshSession: port.createFreshSession,
          );

      expect(session, same(freshSession));
      expect(port.restoreLegacyCalls, 1);
      expect(port.createFreshCalls, 1);
    });

    test(
      'durable restore failure falls back directly to fresh bootstrap',
      () async {
        final durableSession = _bootstrapSession();
        final freshSession = _bootstrapSessionWithNotification();
        final port = _FakeBootstrapPort(
          durableResult: CommonCodeDurableBootstrapLoadResult.available(
            durableSession,
          ),
          restoreDurableError: StateError('durable restore failed'),
          freshSession: freshSession,
        );

        final session = await const CommonCodeSessionBootstrapOrchestrator()
            .bootstrap(
              request: const CommonCodeSessionBootstrapRequest(
                defaultSessionId: 'desktop-session',
                hostId: 'desktop-host',
                attachedClientId: 'desktop-client',
              ),
              isBootstrapped: port.isBootstrapped,
              readBootstrappedSession: port.readBootstrappedSession,
              loadDurableSessionCandidate: port.loadDurableSessionCandidate,
              restoreDurableSession: port.restoreDurableSession,
              loadLegacySeedSession: port.loadLegacySeedSession,
              restoreLegacySeededSession: port.restoreLegacySeededSession,
              createFreshSession: port.createFreshSession,
            );

        expect(session, same(freshSession));
        expect(port.restoreDurableCalls, 1);
        expect(port.loadLegacyCalls, 0);
        expect(port.createFreshCalls, 1);
      },
    );
  });
}

Session _bootstrapSession() {
  return Session(
    id: 'desktop-session',
    activeHost: const Host(id: 'desktop-host'),
  ).attachClient(const Client(id: 'desktop-client'));
}

Session _bootstrapSessionWithNotification() {
  final session = _bootstrapSession()
      .startTurn(
        turnId: 'turn-1',
        client: const Client(id: 'desktop-client'),
        submittedText: 'queued turn',
      )
      .advanceActiveTurnToRunning();

  return Session(
    id: session.id,
    activeHost: session.activeHost,
    clients: session.clients,
    promptThread: session.promptThread,
    notifications: [
      SessionNotification.forTransition(
        sessionId: session.id,
        turnId: 'turn-1',
        transition: SessionNotificationTransition.queuedToRunning,
      ),
    ],
  );
}

final class _FakeCommonCodeSessionDriver implements CommonCodeSessionDriver {
  _FakeCommonCodeSessionDriver({
    this.binding = const CommonCodeSessionBinding.attached(
      sessionId: 'desktop-session',
    ),
  });

  final CommonCodeSessionBinding binding;
  final List<String> acknowledgedNotificationIds = <String>[];
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
  Future<void> acknowledgeNotification({
    required String sessionId,
    required String notificationId,
  }) async {
    acknowledgedNotificationIds.add(notificationId);
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

final class _FakeBootstrapPort {
  _FakeBootstrapPort({
    this.isBootstrapped = false,
    Session? bootstrappedSession,
    this.durableResult = const CommonCodeDurableBootstrapLoadResult.missing(),
    this.legacyResult = const CommonCodeLegacySeedLoadResult.disabled(),
    Session? freshSession,
    this.restoreDurableError,
    this.restoreLegacyError,
    Session? restoredLegacySession,
  }) : _bootstrappedSession = bootstrappedSession ?? _bootstrapSession(),
       _freshSession = freshSession ?? _bootstrapSessionWithNotification(),
       _restoredLegacySession = restoredLegacySession ?? _bootstrapSession();

  final bool isBootstrapped;

  final Session _bootstrappedSession;
  final Session _freshSession;
  final Session _restoredLegacySession;
  final CommonCodeDurableBootstrapLoadResult durableResult;
  final CommonCodeLegacySeedLoadResult legacyResult;
  final Object? restoreDurableError;
  final Object? restoreLegacyError;

  int createFreshCalls = 0;
  int loadDurableCalls = 0;
  int loadLegacyCalls = 0;
  int restoreDurableCalls = 0;
  int restoreLegacyCalls = 0;

  Future<Session> createFreshSession(
    CommonCodeSessionBootstrapRequest request,
  ) async {
    createFreshCalls += 1;
    return _freshSession;
  }

  Future<CommonCodeDurableBootstrapLoadResult> loadDurableSessionCandidate({
    required String attachedClientId,
  }) async {
    loadDurableCalls += 1;
    return durableResult;
  }

  Future<CommonCodeLegacySeedLoadResult> loadLegacySeedSession({
    required String attachedClientId,
  }) async {
    loadLegacyCalls += 1;
    return legacyResult;
  }

  Session readBootstrappedSession() => _bootstrappedSession;

  Session restoreDurableSession(Session session) {
    restoreDurableCalls += 1;
    if (restoreDurableError case final Object error) {
      throw error;
    }
    return session;
  }

  Future<Session> restoreLegacySeededSession({
    required Session session,
    required String attachedClientId,
  }) async {
    restoreLegacyCalls += 1;
    if (restoreLegacyError case final Object error) {
      throw error;
    }
    return _restoredLegacySession;
  }
}
