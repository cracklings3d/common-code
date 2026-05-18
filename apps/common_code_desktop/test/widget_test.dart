// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:common_code_desktop/main.dart';

void main() {
  testWidgets('renders placeholder package wiring', (WidgetTester tester) async {
    await tester.pumpWidget(const CommonCodeDesktopApp());

    expect(find.text('CommonCode Desktop Scaffold'), findsOneWidget);
    expect(find.text('Windows-first Flutter workspace scaffold'), findsOneWidget);
    expect(
      find.text('Domain package: common_code_domain placeholder contract'),
      findsOneWidget,
    );
    expect(
      find.text('Host package: host_core placeholder contract'),
      findsOneWidget,
    );
  });
}
