/// Design-review captures of the SUBPAGES — everything below the five
/// bottom-tab destinations. Sibling of `screen_capture_test.dart` (whose
/// font/geometry/rasterise approach this copies verbatim); that file covers
/// the tab roots, this one covers the forms, sheets, detail screens and
/// flows hanging off them.
///
/// NOT a behavioural test. Output goes to `$LOADOUT_SUBPAGES_OUT` (or the
/// session scratchpad default below). Re-run with:
///
///     fvm flutter test test/tooling/subpage_capture_test.dart
///
/// Frames are iPhone-15-Pro geometry (393x852 logical, 3x) with the SDK's
/// real Roboto + MaterialIcons loaded.
@Timeout(Duration(minutes: 25))
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/features/catalog/application/barcode_scan_service.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/catalog/presentation/tidy_folders_screen.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';
import 'package:loadout/features/closeout/presentation/closeout_line_card.dart';
import 'package:loadout/features/events/domain/event.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/movement.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';

import '../features/catalog/barcode_scan_support.dart'
    show FakeBarcodeScanService;
import '../support/app_harness.dart';

final String _outDir =
    Platform.environment['LOADOUT_SUBPAGES_OUT'] ??
    '/private/tmp/claude-501/-Users-lonegalixy-Desktop-flutter-demo/'
        '9ed42290-4643-4c31-8df3-8e43968faba9/scratchpad/subpages';

final List<String> _caveats = [];

T _ok<T>(Result<T> result) => result.fold(
  (value) => value,
  (error) => fail('seed failed: ${error.code}: ${error.message}'),
);

String _date(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

// --------------------------------------------------------------- fonts

Future<void> _loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || root.isEmpty) {
    fail('FLUTTER_ROOT is not set; run through `fvm flutter test`.');
  }
  final fontsDir = Directory('$root/bin/cache/artifacts/material_fonts');
  expect(
    fontsDir.existsSync(),
    isTrue,
    reason: 'expected SDK fonts at ${fontsDir.path}',
  );

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File('${fontsDir.path}/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Italic.ttf',
    'Roboto-Light.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

// --------------------------------------------------------------- capture

void _phoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

Future<void> _snap(WidgetTester tester, String name) async {
  await tester.pump();
  _drainExceptions(tester, 'before $name');
  final element = tester.element(find.byType(MaterialApp).first);
  RenderObject renderObject = element.renderObject!;
  while (!renderObject.isRepaintBoundary) {
    renderObject = renderObject.parent!;
  }
  final layer = renderObject.debugLayer! as OffsetLayer;
  final bounds = renderObject.paintBounds;
  final physicalWidth = tester.view.physicalSize.width;
  final ratio = (bounds.width - physicalWidth).abs() < 1
      ? 1.0
      : tester.view.devicePixelRatio;
  await tester.runAsync(() async {
    final image = await layer.toImage(bounds, pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/$name')..createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    debugPrint('CAPTURED $name (${image.width}x${image.height})');
    image.dispose();
  });
}

/// Scrolls the primary scrollable up by [dy] logical px and captures.
Future<void> _snapScrolled(
  WidgetTester tester,
  String name, {
  double dy = 620,
}) async {
  final scrollable = find.byType(Scrollable);
  if (scrollable.evaluate().isEmpty) {
    _caveats.add('$name: nothing scrollable');
    return;
  }
  await tester.drag(scrollable.first, Offset(0, -dy));
  await tester.pumpAndSettle();
  await _snap(tester, name);
}

void _drainExceptions(WidgetTester tester, String context) {
  final e = tester.takeException();
  if (e != null) {
    _caveats.add('$context: $e');
    debugPrint('CAPTURE CAVEAT ($context): $e');
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Future<AppHarness> _startWorkspace(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  final h = (await tester.runAsync(
    () => AppHarness.start(
      state: AppHarnessState.workspace,
      overrides: overrides,
    ),
  ))!;
  addTearDown(h.dispose);
  return h;
}

// --------------------------------------------------------------- seeding

final class KitchenIds {
  KitchenIds({
    required this.soupItemId,
    required this.waterItemId,
    required this.soapItemId,
    required this.activeEventId,
    required this.upcomingEventId,
    required this.pastEventId,
    required this.soupRecipeId,
    required this.unlinkedRecipeId,
    required this.receiveMovementId,
  });

  final String soupItemId;
  final String waterItemId;
  final String soapItemId;
  final String activeEventId;
  final String upcomingEventId;
  final String pastEventId;
  final String soupRecipeId;

  /// A recipe with NO output item — the only state that offers
  /// "Add to my items".
  final String unlinkedRecipeId;
  final String receiveMovementId;
}

/// Same community kitchen as `screen_capture_test.dart`, plus: a forecast
/// snapshot on the ACTIVE event (so the closeout carries "Planned load
/// was N" and the quick fills can complete a line), a 15-item load list on
/// it, a recipe with no output item, and three legacy-category unfiled
/// items so the tidy-folders flow has something to tidy.
Future<KitchenIds> _seedKitchen(AppHarness h, {String? waterBarcode}) async {
  await h
      .read(settingsServiceProvider)
      .updatePreferences(name: 'Elm Street Kitchen');

  final catalog = h.read(catalogServiceProvider);
  final folders = {
    for (final folder in await catalog.watchFolders().first)
      folder.name: folder.id.value,
  };

  Future<String> item(
    String name, {
    String? folder,
    int count = 0,
    int? priceCents,
    int? serves,
    String? unitLabel,
    int? usuallyBring,
    String? barcode,
    String? category,
    String notes = '',
  }) async => _ok(
    await catalog.createItem(
      ItemDraft(
        name: name,
        folderId: folder == null ? null : folders[folder],
        unitPrice: priceCents == null ? null : Money.fromCents(priceCents),
        servesPerUnit: serves == null ? null : Quantity.whole(serves),
        unitLabel: unitLabel,
        perEventBaseline: usuallyBring == null
            ? null
            : Quantity.whole(usuallyBring),
        category: category,
        notes: notes,
      ),
      openingCount: Quantity.whole(count),
      barcode: barcode,
    ),
  );

  final soup = await item(
    'Chicken soup',
    folder: 'Cooked on site',
    count: 48,
    serves: 4,
    unitLabel: 'quarts',
    priceCents: 300,
    notes: 'Freezer stock lives in the back chest freezer.',
  );
  final rice = await item(
    'Rice trays',
    folder: 'Cooked on site',
    count: 17,
    serves: 12,
    unitLabel: 'trays',
  );
  final chili = await item(
    'Beef chili',
    folder: 'Cooked on site',
    count: 10,
    serves: 4,
    unitLabel: 'quarts',
  );
  final chips = await item(
    'Tortilla chips (party bag)',
    folder: 'Bought ready to serve',
    count: 62,
    priceCents: 499,
  );
  final platters = await item(
    'Sandwich platters',
    folder: 'Bought ready to serve',
    count: 8,
    priceCents: 2200,
    serves: 10,
  );
  final water = await item(
    'Bottled water',
    folder: 'Drinks',
    count: 380,
    priceCents: 35,
    barcode: waterBarcode,
  );
  final lemonade = await item(
    'Lemonade (gallon)',
    folder: 'Drinks',
    count: 12,
    priceCents: 650,
    serves: 16,
  );
  final plates = await item(
    'Paper plates',
    folder: 'Disposables',
    count: 740,
    priceCents: 8,
  );
  final napkins = await item(
    'Napkins (pack of 250)',
    folder: 'Disposables',
    count: 10,
    priceCents: 399,
  );
  final cutlery = await item(
    'Cutlery packs',
    folder: 'Disposables',
    count: 665,
    priceCents: 5,
  );
  final soap = await item(
    'Dish soap',
    folder: 'Cleaning & setup',
    count: 6,
    priceCents: 349,
    usuallyBring: 2,
  );
  final bags = await item(
    'Trash bags (roll)',
    folder: 'Cleaning & setup',
    count: 13,
    priceCents: 899,
    usuallyBring: 4,
  );
  await item(
    'Nitrile gloves (box)',
    folder: 'Cleaning & setup',
    count: 5,
    priceCents: 999,
    usuallyBring: 2,
  );
  final cds = await item(
    'CDs',
    folder: 'Sales table',
    count: 47,
    priceCents: 1000,
  );
  final cookbooks = await item(
    'Cookbooks',
    folder: 'Sales table',
    count: 28,
    priceCents: 1500,
  );
  final totes = await item(
    'Tote bags',
    folder: 'Sales table',
    count: 30,
    priceCents: 1200,
  );
  final thighs = await item(
    'Chicken thighs (tray)',
    folder: 'Fresh produce',
    count: 12,
  );
  final onions = await item('Onions (bag)', folder: 'Fresh produce', count: 4);
  final carrots = await item(
    'Carrots (bag)',
    folder: 'Fresh produce',
    count: 4,
  );
  final celery = await item(
    'Celery (bunch)',
    folder: 'Fresh produce',
    count: 6,
  );
  await item('Dinner rolls (dozen)', folder: 'Bakery', count: 15);

  // Legacy-category, unfiled — the tidy-folders flow's raw material.
  await item('Coffee urn refills', count: 9, category: 'Drinks');
  await item('Sugar sachets (box)', count: 3, category: 'drinks');
  await item('Serving spoons', count: 24, category: 'Kitchen kit');

  // ------------------------------------------- history: two closed dinners
  final events = h.read(eventServiceProvider);
  final closeout = h.read(closeoutServiceProvider);

  Future<String> pastDinner(
    String name,
    String date,
    int planned,
    int confirmed,
    Map<String, int> depletions,
  ) async {
    final id = _ok(
      await events.createEvent(
        EventDraft(
          name: name,
          scheduledDate: date,
          plannedExposure: planned,
          plannedItemIds: depletions.keys.toList(),
        ),
      ),
    );
    _ok(await events.activate(id));
    _ok(
      await closeout.confirm(
        CloseoutFormDraft(
          eventId: id,
          confirmedExposure: confirmed,
          lines: [
            for (final entry in depletions.entries)
              CloseoutFormLine(
                itemId: entry.key,
                depletion: Quantity.whole(entry.value),
              ),
          ],
        ),
      ),
    );
    return id;
  }

  await pastDinner('Community dinner (Jul 24)', '2026-07-24', 140, 150, {
    soup: 14,
    rice: 5,
    chips: 18,
    water: 150,
    plates: 160,
    cutlery: 150,
    soap: 1,
    bags: 3,
    cds: 3,
    cookbooks: 2,
  });
  final pastEventId =
      await pastDinner('Community dinner (Aug 7)', '2026-08-07', 160, 165, {
        soup: 16,
        rice: 6,
        chips: 20,
        water: 170,
        plates: 180,
        cutlery: 165,
        soap: 1,
        bags: 4,
        cds: 4,
        cookbooks: 1,
      });

  // ------------------------------- yesterday's dinner: closeout pending
  final now = DateTime.now();
  final fullLoad = [
    soup,
    rice,
    chili,
    chips,
    platters,
    water,
    lemonade,
    plates,
    napkins,
    cutlery,
    soap,
    bags,
    cds,
    cookbooks,
    totes,
  ];
  final activeEventId = _ok(
    await events.createEvent(
      EventDraft(
        name: 'Saturday community dinner',
        scheduledDate: _date(now.subtract(const Duration(days: 1))),
        plannedExposure: 150,
        plannedItemIds: fullLoad,
      ),
    ),
  );
  _ok(await events.activate(activeEventId));
  // A packing list was generated before the night — so the closeout can
  // show "Planned load was N" and the quick fills can complete a line.
  _ok(await h.read(forecastServiceProvider).generateSnapshot(activeEventId));

  final receipt = _ok(
    await h
        .read(inventoryServiceProvider)
        .record(
          MovementFormDraft(
            itemId: water,
            kind: MovementKind.receive,
            quantity: Quantity.whole(120),
            note: 'Restock delivery',
          ),
        ),
  );

  // ------------------------ Friday's dinner, with a generated packing list
  final upcomingEventId = _ok(
    await events.createEvent(
      EventDraft(
        name: 'Friday community dinner',
        scheduledDate: _date(now.add(const Duration(days: 4))),
        plannedExposure: 150,
        plannedItemIds: fullLoad,
      ),
    ),
  );
  _ok(await h.read(forecastServiceProvider).generateSnapshot(upcomingEventId));

  // ----------------------------------------------------------- recipes
  final recipes = h.read(recipeServiceProvider);
  final soupRecipeId = _ok(
    await recipes.createRecipe(
      RecipeFormDraft(
        name: 'Chicken soup — big batch',
        outputItemId: soup,
        yieldQuantity: Quantity.whole(40),
        yieldLabel: 'quarts',
        note: 'Simmer 2 hours; stretch with extra stock when the line is long.',
        lines: [
          RecipeFormLine(itemId: thighs, quantityPerBatch: Quantity.whole(6)),
          RecipeFormLine(itemId: onions, quantityPerBatch: Quantity.whole(2)),
          RecipeFormLine(itemId: carrots, quantityPerBatch: Quantity.whole(2)),
          RecipeFormLine(itemId: celery, quantityPerBatch: Quantity.whole(3)),
          RecipeFormLine(
            name: 'Bay leaves',
            unitLabel: 'leaves',
            quantityPerBatch: Quantity.whole(4),
          ),
        ],
      ),
    ),
  );
  // A second revision, so the detail screen shows a real revision history.
  _ok(
    await recipes.reviseRecipe(
      recipeId: soupRecipeId,
      draft: RecipeFormDraft(
        name: 'Chicken soup — big batch',
        outputItemId: soup,
        yieldQuantity: Quantity.whole(44),
        yieldLabel: 'quarts',
        note: 'More stock, one extra tray of thighs — Aug 7 ran short.',
        lines: [
          RecipeFormLine(itemId: thighs, quantityPerBatch: Quantity.whole(7)),
          RecipeFormLine(itemId: onions, quantityPerBatch: Quantity.whole(2)),
          RecipeFormLine(itemId: carrots, quantityPerBatch: Quantity.whole(2)),
          RecipeFormLine(itemId: celery, quantityPerBatch: Quantity.whole(3)),
          RecipeFormLine(
            name: 'Bay leaves',
            unitLabel: 'leaves',
            quantityPerBatch: Quantity.whole(4),
          ),
        ],
      ),
    ),
  );
  _ok(
    await recipes.createRecipe(
      RecipeFormDraft(
        name: 'Beef chili — big batch',
        outputItemId: chili,
        yieldQuantity: Quantity.whole(30),
        yieldLabel: 'quarts',
        note: 'Freezes well; make double when beef is on offer.',
        lines: [
          RecipeFormLine(itemId: onions, quantityPerBatch: Quantity.whole(3)),
          RecipeFormLine(
            name: 'Ground beef',
            unitLabel: 'lb',
            quantityPerBatch: Quantity.whole(20),
          ),
          RecipeFormLine(
            name: 'Kidney beans (cans)',
            quantityPerBatch: Quantity.whole(12),
          ),
        ],
      ),
    ),
  );
  // No output item: the only state that offers "Add to my items".
  final unlinkedRecipeId = _ok(
    await recipes.createRecipe(
      RecipeFormDraft(
        name: 'Cornbread — sheet pan',
        yieldQuantity: Quantity.whole(24),
        yieldLabel: 'squares',
        note: 'Bake at 200C for 25 minutes. Doubles fine.',
        lines: [
          RecipeFormLine(itemId: onions, quantityPerBatch: Quantity.whole(1)),
          RecipeFormLine(
            name: 'Cornmeal',
            unitLabel: 'cups',
            quantityPerBatch: Quantity.whole(6),
          ),
          RecipeFormLine(
            name: 'Buttermilk',
            unitLabel: 'quarts',
            quantityPerBatch: Quantity.whole(2),
          ),
          RecipeFormLine(name: 'Eggs', quantityPerBatch: Quantity.whole(8)),
        ],
      ),
    ),
  );

  return KitchenIds(
    soupItemId: soup,
    waterItemId: water,
    soapItemId: soap,
    activeEventId: activeEventId,
    upcomingEventId: upcomingEventId,
    pastEventId: pastEventId,
    soupRecipeId: soupRecipeId,
    unlinkedRecipeId: unlinkedRecipeId,
    receiveMovementId: receipt.createdRecordIds.first,
  );
}

// ----------------------------------------------------------------- tests

void main() {
  setUpAll(_loadRealFonts);

  tearDownAll(() {
    if (_caveats.isEmpty) {
      debugPrint('SUBPAGE CAPTURE CAVEATS: none');
    } else {
      debugPrint('SUBPAGE CAPTURE CAVEATS (${_caveats.length}):');
      for (final caveat in _caveats) {
        debugPrint('  - $caveat');
      }
    }
  });

  // ------------------------------------------------------------- items

  testWidgets('A items: new / edit / detail / folder picker', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    final ids = (await tester.runAsync(() => _seedKitchen(h)))!;
    await h.pumpApp(tester);

    await h.go(tester, '/items/new');
    await _snap(tester, 'A1-item-new-top.png');
    await _snapScrolled(tester, 'A2-item-new-mid.png');
    await _snapScrolled(tester, 'A3-item-new-bottom.png');

    // The folder pick-list, opened from the form's Folder field.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Unfiled'));
    await _snap(tester, 'A4-folder-picker-sheet.png');
    await tester.tapAt(const Offset(200, 40)); // dismiss
    await tester.pumpAndSettle();

    await h.go(tester, '/items/${ids.soupItemId}/edit');
    await _snap(tester, 'A5-item-edit-top.png');
    await _snapScrolled(tester, 'A6-item-edit-mid.png');
    await _snapScrolled(tester, 'A7-item-edit-bottom.png');

    await h.go(tester, '/items/${ids.soupItemId}');
    await _snap(tester, 'A8-item-detail-top.png');
    await _snapScrolled(tester, 'A9-item-detail-history.png');
  });

  testWidgets('B movements: purchase / count / item picker / correction', (
    tester,
  ) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    final ids = (await tester.runAsync(() => _seedKitchen(h)))!;
    await h.pumpApp(tester);

    await h.go(tester, '/movements/new');
    await _snap(tester, 'B1-movement-new-purchase.png');

    // The searchable item picker.
    await _tap(tester, find.byType(InputDecorator).first);
    await _snap(tester, 'B2-item-picker-sheet.png');
    await _tap(tester, find.text('Chicken soup'));
    await _snap(tester, 'B3-movement-new-purchase-filled.png');

    // Record a count — the volunteer's most common ledger entry. Leave the
    // route first: go_router reuses the page when only the query changes.
    await h.go(tester, '/items');
    await h.go(tester, '/movements/new?kind=count&itemId=${ids.soupItemId}');
    await _snap(tester, 'B4-record-count-empty.png');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'How many did you count?'),
      '41',
    );
    await tester.pumpAndSettle();
    await _snap(tester, 'B5-record-count-typed.png');

    // Waste (the only kind with the event field).
    await h.go(tester, '/items');
    await h.go(tester, '/movements/new?kind=waste&itemId=${ids.soupItemId}');
    await _snap(tester, 'B6-movement-new-waste.png');

    await h.go(tester, '/movements/${ids.receiveMovementId}');
    await _snap(tester, 'B7-movement-detail.png');

    await h.go(tester, '/movements/${ids.receiveMovementId}/correct');
    await _snap(tester, 'B8-correction.png');

    await h.go(tester, '/activity');
    await _snap(tester, 'B9-activity.png');
  });

  testWidgets('C folders: manage + tidy', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    await tester.runAsync(() => _seedKitchen(h));
    await h.pumpApp(tester);

    await h.go(tester, '/items');
    await _tap(
      tester,
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await _snap(tester, 'C1-items-overflow-menu.png');
    await _tap(tester, find.text('Manage folders'));
    await _snap(tester, 'C2-folder-management.png');
    await _snapScrolled(tester, 'C3-folder-management-bottom.png', dy: 400);
  });

  testWidgets('C4 tidy folders', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    await tester.runAsync(() => _seedKitchen(h));
    await h.pumpApp(tester);
    // Only entry point is the home prompt, which needs an empty folders
    // table; pump it directly instead.
    await h.pumpScreen(tester, const TidyFoldersScreen());
    await _snap(tester, 'C4-tidy-folders.png');
    await _snapScrolled(tester, 'C5-tidy-folders-bottom.png', dy: 400);
  });

  // ------------------------------------------------------------ events

  testWidgets('D events: new / edit / pickers / detail', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    final ids = (await tester.runAsync(() => _seedKitchen(h)))!;
    await h.pumpApp(tester);

    await h.go(tester, '/events/new');
    await _snap(tester, 'D1-event-new-top.png');
    await _snapScrolled(tester, 'D2-event-new-bottom.png', dy: 400);

    await h.go(tester, '/events/${ids.upcomingEventId}/edit');
    await _snap(tester, 'D3-event-edit-top.png');
    await _snapScrolled(tester, 'D4-event-edit-chips.png', dy: 400);

    await _tap(tester, find.widgetWithText(OutlinedButton, 'Add items'));
    await _snap(tester, 'D5-planned-items-picker-top.png');
    await _snapScrolled(tester, 'D6-planned-items-picker-mid.png', dy: 400);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();

    await _tap(
      tester,
      find.widgetWithText(OutlinedButton, 'Copy items from a previous event'),
    );
    await _snap(tester, 'D7-previous-event-picker.png');
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();

    await h.go(tester, '/events/${ids.upcomingEventId}');
    await _snap(tester, 'D8-event-detail-top.png');
    await _snapScrolled(tester, 'D9-event-detail-bottom.png', dy: 500);
  });

  testWidgets('E forecast: review + line detail', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    final ids = (await tester.runAsync(() => _seedKitchen(h)))!;
    await h.pumpApp(tester);

    await h.go(tester, '/events/${ids.upcomingEventId}/forecast');
    await _snap(tester, 'E1-forecast-review-top.png');
    await _snapScrolled(tester, 'E2-forecast-review-mid.png', dy: 500);
    await _snapScrolled(tester, 'E3-forecast-review-lower.png', dy: 500);

    await h.go(
      tester,
      '/events/${ids.upcomingEventId}/forecast/${ids.soupItemId}',
    );
    await _snap(tester, 'E4-forecast-line-detail-top.png');
    await _snapScrolled(tester, 'E5-forecast-line-detail-mid.png', dy: 500);
    await _snapScrolled(tester, 'E6-forecast-line-detail-bottom.png', dy: 500);
  });

  testWidgets('F closeout: fresh / part done / confirm sheet', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    final ids = (await tester.runAsync(() => _seedKitchen(h)))!;
    await h.pumpApp(tester);

    await h.go(tester, '/events/${ids.activeEventId}/closeout');
    await _snap(tester, 'F1-closeout-fresh-top.png');
    await _snapScrolled(tester, 'F2-closeout-fresh-cards.png', dy: 500);

    Finder card(String itemName) => find.ancestor(
      of: find.text(itemName),
      matching: find.byType(CloseoutLineCard),
    );
    Finder inCard(String itemName, Finder matching) =>
        find.descendant(of: card(itemName), matching: matching);

    Future<void> tapIn(String itemName, Finder matching) =>
        _tap(tester, inCard(itemName, matching));

    // The card list builds lazily now, so a card has to be scrolled into
    // range before it can be found at all.
    Future<void> reveal(String itemName) async {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 6000));
      await tester.pumpAndSettle();
      final target = find.text(itemName);
      if (target.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          target,
          200,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.ensureVisible(target.first);
      await tester.pumpAndSettle();
    }

    Future<void> typeIn(String itemName, String label, String value) async {
      await reveal(itemName);
      final field = inCard(itemName, find.widgetWithText(TextFormField, label));
      await tester.ensureVisible(field.first);
      await tester.pumpAndSettle();
      await tester.enterText(field.first, value);
      await tester.pumpAndSettle();
    }

    // One line counted the ordinary way: two boxes, no disclosure.
    await typeIn('Chicken soup', 'Loaded', '40');
    await typeIn('Chicken soup', 'Left', '6');
    await _snap(tester, 'F3-closeout-card-counted.png');

    // A second line left mid-entry, a third skipped.
    await typeIn('Rice trays', 'Loaded', '9');
    await reveal('Beef chili');
    await tapIn('Beef chili', find.text('Skip'));
    await tester.pump(const Duration(seconds: 1));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
    await tester.pumpAndSettle();
    await _snap(tester, 'F4-closeout-part-done-top.png');
    await _snapScrolled(tester, 'F5-closeout-part-done-cards.png', dy: 500);
    await _snapScrolled(tester, 'F6-closeout-part-done-more.png', dy: 700);

    // Fill everything else with the quick fills so the confirm sheet opens.
    // The list builds lazily, so walk it from the top tapping whatever is
    // on screen rather than enumerating the (few) built cards.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 6000));
    await tester.pumpAndSettle();
    for (var step = 0; step < 80; step++) {
      final chip = find.text('Everything left');
      if (chip.evaluate().isNotEmpty) {
        await _tap(tester, chip.first);
        continue;
      }
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 6000));
    await tester.pumpAndSettle();
    final exposure = find.byType(TextFormField).first;
    await tester.ensureVisible(exposure);
    await tester.pumpAndSettle();
    await tester.enterText(exposure, '148');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 6000));
    await tester.pumpAndSettle();
    await _snap(tester, 'F7-closeout-nearly-done.png');

    final confirm = find.widgetWithText(FilledButton, 'Finish closeout');
    if (tester.widget<FilledButton>(confirm.first).onPressed != null) {
      await _tap(tester, confirm);
      await _snap(tester, 'F8-closeout-confirm-sheet.png');
    } else {
      _caveats.add(
        'F8: Finish closeout still disabled — some line unfinished; '
        'confirm sheet not captured',
      );
    }
  });

  testWidgets('G closeout report', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    final ids = (await tester.runAsync(() => _seedKitchen(h)))!;
    await h.pumpApp(tester);

    await h.go(tester, '/events/${ids.pastEventId}/closeout/report');
    await _snap(tester, 'G1-closeout-report-top.png');
    await _snapScrolled(tester, 'G2-closeout-report-mid.png', dy: 500);
    await _snapScrolled(tester, 'G3-closeout-report-bottom.png', dy: 500);
  });

  // ----------------------------------------------------------- recipes

  testWidgets('H recipes: new / revise / detail / sheets', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    final ids = (await tester.runAsync(() => _seedKitchen(h)))!;
    await h.pumpApp(tester);

    await h.go(tester, '/recipes/new');
    await _snap(tester, 'H1-recipe-new.png');

    // Paste ingredients: input stage, then the review stage.
    await _tap(tester, find.byKey(const Key('paste-ingredients')));
    await _snap(tester, 'H2-paste-input.png');
    await tester.enterText(
      find.byKey(const Key('paste-input')),
      '6 trays chicken thighs\n2 bags onions\n2 bags carrots\n'
      '3 bunches celery\n4 bay leaves\n1 1/2 cups salt\nCDs',
    );
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('paste-review')));
    await _snap(tester, 'H3-paste-review.png');
    await _snapScrolled(tester, 'H4-paste-review-bottom.png', dy: 300);
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();

    await h.go(tester, '/recipes/${ids.soupRecipeId}/revise');
    await _snap(tester, 'H5-recipe-revise-top.png');
    await _snapScrolled(tester, 'H6-recipe-revise-lines.png', dy: 400);
    await _snapScrolled(tester, 'H7-recipe-revise-more.png', dy: 400);

    await h.go(tester, '/recipes/${ids.soupRecipeId}');
    await _snap(tester, 'H8-recipe-detail-top.png');
    await _snapScrolled(tester, 'H9-recipe-detail-bottom.png', dy: 500);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('scale-to-event')));
    await _snap(tester, 'H10-recipe-scale-sheet.png');
    await tester.tapAt(const Offset(200, 20));
    await tester.pumpAndSettle();

    await h.go(tester, '/recipes/${ids.unlinkedRecipeId}');
    await _tap(tester, find.byKey(const Key('add-to-items')));
    await _snap(tester, 'H11-add-to-items-sheet.png');
    await _snapScrolled(tester, 'H12-add-to-items-sheet-bottom.png', dy: 300);
  });

  // -------------------------------------------------------------- scan

  testWidgets('I scan items in: hub + known sheet', (tester) async {
    _phoneView(tester);
    final fake = FakeBarcodeScanService(
      available: true,
      script: [const BarcodeScan(payload: '5000112637922', symbology: 'ean13')],
    );
    final h = await _startWorkspace(
      tester,
      overrides: [barcodeScanServiceProvider.overrideWithValue(fake)],
    );
    await tester.runAsync(() => _seedKitchen(h, waterBarcode: '5000112637922'));
    await h.pumpApp(tester);
    await h.go(tester, '/items/scan-in');

    // Arriving auto-scans the known barcode: the restock sheet is up.
    await _snap(tester, 'I1-scan-known-item-sheet.png');
    await tester.enterText(
      find.byKey(const Key('scan-arrived-quantity')),
      '24',
    );
    await tester.pumpAndSettle();
    await _snap(tester, 'I2-scan-known-item-sheet-typed.png');
    await _tap(tester, find.byKey(const Key('scan-add-next')));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _snap(tester, 'I3-scan-hub-with-session.png');
  });

  testWidgets('I4 scan items in: unknown barcode sheet', (tester) async {
    _phoneView(tester);
    final fake = FakeBarcodeScanService(
      available: true,
      script: [const BarcodeScan(payload: '8712345678904', symbology: 'ean13')],
    );
    final h = await _startWorkspace(
      tester,
      overrides: [barcodeScanServiceProvider.overrideWithValue(fake)],
    );
    await tester.runAsync(() => _seedKitchen(h));
    await h.pumpApp(tester);
    await h.go(tester, '/items/scan-in');
    await _snap(tester, 'I4-scan-new-item-sheet.png');
    await _snapScrolled(tester, 'I5-scan-new-item-sheet-bottom.png', dy: 250);
  });

  // ---------------------------------------------------------- settings

  testWidgets('J settings / backup / restore', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    await tester.runAsync(() => _seedKitchen(h));
    await h.pumpApp(tester);

    await h.go(tester, '/settings');
    await _snap(tester, 'J1-settings-top.png');
    await _snapScrolled(tester, 'J2-settings-mid.png', dy: 500);
    await _snapScrolled(tester, 'J3-settings-bottom.png', dy: 500);

    await h.go(tester, '/settings/backup');
    await _snap(tester, 'J4-backup.png');
    await _snapScrolled(tester, 'J5-backup-bottom.png', dy: 350);

    await h.go(tester, '/settings/restore');
    await _snap(tester, 'J6-restore.png');
    await _snapScrolled(tester, 'J7-restore-bottom.png', dy: 350);
  });
}
