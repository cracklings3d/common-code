import 'dart:async';

import 'package:common_code_desktop/main.dart';
import 'package:common_code_desktop/src/desktop_session_controller.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter/material.dart' show FilledButton, TextField;
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
        _buildSnapshot(session: _buildRunningTurnSession()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Lifecycle: active (running)'), findsOneWidget);
    expect(find.text('Turn running: Stored submitted turn'), findsOneWidget);

    controller.emit(
      DesktopSessionControllerState.data(
        _buildSnapshot(session: _buildCompletedTurnSession()),
      ),
    );
    await tester.pump();
    await tester.pump();

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
          _buildSnapshot(session: _buildRunningTurnSession()),
        ),
      );
      await tester.pump();
      await tester.pump();

      controller.emit(
        DesktopSessionControllerState.data(
          _buildSnapshot(session: _buildFailedTurnSession()),
        ),
      );
      await tester.pump();
      await tester.pump();

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
    'initial running snapshot and replayed terminal snapshot do not backfill duplicate notices',
    (WidgetTester tester) async {
      final controller = _FakeDesktopSessionController(
        onInitialize: (controller) {
          controller.emit(
            DesktopSessionControllerState.data(
              _buildSnapshot(session: _buildRunningTurnSession()),
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

      controller.emit(
        DesktopSessionControllerState.data(
          _buildSnapshot(session: _buildCompletedTurnSession()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Outcome: completed'), findsOneWidget);
      expect(
        find.text('Turn completed: Stored submitted turn'),
        findsOneWidget,
      );

      controller.emit(
        DesktopSessionControllerState.data(
          _buildSnapshot(session: _buildCompletedTurnSession()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Turn completed: Stored submitted turn'),
        findsOneWidget,
      );
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

Session _buildRunningTurnSession() =>
    _buildActiveTurnSession().advanceActiveTurnToRunning();

Session _buildCompletedTurnSession() =>
    _buildRunningTurnSession().completeActiveTurn();

Session _buildFailedTurnSession() => _buildRunningTurnSession().failActiveTurn(
  failureSummary: 'Simulated host failure.',
);

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

final class _FakeDesktopSessionController extends DesktopSessionController {
  _FakeDesktopSessionController({
    _ControllerCallback? onInitialize,
    _ControllerCallback? onRefresh,
    _SubmitCallback? onSubmit,
  }) : _onInitialize = onInitialize,
       _onRefresh = onRefresh,
       _onSubmit = onSubmit;

  final _ControllerCallback? _onInitialize;
  final _ControllerCallback? _onRefresh;
  final _SubmitCallback? _onSubmit;
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
}
