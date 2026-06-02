import 'dart:async';
import 'dart:convert';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_desktop/main.dart';
import 'package:common_code_desktop/src/desktop_session_app_edge_composition.dart';
import 'package:common_code_desktop/src/desktop_session_controller.dart';
import 'package:common_code_desktop/src/desktop_session_runtime.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:common_code_persistence/common_code_persistence.dart';
import 'package:flutter/material.dart'
    show FilledButton, SizedBox, SnackBar, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('data state renders a prompt thread conversation', (
    WidgetTester tester,
  ) async {
    // Note: this test verifies the UI rendering once a session is established.
    // The real production bootstrap uses OutOfProcessOpenCodeHostAdapter which
    // requires a running OpenCode host process; that integration scenario is
    // exercised separately. Here we drive the UI into the data state via a
    // fake controller, which is the same pattern used by the rest of these
    // widget tests.
    final completer = Completer<void>();
    final controller = _FakeDesktopSessionController(
      onInitialize: (controller) async {
        await completer.future;
        controller.emit(DesktopSessionControllerState.data(_buildSnapshot()));
      },
    );

    await tester.pumpWidget(
      CommonCodeDesktopApp(sessionController: controller),
    );

    expect(find.text('Loading session...'), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();

    expect(find.text('Prompt Thread'), findsOneWidget);
    expect(find.text('Session context'), findsOneWidget);
    expect(find.text('Local desktop Client: desktop-client'), findsOneWidget);
    expect(find.text('Current Input Client: none'), findsOneWidget);
    expect(find.text('Authoring Mode: available'), findsOneWidget);
    expect(find.text('desktop-client (local)'), findsOneWidget);
    expect(find.text('No turns yet'), findsOneWidget);
    expect(
      find.text('Submit the next turn to start this Prompt Thread.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'Next Turn'), findsOneWidget);
    expect(find.text('Submit Turn'), findsOneWidget);
  });

  testWidgets('loading state is visible before the screen settles', (
    WidgetTester tester,
  ) async {
    final completer = Completer<void>();
    final controller = _FakeDesktopSessionController(
      onInitialize: (controller) async {
        await completer.future;
        controller.emit(DesktopSessionControllerState.data(_buildSnapshot()));
      },
    );

    await tester.pumpWidget(
      CommonCodeDesktopApp(sessionController: controller),
    );

    expect(find.text('Loading session...'), findsOneWidget);
    expect(find.text('Prompt Thread'), findsNothing);

    completer.complete();
    await tester.pumpAndSettle();

    expect(find.text('Prompt Thread'), findsOneWidget);
  });

  testWidgets('empty state renders a distinct empty message', (
    WidgetTester tester,
  ) async {
    final controller = _FakeDesktopSessionController(
      onInitialize: (controller) {
        controller.emit(const DesktopSessionControllerState.empty());
      },
    );

    await tester.pumpWidget(
      CommonCodeDesktopApp(sessionController: controller),
    );
    await tester.pumpAndSettle();

    expect(find.text('No session available.'), findsOneWidget);
    expect(
      find.text('No Session was returned for the desktop app.'),
      findsOneWidget,
    );
    expect(find.text('Failed to load session.'), findsNothing);
  });

  testWidgets('error state renders a retry control for watch failures', (
    WidgetTester tester,
  ) async {
    final controller = _FakeDesktopSessionController(
      onInitialize: (controller) {
        controller.emit(const DesktopSessionControllerState.error('boom'));
      },
      onRefresh: (controller) {
        controller.emit(DesktopSessionControllerState.data(_buildSnapshot()));
      },
    );

    await tester.pumpWidget(
      CommonCodeDesktopApp(sessionController: controller),
    );
    await tester.pumpAndSettle();

    expect(find.text('Failed to load session.'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Prompt Thread'), findsOneWidget);
  });

  testWidgets('refresh updates the rendered session through the controller', (
    WidgetTester tester,
  ) async {
    final controller = _FakeDesktopSessionController(
      onInitialize: (controller) {
        controller.emit(DesktopSessionControllerState.data(_buildSnapshot()));
      },
      onRefresh: (controller) {
        controller.emit(
          DesktopSessionControllerState.data(
            _buildSnapshot(session: _buildActiveTurnSession()),
          ),
        );
      },
    );

    await tester.pumpWidget(
      CommonCodeDesktopApp(sessionController: controller),
    );
    await tester.pumpAndSettle();

    expect(find.text('No turns yet'), findsOneWidget);

    await tester.ensureVisible(find.text('Refresh Session'));
    await tester.tap(find.text('Refresh Session'));
    await tester.pumpAndSettle();

    expect(find.text('Current Input Client: desktop-client'), findsOneWidget);
    expect(
      find.text(
        'Authoring Mode: locked while this desktop client turn is queued or running',
      ),
      findsOneWidget,
    );
    expect(find.text('Stored submitted turn'), findsOneWidget);
    expect(find.text('Lifecycle: active (queued)'), findsOneWidget);
    expect(
      find.text(
        'Next-turn authoring is unavailable while the current turn remains queued or running.',
      ),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('submitting text updates the rendered session snapshot', (
    WidgetTester tester,
  ) async {
    final controller = _FakeDesktopSessionController(
      onInitialize: (controller) {
        controller.emit(DesktopSessionControllerState.data(_buildSnapshot()));
      },
      onSubmit: (controller, submittedText) {
        controller.submittedTexts.add(submittedText);
        controller.emit(
          DesktopSessionControllerState.data(
            DesktopSessionSnapshot.fromSession(
              _buildBootstrapSession().startTurn(
                turnId: 'turn-1',
                client: const Client(id: 'desktop-client'),
                submittedText: submittedText,
              ),
              'desktop-client',
            ),
          ),
        );
      },
    );

    await tester.pumpWidget(
      CommonCodeDesktopApp(sessionController: controller),
    );
    await tester.pumpAndSettle();

    // Before submitting: empty prompt thread
    expect(find.text('No turns yet'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Next Turn'), findsOneWidget);

    // Enter text and submit
    await tester.enterText(
      find.widgetWithText(TextField, 'Next Turn'),
      'Hello world',
    );
    await tester.tap(find.text('Submit Turn'));
    await tester.pumpAndSettle();

    // After submitting: turn appears
    expect(find.text('Hello world'), findsOneWidget);
    expect(find.text('Stored submitted turn'), findsNothing);
  });
}

DesktopSessionSnapshot _buildSnapshot({Session? session}) {
  return DesktopSessionSnapshot.fromSession(
    session ?? _buildBootstrapSession(),
    'desktop-client',
  );
}

Session _buildBootstrapSession() {
  return Session(
    id: 'desktop-session',
    activeHost: const Host(id: 'desktop-host'),
  ).attachClient(const Client(id: 'desktop-client'));
}

Session _buildSessionWithAdditionalClient() {
  return _buildBootstrapSession().attachClient(
    const Client(id: 'reviewer-client'),
  );
}

Session _buildActiveTurnSession() {
  final client = const Client(id: 'desktop-client');

  return Session(
        id: 'desktop-session',
        activeHost: const Host(id: 'desktop-host'),
      )
      .attachClient(client)
      .startTurn(
        turnId: 'turn-1',
        client: client,
        submittedText: 'Stored submitted turn',
      );
}

Session _buildCrossClientReadOnlySession() {
  const desktopClient = Client(id: 'desktop-client');
  const reviewerClient = Client(id: 'reviewer-client');

  return Session(
        id: 'desktop-session',
        activeHost: const Host(id: 'desktop-host'),
      )
      .attachClient(desktopClient)
      .attachClient(reviewerClient)
      .startTurn(
        turnId: 'turn-1',
        client: reviewerClient,
        submittedText: 'Reviewer-owned queued turn',
      );
}

Session _buildQueuedTurnSession() => _buildActiveTurnSession();

Session _buildRunningTurnSessionWithNotification({
  bool isAcknowledged = false,
}) {
  return _buildSessionWithNotifications(
    turns: const [
      Turn.running(
        id: 'turn-1',
        clientId: 'desktop-client',
        submittedText: 'Stored submitted turn',
      ),
    ],
    notifications: [
      SessionNotification.forTransition(
        sessionId: 'desktop-session',
        turnId: 'turn-1',
        transition: SessionNotificationTransition.queuedToRunning,
        isAcknowledged: isAcknowledged,
      ),
    ],
  );
}

Session _buildCompletedTurnSessionWithNotification({
  bool isAcknowledged = false,
}) {
  return _buildSessionWithNotifications(
    turns: const [
      Turn.completed(
        id: 'turn-1',
        clientId: 'desktop-client',
        submittedText: 'Stored submitted turn',
      ),
    ],
    notifications: [
      SessionNotification.forTransition(
        sessionId: 'desktop-session',
        turnId: 'turn-1',
        transition: SessionNotificationTransition.runningToCompleted,
        isAcknowledged: isAcknowledged,
      ),
    ],
  );
}

Session _buildFailedTurnSessionWithNotification({bool isAcknowledged = false}) {
  return _buildSessionWithNotifications(
    turns: const [
      Turn.failed(
        id: 'turn-1',
        clientId: 'desktop-client',
        submittedText: 'Stored submitted turn',
        failureSummary: 'Simulated host failure.',
      ),
    ],
    notifications: [
      SessionNotification.forTransition(
        sessionId: 'desktop-session',
        turnId: 'turn-1',
        transition: SessionNotificationTransition.runningToFailed,
        isAcknowledged: isAcknowledged,
      ),
    ],
  );
}

Session _buildSessionWithNotifications({
  required List<Turn> turns,
  required List<SessionNotification> notifications,
}) {
  return Session(
    id: 'desktop-session',
    activeHost: const Host(id: 'desktop-host'),
    clients: const [Client(id: 'desktop-client')],
    promptThread: PromptThread(turns: turns),
    notifications: notifications,
  );
}

Session _buildOrderedConversationSession() {
  const desktopClient = Client(id: 'desktop-client');
  const reviewerClient = Client(id: 'reviewer-client');

  return Session(
        id: 'desktop-session',
        activeHost: const Host(id: 'desktop-host'),
      )
      .attachClient(desktopClient)
      .attachClient(reviewerClient)
      .startTurn(
        turnId: 'turn-1',
        client: desktopClient,
        submittedText: 'First submitted turn',
      )
      .advanceActiveTurnToRunning()
      .completeActiveTurn()
      .startTurn(
        turnId: 'turn-2',
        client: reviewerClient,
        submittedText: 'Second submitted turn',
      )
      .advanceActiveTurnToRunning()
      .failActiveTurn(failureSummary: 'Ordered failure.');
}

typedef _ControllerCallback =
    FutureOr<void> Function(_FakeDesktopSessionController controller);
typedef _SubmitCallback =
    FutureOr<void> Function(
      _FakeDesktopSessionController controller,
      String submittedText,
    );
typedef _AcknowledgeCallback =
    FutureOr<void> Function(
      _FakeDesktopSessionController controller,
      String notificationId,
    );

final class _FakeDesktopSessionController extends DesktopSessionController {
  _FakeDesktopSessionController({
    _ControllerCallback? onInitialize,
    _ControllerCallback? onRefresh,
    _SubmitCallback? onSubmit,
    _AcknowledgeCallback? onAcknowledge,
  }) : _onInitialize = onInitialize,
       _onRefresh = onRefresh,
       _onSubmit = onSubmit,
       _onAcknowledge = onAcknowledge;

  final _ControllerCallback? _onInitialize;
  final _ControllerCallback? _onRefresh;
  final _SubmitCallback? _onSubmit;
  final _AcknowledgeCallback? _onAcknowledge;
  final List<String> submittedTexts = <String>[];

  void emit(DesktopSessionControllerState state) {
    emitState(state);
  }

  @override
  Future<void> initialize() => Future.sync(() => _onInitialize?.call(this));

  @override
  Future<void> refresh() => Future.sync(() => _onRefresh?.call(this));

  @override
  Future<void> submitTurn({required String submittedText}) async {
    emit(
      DesktopSessionControllerState.data(_buildSnapshot(), isSubmitting: true),
    );
    await Future.sync(() => _onSubmit?.call(this, submittedText));
  }

  @override
  Future<void> acknowledgeNotification({required String notificationId}) {
    return Future.sync(() => _onAcknowledge?.call(this, notificationId));
  }
}

final class _AcknowledgeFailingRuntime implements DesktopSessionRuntime {
  _AcknowledgeFailingRuntime({required Session session}) : _session = session;

  final Session _session;

  @override
  void bind({
    required void Function(Session session) onSnapshot,
    required void Function(Object error, StackTrace stackTrace) onWatchError,
  }) {
    _onSnapshot = onSnapshot;
  }

  void Function(Session session)? _onSnapshot;

  @override
  Future<void> initialize() async {
    _emitSession();
  }

  @override
  Future<void> refresh() async {
    _emitSession();
  }

  @override
  Future<void> acknowledgeNotification({required String notificationId}) {
    return Future<void>.error(StateError('ack failed'));
  }

  @override
  Future<void> submitTurn({required String submittedText}) async {}

  @override
  Future<void> dispose() async {}

  void _emitSession() {
    _onSnapshot?.call(_session);
  }
}
