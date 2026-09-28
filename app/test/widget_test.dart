import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Smoke test - MaterialApp renders', (WidgetTester tester) async {
    // Pump a minimal widget that has no platform channel or network dependencies.
    // Full integration tests (Supabase, GoogleFonts, BLE) require a real device.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('SafeLink')),
        ),
      ),
    );
    expect(find.text('SafeLink'), findsOneWidget);
  });
}
