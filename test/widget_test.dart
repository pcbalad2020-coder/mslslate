import 'package:flutter_test/flutter_test.dart';

import 'package:mslslate/main.dart';

void main() {
  testWidgets('App builds and shows the home screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MosalsalatiApp());
    await tester.pump();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(kAppName), findsOneWidget);
  });
}
