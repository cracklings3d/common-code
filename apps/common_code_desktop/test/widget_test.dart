import 'dart:async';

import 'package:common_code_desktop/main.dart';
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
    final completer = Completer<DesktopSessionSnapshot?>();

    await tester.pumpWidget(
      CommonCodeDesktopApp(
        sessionLoader: _FakeDesktopSessionLoader(
          watchFactory: () => completer.future.asStream(),
        ),
      ),
    );

    expect(find.text('Loading session...'), findsOneWidget);
    expect(find.text('Live Session state'), findsNothing);

    completer.complete(_buildSnapshot());
    await tester.pumpAndSettle();

    expect(find.text('Live Session state'), findsOneWidget);
  });

  testWidgets('empty state renders a distinct empty message', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      CommonCodeDesktopApp(
        sessionLoader: _FakeDesktopSessionLoader(
          watchFactory: () => Stream<DesktopSessionSnapshot?>.value(null),
        ),
      ),
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
    final loader = _RetryingDesktopSessionLoader();

    await tester.pumpWidget(CommonCodeDesktopApp(sessionLoader: loader));

    await tester.pumpAndSettle();

    expect(find.text('Failed to load session.'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
  });

  testWidgets('refresh cancels the prior watch subscription', (
    WidgetTester tester,
  ) async {
    final loader = _RefreshableDesktopSessionLoader([
      [_buildSnapshot()],
      [_buildSnapshot(session: _buildActiveTurnSession())],
    ]);

    await tester.pumpWidget(CommonCodeDesktopApp(sessionLoader: loader));

    await tester.pumpAndSettle();

    expect(find.text('Input Client: none'), findsOneWidget);
    expect(find.text('Prompt Thread turns: 0'), findsOneWidget);
    expect(find.text('Active Turn: none'), findsOneWidget);

    await tester.tap(find.text('Refresh Session'));
    await tester.pump();
    await tester.pump();

    expect(loader.cancelCount, 1);
  });

  testWidgets('submitting text updates the rendered session snapshot', (
    WidgetTester tester,
  ) async {
    final loader = _RecordingDesktopSessionLoader();

    await tester.pumpWidget(CommonCodeDesktopApp(sessionLoader: loader));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'Submit the first desktop turn.',
    );
    await tester.tap(find.text('Submit Turn'));
    await tester.pumpAndSettle();

    expect(loader.submittedTexts, ['Submit the first desktop turn.']);
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

  testWidgets('screen updates from watch stream without manual refresh', (
    WidgetTester tester,
  ) async {
    final loader = _StreamingDesktopSessionLoader();

    await tester.pumpWidget(CommonCodeDesktopApp(sessionLoader: loader));
    await tester.pump();

    expect(find.text('Live Session state'), findsOneWidget);
    expect(find.text('Prompt Thread turns: 0'), findsOneWidget);

    loader.emit(_buildSnapshot(session: _buildQueuedTurnSession()));
    await tester.pump();
    await tester.pump();

    expect(find.text('Status: queued'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    loader.emit(_buildSnapshot(session: _buildRunningTurnSession()));
    await tester.pump();
    await tester.pump();

    expect(find.text('Status: running'), findsOneWidget);

    loader.emit(_buildSnapshot(session: _buildCompletedTurnSession()));
    await tester.pump();
    await tester.pump();

    expect(find.text('Status: completed'), findsOneWidget);
    expect(find.text('Active Turn: none'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Next Turn'), findsOneWidget);
  });

  testWidgets(
    'terminal failure stays on data screen and shows failure summary',
    (WidgetTester tester) async {
      final loader = _StreamingDesktopSessionLoader();

      await tester.pumpWidget(CommonCodeDesktopApp(sessionLoader: loader));
      await tester.pump();

      loader.emit(_buildSnapshot(session: _buildFailedTurnSession()));
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

final class _FakeDesktopSessionLoader implements DesktopSessionLoader {
  _FakeDesktopSessionLoader({
    required Stream<DesktopSessionSnapshot?> Function() watchFactory,
  }) : _watchFactory = watchFactory;

  final Stream<DesktopSessionSnapshot?> Function() _watchFactory;

  @override
  Future<DesktopSessionSnapshot?> load() => watch().first;

  @override
  Stream<DesktopSessionSnapshot?> watch() => _watchFactory();

  @override
  Future<DesktopSessionSnapshot> submitTurn({required String submittedText}) {
    throw UnimplementedError('submitTurn is not used in this fake loader.');
  }
}

final class _RecordingDesktopSessionLoader implements DesktopSessionLoader {
  final List<String> submittedTexts = <String>[];
  final StreamController<DesktopSessionSnapshot?> _controller =
      StreamController<DesktopSessionSnapshot?>.broadcast();
  DesktopSessionSnapshot _snapshot = _buildSnapshot();

  @override
  Future<DesktopSessionSnapshot?> load() async => _snapshot;

  @override
  Stream<DesktopSessionSnapshot?> watch() => Stream.multi((multi) {
    multi.add(_snapshot);
    final subscription = _controller.stream.listen(
      multi.add,
      onError: multi.addError,
      onDone: multi.close,
    );
    multi.onCancel = subscription.cancel;
  });

  @override
  Future<DesktopSessionSnapshot> submitTurn({
    required String submittedText,
  }) async {
    submittedTexts.add(submittedText);
    _snapshot = DesktopSessionSnapshot(
      attachedClientId: 'desktop-client',
      session: _buildBootstrapSession().startTurn(
        turnId: 'turn-1',
        client: const Client(id: 'desktop-client'),
        submittedText: submittedText,
      ),
    );

    _controller.add(_snapshot);

    return _snapshot;
  }
}

final class _StreamingDesktopSessionLoader implements DesktopSessionLoader {
  DesktopSessionSnapshot? _latest = _buildSnapshot();
  final StreamController<DesktopSessionSnapshot?> _controller =
      StreamController<DesktopSessionSnapshot?>.broadcast();

  void emit(DesktopSessionSnapshot? snapshot) {
    _latest = snapshot;
    _controller.add(snapshot);
  }

  @override
  Future<DesktopSessionSnapshot?> load() async => _latest;

  @override
  Stream<DesktopSessionSnapshot?> watch() => Stream.multi((multi) {
    multi.add(_latest);
    final subscription = _controller.stream.listen(
      multi.add,
      onError: multi.addError,
      onDone: multi.close,
    );
    multi.onCancel = subscription.cancel;
  });

  @override
  Future<DesktopSessionSnapshot> submitTurn({required String submittedText}) {
    throw UnimplementedError('submitTurn is not used in this fake loader.');
  }
}

final class _RefreshableDesktopSessionLoader implements DesktopSessionLoader {
  _RefreshableDesktopSessionLoader(this._watchEvents);

  final List<List<DesktopSessionSnapshot?>> _watchEvents;
  int watchCount = 0;
  int cancelCount = 0;

  @override
  Future<DesktopSessionSnapshot?> load() async => _watchEvents.first.first;

  @override
  Stream<DesktopSessionSnapshot?> watch() {
    final events = _watchEvents[watchCount];
    watchCount += 1;

    late final StreamController<DesktopSessionSnapshot?> controller;
    controller = StreamController<DesktopSessionSnapshot?>(
      onListen: () {
        for (final event in events) {
          controller.add(event);
        }
      },
      onCancel: () {
        cancelCount += 1;
      },
    );

    return controller.stream;
  }

  @override
  Future<DesktopSessionSnapshot> submitTurn({required String submittedText}) {
    throw UnimplementedError('submitTurn is not used in this fake loader.');
  }
}

final class _RetryingDesktopSessionLoader implements DesktopSessionLoader {
  int watchCount = 0;

  @override
  Future<DesktopSessionSnapshot?> load() async => _buildSnapshot();

  @override
  Stream<DesktopSessionSnapshot?> watch() {
    watchCount += 1;

    late final StreamController<DesktopSessionSnapshot?> controller;
    controller = StreamController<DesktopSessionSnapshot?>(
      onListen: () {
        if (watchCount == 1) {
          controller.addError(StateError('boom'));
        } else {
          controller.add(_buildSnapshot());
        }
      },
    );

    return controller.stream;
  }

  @override
  Future<DesktopSessionSnapshot> submitTurn({required String submittedText}) {
    throw UnimplementedError('submitTurn is not used in this fake loader.');
  }
}
