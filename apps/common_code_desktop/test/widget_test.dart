import 'dart:async';
import 'dart:convert';

import 'package:common_code_application/common_code_application.dart';
import 'package:common_code_desktop/main.dart';
import 'package:common_code_desktop/src/desktop_session_app_edge_composition.dart';
import 'package:common_code_desktop/src/desktop_session_controller.dart';
import 'package:common_code_desktop/src/desktop_session_runtime.dart';
import 'package:common_code_desktop/src/desktop_session_snapshot_codec.dart';
import 'package:common_code_desktop/src/desktop_session_snapshot_store.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter/material.dart'
    show FilledButton, SizedBox, SnackBar, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'production bootstrap path renders a prompt thread conversation',
    (WidgetTester tester) async {
      await tester.pumpWidget(CommonCodeDesktopApp());

      expect(find.text('Loading session...'), findsOneWidget);

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
    },
  );

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
            DesktopSessionSnapshot(
              attachedClientId: 'desktop-client',
              session: _buildBootstrapSession().startTurn(
                turnId: 'turn-1',
                client: const Client(id: 'desktop-client'),
                submittedText: submittedText,
              ),
            ),
          ),
        );
      },
    );

    await tester.pumpWidget(
      CommonCodeDesktopApp(sessionController: controller),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'Submit the first desktop turn.',
    );
    await tester.ensureVisible(find.text('Submit Turn'));
    await tester.tap(find.text('Submit Turn'));
    await tester.pumpAndSettle();

    expect(controller.submittedTexts, ['Submit the first desktop turn.']);
    expect(find.text('This desktop client'), findsOneWidget);
    expect(find.text('Current Input Client: desktop-client'), findsOneWidget);
    expect(find.text('desktop-client (local, input)'), findsOneWidget);
    expect(find.text('Submit the first desktop turn.'), findsOneWidget);
    expect(find.text('Lifecycle: active (queued)'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Submit Turn'), findsNothing);
  });

  testWidgets('screen updates from controller state without manual refresh', (
    WidgetTester tester,
  ) async {
    final controller = _FakeDesktopSessionController(
      onInitialize: (controller) {
        controller.emit(DesktopSessionControllerState.data(_buildSnapshot()));
      },
    );

    await tester.pumpWidget(
      CommonCodeDesktopApp(sessionController: controller),
    );
    await tester.pump();

    expect(find.text('Prompt Thread'), findsOneWidget);
    expect(find.text('No turns yet'), findsOneWidget);

    controller.emit(
      DesktopSessionControllerState.data(
        _buildSnapshot(session: _buildQueuedTurnSession()),
      ),
    );
    await tester.pump();

    expect(find.text('Lifecycle: active (queued)'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Current Input Client: desktop-client'), findsOneWidget);

    controller.emit(
      DesktopSessionControllerState.data(
        _buildSnapshot(session: _buildRunningTurnSessionWithNotification()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Lifecycle: active (running)'), findsOneWidget);
    expect(find.text('Turn running: Stored submitted turn'), findsOneWidget);

    controller.emit(
      DesktopSessionControllerState.data(
        _buildSnapshot(session: _buildCompletedTurnSessionWithNotification()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('Outcome: completed'), findsOneWidget);
    expect(find.text('Turn completed: Stored submitted turn'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Next Turn'), findsOneWidget);
  });

  testWidgets(
    'terminal failure stays on data screen and shows failure summary',
    (WidgetTester tester) async {
      final controller = _FakeDesktopSessionController(
        onInitialize: (controller) {
          controller.emit(DesktopSessionControllerState.data(_buildSnapshot()));
        },
      );

      await tester.pumpWidget(
        CommonCodeDesktopApp(sessionController: controller),
      );
      await tester.pump();

      controller.emit(
        DesktopSessionControllerState.data(
          _buildSnapshot(session: _buildRunningTurnSessionWithNotification()),
        ),
      );
      await tester.pump();
      await tester.pump();

      controller.emit(
        DesktopSessionControllerState.data(
          _buildSnapshot(session: _buildFailedTurnSessionWithNotification()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load session.'), findsNothing);
      expect(find.text('Outcome: failed'), findsOneWidget);
      expect(find.text('Turn failed: Stored submitted turn'), findsOneWidget);
      expect(
        find.text('Failure summary: Simulated host failure.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'Next Turn'), findsOneWidget);
    },
  );

  testWidgets(
    'first render shows still-unacknowledged running notification already in session state',
    (WidgetTester tester) async {
      final controller = _FakeDesktopSessionController(
        onInitialize: (controller) {
          controller.emit(
            DesktopSessionControllerState.data(
              _buildSnapshot(
                session: _buildRunningTurnSessionWithNotification(),
              ),
            ),
          );
        },
      );

      await tester.pumpWidget(
        CommonCodeDesktopApp(sessionController: controller),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lifecycle: active (running)'), findsOneWidget);
      expect(find.text('Turn running: Stored submitted turn'), findsOneWidget);
    },
  );

  testWidgets('first render suppresses an already acknowledged notification', (
    WidgetTester tester,
  ) async {
    final controller = _FakeDesktopSessionController(
      onInitialize: (controller) {
        controller.emit(
          DesktopSessionControllerState.data(
            _buildSnapshot(
              session: _buildRunningTurnSessionWithNotification(
                isAcknowledged: true,
              ),
            ),
          ),
        );
      },
    );

    await tester.pumpWidget(
      CommonCodeDesktopApp(sessionController: controller),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lifecycle: active (running)'), findsOneWidget);
    expect(find.text('Turn running: Stored submitted turn'), findsNothing);
  });

  testWidgets(
    'repeated delivery of the same notification id does not duplicate visible renders in one runtime',
    (WidgetTester tester) async {
      final controller = _FakeDesktopSessionController(
        onInitialize: (controller) {
          controller.emit(
            DesktopSessionControllerState.data(
              _buildSnapshot(
                session: _buildRunningTurnSessionWithNotification(),
              ),
            ),
          );
        },
      );

      await tester.pumpWidget(
        CommonCodeDesktopApp(sessionController: controller),
      );
      await tester.pumpAndSettle();

      controller.emit(
        DesktopSessionControllerState.data(
          _buildSnapshot(session: _buildRunningTurnSessionWithNotification()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Turn running: Stored submitted turn'), findsOneWidget);
    },
  );

  testWidgets(
    'still-unacknowledged notifications replay after reconnect in the same runtime',
    (WidgetTester tester) async {
      final controller = _FakeDesktopSessionController(
        onInitialize: (controller) {
          controller.emit(
            DesktopSessionControllerState.data(
              _buildSnapshot(
                session: _buildRunningTurnSessionWithNotification(),
              ),
            ),
          );
        },
      );

      await tester.pumpWidget(
        CommonCodeDesktopApp(sessionController: controller),
      );
      await tester.pumpAndSettle();

      controller.emit(const DesktopSessionControllerState.loading());
      await tester.pump();

      controller.emit(
        DesktopSessionControllerState.data(
          _buildSnapshot(session: _buildRunningTurnSessionWithNotification()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Turn running: Stored submitted turn'), findsOneWidget);
    },
  );

  testWidgets(
    'already acknowledged notifications do not replay after reconnect in the same runtime',
    (WidgetTester tester) async {
      final controller = _FakeDesktopSessionController(
        onInitialize: (controller) {
          controller.emit(
            DesktopSessionControllerState.data(
              _buildSnapshot(
                session: _buildRunningTurnSessionWithNotification(
                  isAcknowledged: true,
                ),
              ),
            ),
          );
        },
      );

      await tester.pumpWidget(
        CommonCodeDesktopApp(sessionController: controller),
      );
      await tester.pumpAndSettle();

      controller.emit(const DesktopSessionControllerState.loading());
      await tester.pump();

      controller.emit(
        DesktopSessionControllerState.data(
          _buildSnapshot(
            session: _buildRunningTurnSessionWithNotification(
              isAcknowledged: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Turn running: Stored submitted turn'), findsNothing);
    },
  );

  testWidgets(
    'explicit snackbar acknowledgement uses the live desktop seam and suppresses replay after reconnect',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SharedPreferencesDurableLocalHostStorage.sessionStorageKey: jsonEncode(
          const DesktopSessionSnapshotJsonCodec().encode(
            _buildRunningTurnSessionWithNotification(),
          ),
        ),
      });

      final replayedSnackBarMessage = find.descendant(
        of: find.byType(SnackBar),
        matching: find.text('Turn running: Stored submitted turn'),
      );
      final controller = DesktopSessionController(
        runtime: createDesktopSessionRuntime(
          durableStorage: SharedPreferencesDurableLocalHostStorage(),
          snapshotStore: SharedPreferencesDesktopSessionSnapshotStore(),
        ),
      );

      await tester.pumpWidget(
        CommonCodeDesktopApp(sessionController: controller),
      );
      await tester.pumpAndSettle();

      expect(replayedSnackBarMessage, findsOneWidget);
      expect(find.text('Acknowledge'), findsOneWidget);

      final notificationId = controller.state.snapshot!.session.notifications
          .firstWhere((notification) => !notification.isAcknowledged)
          .id;

      await tester.tap(find.text('Acknowledge'));
      await tester.pumpAndSettle();

      expect(
        controller.state.snapshot!.session.notifications
            .firstWhere((notification) => notification.id == notificationId)
            .isAcknowledged,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      controller.dispose();

      final reconnectedController = DesktopSessionController(
        runtime: createDesktopSessionRuntime(
          durableStorage: SharedPreferencesDurableLocalHostStorage(),
          snapshotStore: SharedPreferencesDesktopSessionSnapshotStore(),
        ),
      );

      await tester.pumpWidget(
        CommonCodeDesktopApp(sessionController: reconnectedController),
      );
      await tester.pumpAndSettle();

      expect(find.text('Prompt Thread'), findsOneWidget);
      expect(replayedSnackBarMessage, findsNothing);

      reconnectedController.dispose();
    },
  );

  testWidgets('acknowledgement failures surface through controller state', (
    WidgetTester tester,
  ) async {
    final controller = DesktopSessionController(
      runtime: _AcknowledgeFailingRuntime(
        session: _buildRunningTurnSessionWithNotification(),
      ),
    );

    await tester.pumpWidget(
      CommonCodeDesktopApp(sessionController: controller),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Acknowledge'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Failed to acknowledge notification: Bad state: ack failed',
      ),
      findsOneWidget,
    );
    expect(
      controller.state.acknowledgementErrorMessage,
      contains('ack failed'),
    );
    expect(controller.state.status, DesktopSessionControllerStatus.data);
  });

  testWidgets(
    'completed outcome notification renders from session-backed notification data',
    (WidgetTester tester) async {
      final controller = _FakeDesktopSessionController(
        onInitialize: (controller) {
          controller.emit(
            DesktopSessionControllerState.data(
              _buildSnapshot(
                session: _buildCompletedTurnSessionWithNotification(),
              ),
            ),
          );
        },
      );

      await tester.pumpWidget(
        CommonCodeDesktopApp(sessionController: controller),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Turn completed: Stored submitted turn'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'failed outcome notification renders from session-backed notification data',
    (WidgetTester tester) async {
      final controller = _FakeDesktopSessionController(
        onInitialize: (controller) {
          controller.emit(
            DesktopSessionControllerState.data(
              _buildSnapshot(
                session: _buildFailedTurnSessionWithNotification(),
              ),
            ),
          );
        },
      );

      await tester.pumpWidget(
        CommonCodeDesktopApp(sessionController: controller),
      );
      await tester.pumpAndSettle();

      expect(find.text('Turn failed: Stored submitted turn'), findsOneWidget);
    },
  );

  testWidgets(
    'empty prompt thread renders placeholder and keeps authoring available',
    (WidgetTester tester) async {
      final controller = _FakeDesktopSessionController(
        onInitialize: (controller) {
          controller.emit(DesktopSessionControllerState.data(_buildSnapshot()));
        },
      );

      await tester.pumpWidget(
        CommonCodeDesktopApp(sessionController: controller),
      );
      await tester.pumpAndSettle();

      expect(find.text('No turns yet'), findsOneWidget);
      expect(
        find.text('Submit the next turn to start this Prompt Thread.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'Next Turn'), findsOneWidget);
      expect(find.text('Submit Turn'), findsOneWidget);
    },
  );

  testWidgets(
    'shows local client input client and attached client set chrome',
    (WidgetTester tester) async {
      final controller = _FakeDesktopSessionController(
        onInitialize: (controller) {
          controller.emit(
            DesktopSessionControllerState.data(
              _buildSnapshot(session: _buildSessionWithAdditionalClient()),
            ),
          );
        },
      );

      await tester.pumpWidget(
        CommonCodeDesktopApp(sessionController: controller),
      );
      await tester.pumpAndSettle();

      expect(find.text('Session context'), findsOneWidget);
      expect(find.text('Local desktop Client: desktop-client'), findsOneWidget);
      expect(find.text('Current Input Client: none'), findsOneWidget);
      expect(find.text('desktop-client (local)'), findsOneWidget);
      expect(find.text('reviewer-client'), findsOneWidget);
      expect(find.text('Prompt Thread'), findsOneWidget);
    },
  );

  testWidgets('cross-client input keeps composer visible but read-only', (
    WidgetTester tester,
  ) async {
    final controller = _FakeDesktopSessionController(
      onInitialize: (controller) {
        controller.emit(
          DesktopSessionControllerState.data(
            _buildSnapshot(session: _buildCrossClientReadOnlySession()),
          ),
        );
      },
    );

    await tester.pumpWidget(
      CommonCodeDesktopApp(sessionController: controller),
    );
    await tester.pumpAndSettle();

    expect(find.text('Current Input Client: reviewer-client'), findsOneWidget);
    expect(find.text('desktop-client (local)'), findsOneWidget);
    expect(find.text('reviewer-client (input)'), findsOneWidget);
    expect(
      find.text(
        'Authoring Mode: read-only while Client reviewer-client owns input',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'This desktop presentation is read-only while Client reviewer-client owns input.',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextField, 'Next Turn (read-only)'),
      findsOneWidget,
    );
    expect(find.text('Submit Turn (read-only)'), findsOneWidget);

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.readOnly, isTrue);
    expect(textField.enabled, isFalse);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Submit Turn (read-only)'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
    'desktop input client case preserves active-turn lockout while identifying local input',
    (WidgetTester tester) async {
      final controller = _FakeDesktopSessionController(
        onInitialize: (controller) {
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

      expect(find.text('Current Input Client: desktop-client'), findsOneWidget);
      expect(find.text('desktop-client (local, input)'), findsOneWidget);
      expect(
        find.text(
          'Next-turn authoring is unavailable while the current turn remains queued or running.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Submit Turn'), findsNothing);
    },
  );

  testWidgets('previously submitted turns render in prompt thread order', (
    WidgetTester tester,
  ) async {
    final controller = _FakeDesktopSessionController(
      onInitialize: (controller) {
        controller.emit(
          DesktopSessionControllerState.data(
            _buildSnapshot(session: _buildOrderedConversationSession()),
          ),
        );
      },
    );

    await tester.pumpWidget(
      CommonCodeDesktopApp(sessionController: controller),
    );
    await tester.pumpAndSettle();

    final firstTextFinder = find.text('First submitted turn');
    final secondTextFinder = find.text('Second submitted turn');

    expect(firstTextFinder, findsOneWidget);
    expect(secondTextFinder, findsOneWidget);
    expect(
      tester.getTopLeft(firstTextFinder).dy <
          tester.getTopLeft(secondTextFinder).dy,
      isTrue,
    );
    expect(find.text('Outcome: completed'), findsOneWidget);
    expect(find.text('Outcome: failed'), findsOneWidget);
    expect(find.text('Failure summary: Ordered failure.'), findsOneWidget);
  });
}

DesktopSessionSnapshot _buildSnapshot({Session? session}) {
  return DesktopSessionSnapshot(
    session: session ?? _buildBootstrapSession(),
    attachedClientId: 'desktop-client',
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
  final StreamController<CommonCodeSessionFacadeState> _states =
      StreamController<CommonCodeSessionFacadeState>.broadcast(sync: true);
  CommonCodeSessionFacadeState _state =
      const CommonCodeSessionFacadeState.loading();

  @override
  void bind({
    required void Function(Session session) onSnapshot,
    required void Function(Object error, StackTrace stackTrace) onWatchError,
  }) {}

  @override
  Stream<CommonCodeSessionFacadeState> get states => _states.stream;

  @override
  CommonCodeSessionFacadeState get state => _state;

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
  Future<void> dispose() async {
    await _states.close();
  }

  void _emitSession() {
    if (_states.isClosed) {
      return;
    }

    _state = CommonCodeSessionFacadeState.data(
      CommonCodeSessionSnapshot(
        session: _session,
        attachedClientId: DesktopSessionController.attachedClientId,
      ),
    );
    _states.add(_state);
  }
}
