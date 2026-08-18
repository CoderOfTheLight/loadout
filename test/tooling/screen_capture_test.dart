/// Design-review screen captures — NOT a behavioral test.
///
/// Pumps the real app through [AppHarness] over a realistic community-kitchen
/// dataset (seeded through the real services, per §11.3) and writes faithful
/// PNG renders of the key screens for the design lead to look at.
///
/// Output goes to `$LOADOUT_SCREENS_OUT` (or the session scratchpad default
/// below). Re-run with:
///
///     fvm flutter test test/tooling/screen_capture_test.dart
///
/// Frames are captured at iPhone-15-Pro geometry (393x852 logical, 3x) with
/// the SDK's real Roboto + MaterialIcons fonts loaded, so text renders as
/// glyphs rather than the FlutterTest box font.
@Timeout(Duration(minutes: 10))
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
import 'package:loadout/features/closeout/domain/closeout_form.dart';
import 'package:loadout/features/closeout/presentation/closeout_line_card.dart';
import 'package:loadout/features/events/domain/event.dart';
import 'package:loadout/features/inventory/application/inventory_service.dart';
import 'package:loadout/features/inventory/domain/movement.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';

import '../features/catalog/barcode_scan_support.dart'
    show FakeBarcodeScanService;
import '../support/app_harness.dart';

/// Where the PNGs land. Override with LOADOUT_SCREENS_OUT.
final String _outDir =
    Platform.environment['LOADOUT_SCREENS_OUT'] ??
    '/private/tmp/claude-501/-Users-lonegalixy-Desktop-flutter-demo/'
        '9ed42290-4643-4c31-8df3-8e43968faba9/scratchpad/screens';

/// Rendering caveats observed while capturing (overflows, exceptions).
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

/// Loads the SDK-bundled Roboto family and MaterialIcons so captures carry
/// real glyphs. `flutter test` sets FLUTTER_ROOT.
Future<void> _loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || root.isEmpty) {
    fail(
      'FLUTTER_ROOT is not set; run through `fvm flutter test` so the '
      'SDK material fonts can be loaded (renders are useless in the '
      'box-glyph test font).',
    );
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

/// Phone geometry: iPhone 15 Pro — 393x852 logical at 3x.
void _phoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

/// Renders the current frame to `<outDir>/<name>` the way golden capture
/// does: walk up from the app root to the nearest repaint boundary (the
/// root RenderView at the latest) and rasterize its layer.
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
  // RenderView paint bounds are already physical px; anything lower is
  // logical and needs the device pixel ratio applied.
  final physicalWidth = tester.view.physicalSize.width;
  final ratio = (bounds.width - physicalWidth).abs() < 1
      ? 1.0
      : tester.view.devicePixelRatio;
  await tester.runAsync(() async {
    final image = await layer.toImage(bounds, pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/$name')..createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    debugPrint(
      'CAPTURED $name (${image.width}x${image.height}) -> ${file.path}',
    );
    image.dispose();
  });
}

void _drainExceptions(WidgetTester tester, String context) {
  final e = tester.takeException();
  if (e != null) {
    _caveats.add('$context: $e');
    debugPrint('CAPTURE CAVEAT ($context): $e');
  }
}

Future<void> _goDark(WidgetTester tester) async {
  tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
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

/// Ids the capture tests navigate to.
final class KitchenIds {
  KitchenIds({
    required this.soupItemId,
    required this.activeEventId,
    required this.upcomingEventId,
    required this.soupRecipeId,
  });

  final String soupItemId;
  final String activeEventId;
  final String upcomingEventId;
  final String soupRecipeId;
}

/// A community kitchen feeding ~150 a night: folders, counted items with
/// prices, two closed-out past dinners (real history for the forecast),
/// one active dinner held yesterday (closeout pending), one planned dinner
/// this Friday with a generated packing list, and two batch recipes.
/// Everything goes through the real services, inside `tester.runAsync`.
Future<KitchenIds> _seedKitchen(AppHarness h, {String? waterBarcode}) async {
  // The harness names the workspace 'Test workspace'; give it the kitchen's
  // real name through the same preferences path the Settings screen uses.
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
      ),
      openingCount: Quantity.whole(count),
      barcode: barcode,
    ),
  );

  // Cooked on site.
  final soup = await item(
    'Chicken soup',
    folder: 'Cooked on site',
    count: 48,
    serves: 4,
    unitLabel: 'quarts',
    priceCents: 300, // what a quart costs to make — fills the edit form
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
  // Bought in.
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
  // Drinks.
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
  // Paper goods.
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
  // Cleaning.
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
  // Sales table.
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
  // Recipe ingredients.
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

  // ------------------------------------------- history: two closed dinners
  final events = h.read(eventServiceProvider);
  final closeout = h.read(closeoutServiceProvider);

  Future<void> pastDinner(
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
  final activeEventId = _ok(
    await events.createEvent(
      EventDraft(
        name: 'Saturday community dinner',
        scheduledDate: _date(now.subtract(const Duration(days: 1))),
        plannedExposure: 150,
        plannedItemIds: [soup, chips, water, plates],
      ),
    ),
  );
  _ok(await events.activate(activeEventId));

  // A restock delivery, so Recent activity has a receive row.
  _ok(
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
        plannedItemIds: [
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
        ],
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
        note:
            'Simmer 2 hours; stretch with extra stock when the line is '
            'long.',
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

  return KitchenIds(
    soupItemId: soup,
    activeEventId: activeEventId,
    upcomingEventId: upcomingEventId,
    soupRecipeId: soupRecipeId,
  );
}

// ----------------------------------------------------------------- tests

void main() {
  setUpAll(_loadRealFonts);

  tearDownAll(() {
    if (_caveats.isEmpty) {
      debugPrint('CAPTURE CAVEATS: none');
    } else {
      debugPrint('CAPTURE CAVEATS (${_caveats.length}):');
      for (final caveat in _caveats) {
        debugPrint('  - $caveat');
      }
    }
  });

  testWidgets('01 home (light + dark)', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    await tester.runAsync(() => _seedKitchen(h));

    await h.pumpApp(tester); // lands on /home
    await _snap(tester, '01-home-light.png');
    await _goDark(tester);
    await _snap(tester, '01-home-dark.png');
  });

  testWidgets('02 items list (light + dark)', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    await tester.runAsync(() => _seedKitchen(h));

    await h.pumpApp(tester);
    await h.go(tester, '/items');
    await _snap(tester, '02-items-light.png');
    await _goDark(tester);
    await _snap(tester, '02-items-dark.png');
  });

  testWidgets('03 item edit form (populated)', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    final ids = (await tester.runAsync(() => _seedKitchen(h)))!;

    await h.pumpApp(tester);
    await h.go(tester, '/items/${ids.soupItemId}/edit');
    await _snap(tester, '03-item-edit.png');
  });

  testWidgets('04 event detail (planned event with items)', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    final ids = (await tester.runAsync(() => _seedKitchen(h)))!;

    await h.pumpApp(tester);
    await h.go(tester, '/events/${ids.upcomingEventId}');
    await _snap(tester, '04-event-detail.png');
  });

  testWidgets('05 forecast review (persisted snapshot)', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    final ids = (await tester.runAsync(() => _seedKitchen(h)))!;

    await h.pumpApp(tester);
    await h.go(tester, '/events/${ids.upcomingEventId}/forecast');
    await _snap(tester, '05-forecast-review.png');
  });

  testWidgets('06 closeout (confirmed / in progress / skipped; light + dark)', (
    tester,
  ) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    final ids = (await tester.runAsync(() => _seedKitchen(h)))!;

    await h.pumpApp(tester);
    await h.go(tester, '/events/${ids.activeEventId}/closeout');

    Finder card(String itemName) => find.ancestor(
      of: find.text(itemName),
      matching: find.byType(CloseoutLineCard),
    );
    Finder inCard(String itemName, Finder matching) =>
        find.descendant(of: card(itemName), matching: matching);

    Future<void> tapIn(String itemName, Finder matching) async {
      final target = inCard(itemName, matching);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    // Chicken soup: worksheet, loaded 40, 6 left -> Confirmed (Used: 34).
    await tapIn('Chicken soup', find.textContaining('Worksheet ('));
    await tester.enterText(
      inCard('Chicken soup', find.widgetWithText(TextFormField, 'Loaded')),
      '40',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      inCard(
        'Chicken soup',
        find.widgetWithText(TextFormField, 'How many are left?'),
      ),
      '6',
    );
    await tester.pumpAndSettle();
    // Fold the completed worksheet away so the confirmed card is compact
    // and all three line states fit in the captured frame.
    await tapIn('Chicken soup', find.text('Hide worksheet'));

    // Tortilla chips: a loaded count only -> In progress.
    await tapIn(
      'Tortilla chips (party bag)',
      find.textContaining('Worksheet ('),
    );
    await tester.enterText(
      inCard(
        'Tortilla chips (party bag)',
        find.widgetWithText(TextFormField, 'Loaded'),
      ),
      '30',
    );
    await tester.pumpAndSettle();
    await tapIn('Tortilla chips (party bag)', find.text('Hide worksheet'));

    // Bottled water: deliberately skipped.
    await tapIn('Bottled water', find.text('Skip item'));

    // Flush the 500 ms draft autosave, then scroll back to the top.
    await tester.pump(const Duration(seconds: 1));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();

    await _snap(tester, '06-closeout-light.png');

    // A phone frame fits two cards; the skipped and pending cards sit below
    // the fold, so capture a scrolled companion frame showing them.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -560));
    await tester.pumpAndSettle();
    await _snap(tester, '06-closeout-light-scrolled.png');

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await _goDark(tester);
    await _snap(tester, '06-closeout-dark.png');
  });

  testWidgets('07 recipes list', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    await tester.runAsync(() => _seedKitchen(h));

    await h.pumpApp(tester);
    await h.go(tester, '/recipes');
    await _snap(tester, '07-recipes-list.png');
  });

  testWidgets('08 recipe edit form (populated)', (tester) async {
    _phoneView(tester);
    final h = await _startWorkspace(tester);
    final ids = (await tester.runAsync(() => _seedKitchen(h)))!;

    await h.pumpApp(tester);
    await h.go(tester, '/recipes/${ids.soupRecipeId}/revise');
    await _snap(tester, '08-recipe-edit.png');
  });

  testWidgets('09 scan items in (hub with a session row)', (tester) async {
    _phoneView(tester);
    // Scripted scanner: arriving on the hub scans a KNOWN barcode (Bottled
    // water), the restock sheet records 24, then the exhausted script
    // cancels the follow-up scan and lands back on the hub.
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

    await tester.enterText(
      find.byKey(const Key('scan-arrived-quantity')),
      '24',
    );
    await tester.tap(find.byKey(const Key('scan-add-next')));
    await tester.pumpAndSettle();

    // Let the confirmation snackbar expire so the hub reads clean.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _snap(tester, '09-scan-in-hub.png');
  });
}
