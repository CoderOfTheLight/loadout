import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/main.dart';

void main() {
  testWidgets('explains offline privacy on first screen', (tester) async {
    await tester.pumpWidget(const LoadoutApp());
    expect(find.textContaining('Nothing is uploaded'), findsOneWidget);
    expect(find.text('Create workspace'), findsOneWidget);
  });
}
