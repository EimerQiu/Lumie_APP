// Basic Flutter widget test for Lumie Activity App

import 'package:flutter_test/flutter_test.dart';

import 'package:lumie_activity_app/main.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LumieActivityApp());

    // Verify the app loads with expected content
    expect(find.text('Good Morning!'), findsOneWidget);
  });
}
