import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tv_app/main.dart';

void main() {
  testWidgets('ClearCast shows shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ClearCastApp());
    await tester.pump();
    expect(find.text('ClearCast'), findsOneWidget);
  });
}
