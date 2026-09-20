import 'package:flutter_test/flutter_test.dart';
import 'package:gps_safety_wearable/core/di/service_locator.dart';
import 'package:gps_safety_wearable/main.dart';

void main() {
  setUp(() async {
    await setupServiceLocator();
  });

  testWidgets('SafeGuardApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SafeGuardApp());
    expect(find.byType(SafeGuardApp), findsOneWidget);
  });
}
