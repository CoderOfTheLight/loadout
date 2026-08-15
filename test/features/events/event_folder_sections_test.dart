/// Event detail planned list in folder sections (proposal §3): headers
/// carry per-section counts ("Disposables · 2"), sections read in the
/// owner's folder order, Unfiled last — so the kitchen's part reads
/// together and the van-packing part together, on one list.
library;

import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import 'feature_seeds.dart';

void main() {
  testWidgets('planned items group into folder sections with counts, '
      'folder order, Unfiled last', (tester) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    late String eventId;
    await tester.runAsync(() async {
      final disposables = await folderIdByName(h, 'Disposables');
      final cleaning = await folderIdByName(h, 'Cleaning & setup');
      final plates = await seedItem(
        h,
        name: 'Paper plates',
        folderId: disposables,
      );
      final napkins = await seedItem(h, name: 'Napkins', folderId: disposables);
      final soap = await seedItem(h, name: 'Dish soap', folderId: cleaning);
      final tortillas = await seedItem(h, name: 'Tortillas'); // Unfiled
      // Deliberately shuffled: the sections re-order, the event stores the
      // owner's pick order untouched.
      eventId = await seedEvent(
        h,
        name: 'Street fair',
        date: '2026-08-20',
        exposure: 200,
        itemIds: [tortillas, soap, plates, napkins],
      );
    });

    await h.pumpApp(tester);
    await h.go(tester, '/events/$eventId');

    expect(find.text('Planned items (4)'), findsOneWidget);
    // Per-section counts on the headers.
    expect(find.text('Disposables · 2'), findsOneWidget);
    expect(find.text('Cleaning & setup · 1'), findsOneWidget);
    expect(find.text('Unfiled · 1'), findsOneWidget);
    // Every item still renders, under its section.
    for (final name in ['Paper plates', 'Napkins', 'Dish soap', 'Tortillas']) {
      expect(find.text(name), findsOneWidget);
    }
    // Folder order (starter positions), Unfiled last. SingleChildScrollView
    // lays the whole list out, so vertical positions are comparable even
    // past the fold.
    final disposablesY = tester.getTopLeft(find.text('Disposables · 2')).dy;
    final cleaningY = tester.getTopLeft(find.text('Cleaning & setup · 1')).dy;
    final unfiledY = tester.getTopLeft(find.text('Unfiled · 1')).dy;
    expect(disposablesY, lessThan(cleaningY));
    expect(cleaningY, lessThan(unfiledY));
    await h.flushTimers(tester);
  });
}
