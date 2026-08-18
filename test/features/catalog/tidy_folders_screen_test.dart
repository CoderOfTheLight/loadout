/// TidyFoldersScreen + Home tidy prompt widget tests (proposal §5).
///
/// A migrated workspace — items exist, `folders` empty — gets exactly one
/// Home card into a one-time flow that maps every distinct legacy Group
/// (case-insensitively merged) onto folders. Everything commits on the
/// confirm button and ONLY there; skipped groups stay in Unfiled. Fresh
/// workspaces are born with the eight starter folders and never see any of
/// this — that pin lives in `home_screen_test.dart`.
///
/// The migrated state is simulated by archiving the eight seeded starters
/// through the real command path: live folders drop to zero, exactly the
/// signature the v2→v3 migration leaves behind (proved byte-for-byte in
/// `test/db/migration_v2_to_v3_test.dart`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/tidy_folders_screen.dart';
import 'package:loadout/features/home/presentation/tidy_prompt.dart';

import '../../support/app_harness.dart';

void _usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<String> _seedItem(
  AppHarness h,
  WidgetTester tester,
  String name,
  String? category,
) async {
  final result = await tester.runAsync(
    () => h
        .read(catalogServiceProvider)
        .createItem(ItemDraft(name: name, category: category)),
  );
  return result!.fold((id) => id, (error) => throw StateError(error.code));
}

/// Archives the eight seeded starter folders through the real command path,
/// leaving the workspace in the migrated signature: items, no live folders.
///
/// State checks here and below read one-shot DAO/table futures, NOT
/// `watch*().first`: drift caches query streams by statement, so a
/// throwaway real-zone subscription from `runAsync` would entangle the
/// providers' cached streams across zones and deadlock later writes under
/// the widget test's fake async.
Future<void> _archiveStarterFolders(AppHarness h, WidgetTester tester) async {
  await tester.runAsync(() async {
    final service = h.read(catalogServiceProvider);
    final folders = await h.read(appDatabaseProvider).folderDao.live();
    for (final folder in folders) {
      final result = await service.archiveFolder(folder.id);
      result.fold((_) => null, (error) => throw StateError(error.code));
    }
  });
}

/// Completes a drift future from the WIDGET zone by flushing microtasks
/// with zero-duration pumps. The in-memory database completes on
/// microtasks, and staying in the same zone as the screens' own writes
/// avoids the cross-zone executor deadlock a post-tap `runAsync` can hit.
Future<T> _settleFuture<T>(WidgetTester tester, Future<T> future) async {
  var done = false;
  late T value;
  Object? error;
  unawaited(
    future.then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e) {
        error = e;
        done = true;
      },
    ),
  );
  for (var i = 0; i < 50 && !done; i++) {
    await tester.pump(Duration.zero);
  }
  if (!done) fail('drift future did not complete within 50 pumps');
  if (error != null) throw error!;
  return value;
}

/// Live folders straight off the table, in position order.
Future<List<String>> _liveFolderNames(AppHarness h, WidgetTester tester) async {
  final rows = await _settleFuture(
    tester,
    h.read(appDatabaseProvider).folderDao.live(),
  );
  return [for (final row in rows) row.name];
}

/// Item name → live folder name (null = Unfiled), straight off the tables.
Future<Map<String, String?>> _itemPlacements(
  AppHarness h,
  WidgetTester tester,
) async {
  final db = h.read(appDatabaseProvider);
  final folders = {
    for (final folder in await _settleFuture(tester, db.folderDao.live()))
      folder.id: folder.name,
  };
  final items = await _settleFuture(tester, db.select(db.items).get());
  return {
    for (final item in items)
      item.name: item.folderId == null ? null : folders[item.folderId],
  };
}

/// The persisted "Don't show again" flag, read from the widget zone.
Future<String?> _storedHiddenFlag(AppHarness h, WidgetTester tester) =>
    _settleFuture(
      tester,
      h.read(appDatabaseProvider).settingsDao.value(tidyPromptHiddenKey),
    );

/// Two legacy groups ("Drinks"/"drinks" merged + "Bakery"), one to skip
/// ("Cleaning"), in a migrated workspace.
Future<void> _seedMigratedWorkspace(AppHarness h, WidgetTester tester) async {
  await _seedItem(h, tester, 'Cola', 'Drinks');
  await _seedItem(h, tester, 'Fanta', 'drinks');
  await _seedItem(h, tester, 'Rolls', 'Bakery');
  await _seedItem(h, tester, 'Dish soap', 'Cleaning');
  await _archiveStarterFolders(h, tester);
}

Finder _inSheet(String text) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

void main() {
  testWidgets('the tidy flow maps groups to folders, commits only on confirm', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedMigratedWorkspace(h, tester);

    await h.pumpApp(tester);

    // The one Home card, in the approved words.
    expect(find.text('Tidy your items into folders'), findsOneWidget);
    expect(find.text('2 minutes, once'), findsOneWidget);

    await tester.tap(find.text('Tidy your items into folders'));
    await tester.pumpAndSettle();
    expect(find.byType(TidyFoldersScreen), findsOneWidget);

    // "Drinks" and "drinks" read as ONE group of two items; nothing is
    // mapped yet, so everything stays in Unfiled and there is nothing to
    // confirm.
    expect(find.text('Drinks'), findsOneWidget);
    expect(find.text('drinks'), findsNothing);
    expect(find.text('2 items · stays in Unfiled'), findsOneWidget);
    expect(find.text('Cleaning'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Nothing to move yet'),
          )
          .onPressed,
      isNull,
    );

    // Map Drinks → starter "Drinks", Bakery → starter "Bakery"; leave
    // Cleaning alone.
    await tester.tap(find.text('Drinks'));
    await tester.pumpAndSettle();
    expect(_inSheet('Where do "Drinks" items go?'), findsOneWidget);
    await tester.tap(_inSheet('Drinks'));
    await tester.pumpAndSettle();
    expect(find.text('2 items · moves to Drinks'), findsOneWidget);

    await tester.tap(find.text('Bakery'));
    await tester.pumpAndSettle();
    await tester.tap(_inSheet('Bakery'));
    await tester.pumpAndSettle();
    expect(find.text('1 item · moves to Bakery'), findsOneWidget);

    // Nothing has moved yet: the mapping is only staged.
    expect(await _liveFolderNames(h, tester), isEmpty);

    await tester.tap(
      find.widgetWithText(FilledButton, 'Move 3 items into 2 folders'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Filed 3 items into 2 folders.'), findsOneWidget);
    // Let the snackbar timer expire so the test ends clean.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Back on Home, and the card is gone — folders exist now.
    expect(find.byType(TidyFoldersScreen), findsNothing);
    expect(find.text('Tidy your items into folders'), findsNothing);

    // The commit, verified straight off the tables: Bakery and Drinks
    // (created in starter order), the merged Drinks group filed together,
    // and the skipped Cleaning item left in Unfiled — never guessed at.
    expect(await _liveFolderNames(h, tester), ['Bakery', 'Drinks']);
    expect(await _itemPlacements(h, tester), {
      'Cola': 'Drinks',
      'Fanta': 'Drinks',
      'Rolls': 'Bakery',
      'Dish soap': null,
    });
    await h.flushTimers(tester);
  });

  testWidgets('backing out of the tidy screen moves nothing', (tester) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedMigratedWorkspace(h, tester);

    await h.pumpApp(tester);
    await tester.tap(find.text('Tidy your items into folders'));
    await tester.pumpAndSettle();

    // Stage a mapping, then leave without confirming.
    await tester.tap(find.text('Drinks'));
    await tester.pumpAndSettle();
    await tester.tap(_inSheet('Drinks'));
    await tester.pumpAndSettle();
    expect(find.text('2 items · moves to Drinks'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    // No folder was created, no item was moved, and the card is still
    // there for next time.
    expect(await _liveFolderNames(h, tester), isEmpty);
    expect((await _itemPlacements(h, tester)).values, everyElement(isNull));
    expect(find.text('Tidy your items into folders'), findsOneWidget);
    await h.flushTimers(tester);
  });

  testWidgets('a skipped-everything tidy has nothing to confirm', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    // An item with no group at all: the screen says so and offers nothing
    // to move.
    await _seedItem(h, tester, 'Cash box', null);
    await _archiveStarterFolders(h, tester);

    await h.pumpApp(tester);
    await tester.tap(find.text('Tidy your items into folders'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('None of your items has a group'),
      findsOneWidget,
    );
    expect(find.textContaining('with no group'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Nothing to move yet'),
          )
          .onPressed,
      isNull,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });

  testWidgets('"Not now" hides the card for this session only', (tester) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedMigratedWorkspace(h, tester);

    await h.pumpApp(tester);
    expect(find.text('Tidy your items into folders'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Tidy your items into folders'), findsNothing);

    // Nothing was persisted: only the in-memory session flag hides it, so
    // the next launch shows the card again.
    expect(await _storedHiddenFlag(h, tester), isNull);
    expect(h.read(tidyPromptSessionDismissedProvider), isTrue);
  });

  testWidgets('"Don\'t show again" hides the card at once', (tester) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedMigratedWorkspace(h, tester);

    await h.pumpApp(tester);
    await tester.tap(find.text("Don't show again"));
    await tester.pump();
    // The hide travels write → table notification → watcher refetch →
    // provider → rebuild, and part of that chain hops through the real
    // event loop (the provider container is created outside the test's
    // fake-async zone). Zero-duration pumps never run real-zone work, so
    // give the real event loop one turn before settling — a bare delay
    // subscribes to nothing, which keeps drift's per-statement stream
    // cache out of the cross-zone entanglement described above.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tidy your items into folders'), findsNothing);
    // The card hides through the settings WATCHER — there is no in-memory
    // shortcut on this button — so its disappearance is itself proof the
    // row landed. The stored flag agrees, and the test below pins that it
    // also holds on the next launch.
    expect(await _storedHiddenFlag(h, tester), 'true');
  });

  testWidgets('a persisted hide flag keeps the card away next launch', (
    tester,
  ) async {
    _usePhoneSurface(tester);
    final h = await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    );
    addTearDown(h!.dispose);
    await _seedMigratedWorkspace(h, tester);
    // The row "Don't show again" wrote in a previous session, exactly as
    // TidyPromptCard persists it.
    await tester.runAsync(() async {
      final db = h.read(appDatabaseProvider);
      await db.customStatement(
        'INSERT OR REPLACE INTO settings (key, value, updated_at_micros) '
        "VALUES (?, 'true', 0)",
        [tidyPromptHiddenKey],
      );
    });

    await h.pumpApp(tester);

    // Migrated signature (items, no folders) — and still no card: the flag
    // outlives the session that set it. (Home leads with the item count
    // now, so that stat standing alone is the "nothing else to do" state.)
    expect(find.text('items on hand'), findsOneWidget);
    expect(find.text('Tidy your items into folders'), findsNothing);
  });
}
