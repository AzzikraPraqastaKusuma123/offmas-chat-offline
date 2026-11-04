import 'package:flutter_test/flutter_test.dart';
import 'package:offmas/main.dart';

void main() {
  testWidgets('OFFMAS app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const OffmasApp());
    expect(find.byType(OffmasApp), findsOneWidget);
  });
}
