import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets('explains offline privacy on first screen', (tester) async {
    final h = (await tester.runAsync(AppHarness.start))!;
    addTearDown(h.dispose);

    await h.pumpApp(tester);

    expect(find.textContaining('Nothing is uploaded'), findsOneWidget);
    expect(find.text('Create workspace'), findsOneWidget);
  });
}
