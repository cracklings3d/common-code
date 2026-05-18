import 'dart:async';

import 'package:common_code_desktop/main.dart';
import 'package:common_code_domain/common_code_domain.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter_test/flutter_test.dart';

void main() {
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
        sessionLoader: _FakeDesktopSessionLoader(() => completer.future),
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
        sessionLoader: _FakeDesktopSessionLoader(() async => null),
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

  testWidgets('error state renders a retry path that reloads the session', (
    WidgetTester tester,
  ) async {
    var attempts = 0;

    await tester.pumpWidget(
      CommonCodeDesktopApp(
        sessionLoader: _FakeDesktopSessionLoader(() async {
          attempts += 1;
          if (attempts == 1) {
            throw StateError('boom');
          }

          return _buildSnapshot();
        }),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Failed to load session.'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Live Session state'), findsOneWidget);
    expect(find.text('Session id: desktop-session'), findsOneWidget);
  });

  testWidgets('reread updates the rendered session summary', (
    WidgetTester tester,
  ) async {
    var loadCount = 0;

    await tester.pumpWidget(
      CommonCodeDesktopApp(
        sessionLoader: _FakeDesktopSessionLoader(() async {
          loadCount += 1;
          if (loadCount == 1) {
            return _buildSnapshot();
          }

          return _buildSnapshot(session: _buildActiveTurnSession());
        }),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Input Client: none'), findsOneWidget);
    expect(find.text('Prompt Thread turns: 0'), findsOneWidget);
    expect(find.text('Active Turn: none'), findsOneWidget);

    await tester.tap(find.text('Refresh Session'));
    await tester.pumpAndSettle();

    expect(find.text('Input Client: desktop-client'), findsOneWidget);
    expect(find.text('Prompt Thread turns: 1'), findsOneWidget);
    expect(find.text('Active Turn: turn-1'), findsOneWidget);
    expect(
      find.text(
        'Turn authoring is unavailable while the current active Turn remains in progress.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('submitting text updates the rendered session snapshot', (
    WidgetTester tester,
  ) async {
    final loader = _RecordingDesktopSessionLoader();

    await tester.pumpWidget(CommonCodeDesktopApp(sessionLoader: loader));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Submit the first desktop turn.');
    await tester.tap(find.text('Submit Turn'));
    await tester.pumpAndSettle();

    expect(loader.submittedTexts, ['Submit the first desktop turn.']);
    expect(find.text('Input Client: desktop-client'), findsOneWidget);
    expect(find.text('Prompt Thread turns: 1'), findsOneWidget);
    expect(find.text('Active Turn: turn-1'), findsOneWidget);
    expect(
      find.text('Turn turn-1: Submit the first desktop turn.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Submit Turn'), findsNothing);
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

Session _buildActiveTurnSession() {
  final client = const Client(id: 'desktop-client');

  return Session(
    id: 'desktop-session',
    activeHost: const Host(id: 'desktop-host'),
  ).attachClient(client).startTurn(
    turnId: 'turn-1',
    client: client,
    submittedText: 'Stored submitted turn',
  );
}

final class _FakeDesktopSessionLoader implements DesktopSessionLoader {
  _FakeDesktopSessionLoader(this._onLoad);

  final Future<DesktopSessionSnapshot?> Function() _onLoad;

  @override
  Future<DesktopSessionSnapshot?> load() => _onLoad();

  @override
  Future<DesktopSessionSnapshot> submitTurn({required String submittedText}) {
    throw UnimplementedError('submitTurn is not used in this fake loader.');
  }
}

final class _RecordingDesktopSessionLoader implements DesktopSessionLoader {
  final List<String> submittedTexts = <String>[];
  DesktopSessionSnapshot _snapshot = _buildSnapshot();

  @override
  Future<DesktopSessionSnapshot?> load() async => _snapshot;

  @override
  Future<DesktopSessionSnapshot> submitTurn({required String submittedText}) async {
    submittedTexts.add(submittedText);
    _snapshot = DesktopSessionSnapshot(
      attachedClientId: 'desktop-client',
      session: _buildBootstrapSession().startTurn(
        turnId: 'turn-1',
        client: const Client(id: 'desktop-client'),
        submittedText: submittedText,
      ),
    );

    return _snapshot;
  }
}
