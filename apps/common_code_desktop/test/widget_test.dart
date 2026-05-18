// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:common_code_desktop/main.dart';

void main() {
  testWidgets('renders a service-backed session summary', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(CommonCodeDesktopApp());

    expect(find.text('CommonCode Desktop'), findsOneWidget);
    expect(find.text('Desktop host boundary proof'), findsOneWidget);
    expect(find.text('Session id: desktop-session'), findsOneWidget);
    expect(find.text('Active host id: desktop-host'), findsOneWidget);
    expect(find.text('Attached clients: 1'), findsOneWidget);
    expect(find.text('Attached client ids: desktop-client'), findsOneWidget);
  });
}
