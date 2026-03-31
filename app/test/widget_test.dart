import 'package:flutter_test/flutter_test.dart';

import 'package:app/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MirrorApp());
    expect(find.text('Mirror'), findsOneWidget);
  });
}
