import 'package:flutter_test/flutter_test.dart';

import 'package:tickety/main.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const TicketyApp());

    // Verify the app renders with the discover header
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Featured'), findsOneWidget);
  });
}
