import 'dart:async';

import 'package:common_code_desktop/main.dart';
import 'package:common_code_desktop/src/desktop_session_controller.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('production bootstrap path renders a real session summary', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(CommonCodeDesktopApp());

    expect(find.text('Loading session...'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Live Session state'), findsOneWidget);
    expect(find.text('Session id: desktop-session'), findsOneWidget);
    expect(find.text('Host id: desktop-host'), findsOneWidget);
    expect(find.text('Attached Client: desktop-client'), findsOneWidget);
    expect(find.text('Attached Clients: desktop-client'), findsOneWidget);
    expect(find.text('Input Client: none'), findsOneWidget);
    expect(find.text('Prompt Thread turns: 0'), findsOneWidget);
    expect(find.text('Active Turn: none'), findsOneWidget);
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
    expect(find.text('Live Session state'), findsNothing);

    completer.complete();
    await tester.pumpAndSettle();

    expect(find.text('Live Session state'), findsOneWidget);
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

    expect(find.text('Live Session state'), findsOneWidget);
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

    expect(find.text('Prompt Thread turns: 0'), findsOneWidget);
    expect(find.text('Active Turn: none'), findsOneWidget);

    await tester.tap(find.text('Refresh Session'));
    await tester.pumpAndSettle();

    expect(find.text('Prompt Thread turns: 1'), findsOneWidget);
    expect(find.text('Active Turn: turn-1'), findsOneWidget);
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
    await tester.tap(find.text('Submit Turn'));
    await tester.pumpAndSettle();

    expect(controller.submittedTexts, ['Submit the first desktop turn.']);
    expect(find.text('Attached Clients: desktop-client'), findsOneWidget);
    expect(find.text('Input Client: desktop-client'), findsOneWidget);
    expect(find.text('Prompt Thread turns: 1'), findsOneWidget);
    expect(find.text('Active Turn: turn-1'), findsOneWidget);
    expect(
      find.text('Turn turn-1: Submit the first desktop turn.'),
      findsOneWidget,
    );
    expect(find.text('Status: queued'), findsOneWidget);
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

    expect(find.text('Live Session state'), findsOneWidget);
    expect(find.text('Prompt Thread turns: 0'), findsOneWidget);

    controller.emit(
      DesktopSessionControllerState.data(
        _buildSnapshot(session: _buildQueuedTurnSession()),
      ),
    );
    await tester.pump();

    expect(find.text('Status: queued'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    controller.emit(
      DesktopSessionControllerState.data(
        _buildSnapshot(session: _buildRunningTurnSession()),
      ),
    );
    await tester.pump();

    expect(find.text('Status: running'), findsOneWidget);

    controller.emit(
      DesktopSessionControllerState.data(
        _buildSnapshot(session: _buildCompletedTurnSession()),
      ),
    );
    await tester.pump();

    expect(find.text('Status: completed'), findsOneWidget);
    expect(find.text('Active Turn: none'), findsOneWidget);
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
          _buildSnapshot(session: _buildFailedTurnSession()),
        ),
      );
      await tester.pump();

      expect(find.text('Failed to load session.'), findsNothing);
      expect(find.text('Status: failed'), findsOneWidget);
      expect(find.text('Failure: Simulated host failure.'), findsOneWidget);
      expect(find.text('Active Turn: none'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Next Turn'), findsOneWidget);
    },
  );
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

Session _buildQueuedTurnSession() => _buildActiveTurnSession();

Session _buildRunningTurnSession() =>
    _buildActiveTurnSession().advanceActiveTurnToRunning();

Session _buildCompletedTurnSession() =>
    _buildRunningTurnSession().completeActiveTurn();

Session _buildFailedTurnSession() => _buildRunningTurnSession().failActiveTurn(
  failureSummary: 'Simulated host failure.',
);

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
