/// README demo GIFs — NOT a behavioural test.
///
/// Drives three real flows through [AppHarness] over a seeded
/// community-kitchen workspace, rasterises a frame after every meaningful
/// step, downsamples to README width and encodes an animated GIF (plus a
/// still PNG fallback) per flow.
///
/// A scripted widget test rather than a simulator recording on purpose:
/// deterministic frames, no cursor, no status-bar clock, exact framing, and
/// re-runnable from a single command.
///
/// ## Regenerate
///
///     LOADOUT_GIFS=1 fvm flutter test test/tooling/gif_capture_test.dart
///
/// Without `LOADOUT_GIFS` (or `LOADOUT_GIFS_OUT=<dir>`) every test here is
/// SKIPPED, so an ordinary `fvm flutter test` neither pays for the encode
/// nor writes into the repo. `LOADOUT_GIFS=1` writes to `docs/media`;
/// `LOADOUT_GIFS_OUT` overrides the directory. `LOADOUT_GIF_FRAMES=1`
/// additionally dumps every source frame as a numbered PNG next to the GIF,
/// for eyeballing what the encoder was given.
///
/// Frames are captured at iPhone-15-Pro geometry (393x852 logical) at 2x and
/// box-downsampled to [_gifWidth], with the SDK's real Roboto +
/// MaterialIcons loaded so text renders as glyphs rather than the
/// FlutterTest box font. Light theme throughout — the app's default.
@Timeout(Duration(minutes: 30))
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/money.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/core/result.dart';
import 'package:loadout/features/catalog/domain/item.dart';
import 'package:loadout/features/closeout/domain/closeout_form.dart';
import 'package:loadout/features/closeout/presentation/closeout_line_card.dart';
import 'package:loadout/features/events/domain/event.dart';

import '../support/app_harness.dart';

// ------------------------------------------------------------------ output

/// Where the GIFs land, or null when this file should not write at all.
///
/// `LOADOUT_GIFS_OUT` wins; `LOADOUT_GIFS` opts in at the repo default.
final String? _outDir = () {
  final explicit = Platform.environment['LOADOUT_GIFS_OUT']?.trim();
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final enabled = Platform.environment['LOADOUT_GIFS']?.trim();
  if (enabled != null && enabled.isNotEmpty) return 'docs/media';
  return null;
}();

/// Reason string for `skip:` — non-null keeps these out of a normal run.
final String? _skip = _outDir == null
    ? 'README GIF capture: set LOADOUT_GIFS=1 (or LOADOUT_GIFS_OUT=<dir>)'
    : null;

final bool _dumpFrames =
    (Platform.environment['LOADOUT_GIF_FRAMES']?.trim() ?? '').isNotEmpty;

// ------------------------------------------------------------ gif geometry

/// README width. The phone is 393 logical px wide, so this is a 0.865
/// downsample of a 2x raster — small enough for a README, big enough to read.
const int _gifWidth = 340;

/// How long an ordinary step is held, in centiseconds (GIF's own unit).
const int _stepCentis = 95;

/// The closing frame of each loop, held long enough to read before it wraps.
const int _endCentis = 230;

/// Palette size per frame. Flat Material surfaces quantise cleanly well
/// below 256, and fewer indices compress a lot better under LZW.
const int _gifColors = 96;

// ----------------------------------------------------------------- helpers

/// Rendering caveats observed while capturing.
final List<String> _caveats = [];

T _ok<T>(Result<T> result) => result.fold(
  (value) => value,
  (error) => fail('seed failed: ${error.code}: ${error.message}'),
);

String _date(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Loads the SDK-bundled Roboto family and MaterialIcons so captures carry
/// real glyphs. `flutter test` sets FLUTTER_ROOT.
Future<void> _loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || root.isEmpty) {
    fail(
      'FLUTTER_ROOT is not set; run through `fvm flutter test` so the SDK '
      'material fonts can be loaded (renders are useless in the box-glyph '
      'test font).',
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

/// Phone geometry: iPhone 15 Pro — 393x852 logical. Captured at 2x and
/// downsampled rather than at 1x, so glyph edges survive the resize.
void _phoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(786, 1704);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

void _drainExceptions(WidgetTester tester, String context) {
  final e = tester.takeException();
  if (e != null) {
    _caveats.add('$context: $e');
    debugPrint('GIF CAPTURE CAVEAT ($context): $e');
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Future<AppHarness> _startWorkspace(WidgetTester tester) async {
  final h = (await tester.runAsync(
    () => AppHarness.start(state: AppHarnessState.workspace),
  ))!;
  addTearDown(h.dispose);
  return h;
}

/// Cheap sampled FNV-1a over a frame's pixels — enough to tell two rendered
/// steps apart without holding a second copy of every frame.
int _fingerprint(img.Image frame) {
  final bytes = frame.getBytes();
  var hash = 0x811c9dc5;
  for (var i = 0; i < bytes.length; i += 97) {
    hash = ((hash ^ bytes[i]) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

// -------------------------------------------------------------------- reel

/// A flow's frames, held in memory until the whole loop is captured.
final class _Reel {
  _Reel(this.name);

  /// Basename, without extension: `add-item` -> `add-item.gif` + `.png`.
  final String name;

  final List<img.Image> frames = [];
  final List<int> holds = [];

  void add(img.Image frame, int hold) {
    frames.add(frame);
    holds.add(hold);
  }

  /// Rasterises the current frame the way golden capture does — walk up from
  /// the app root to the nearest repaint boundary and rasterise its layer —
  /// then box-downsamples it to [_gifWidth] and stores it.
  Future<void> shoot(
    WidgetTester tester, {
    int hold = _stepCentis,
    bool last = false,
  }) async {
    await tester.pump();
    _drainExceptions(tester, '$name frame ${frames.length}');
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
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final rgba = Uint8List.fromList(
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final full = img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: rgba.buffer,
        numChannels: 4,
      );
      // Screens are opaque, so dropping alpha loses nothing and keeps the
      // quantiser off a channel it would only waste palette entries on.
      final small = img
          .copyResize(
            full,
            width: _gifWidth,
            interpolation: img.Interpolation.average,
          )
          .convert(numChannels: 3);
      add(small, last ? _endCentis : hold);
      image.dispose();
    });
  }

  /// Encodes the reel, writes `<name>.gif` + `<name>.png`, then reads the
  /// GIF back and asserts it is a real multi-frame animation.
  void write() {
    expect(
      frames.length,
      greaterThan(1),
      reason: '$name captured no animation',
    );
    final dir = Directory(_outDir!)..createSync(recursive: true);

    final encoder = img.GifEncoder(
      repeat: 0, // loop forever
      numColors: _gifColors,
      quantizerType: img.QuantizerType.octree,
      // Flat UI panels band far less than a photo would, and dithering
      // sprays per-pixel noise that both looks wrong and doubles the file.
      dither: img.DitherKernel.none,
    );
    for (var i = 0; i < frames.length; i++) {
      encoder.addFrame(frames[i], duration: holds[i]);
    }
    final bytes = encoder.finish()!;
    final gif = File('${dir.path}/$name.gif')..writeAsBytesSync(bytes);

    // Still fallback at the same size, for renderers that do not animate.
    final still = File('${dir.path}/$name.png')
      ..writeAsBytesSync(img.encodePng(frames.last));

    // ------------------------------------------------- read it back
    final decoded = img.decodeGif(bytes);
    expect(decoded, isNotNull, reason: '$name.gif does not parse');
    expect(decoded!.numFrames, frames.length, reason: '$name frame count');
    expect(decoded.numFrames, greaterThan(1));
    expect(decoded.width, _gifWidth);
    expect(decoded.height, frames.first.height);
    expect(decoded.loopCount, 0, reason: '$name must loop forever');
    for (var i = 0; i < decoded.numFrames; i++) {
      expect(
        decoded.frames[i].frameDuration,
        holds[i] * 10,
        reason: '$name frame $i duration (ms)',
      );
    }
    expect(bytes.length, lessThan(2 * 1024 * 1024), reason: '$name over 2 MB');
    // A GIF whose every frame is identical is technically valid and useless:
    // no step of the flow would have landed on screen.
    final seen = <int>{};
    for (final frame in decoded.frames) {
      expect(
        seen.add(_fingerprint(frame)),
        isTrue,
        reason: '$name has duplicate frames — a step did not render',
      );
    }

    if (_dumpFrames) {
      for (var i = 0; i < frames.length; i++) {
        File(
          '${dir.path}/$name-frame-${i.toString().padLeft(2, '0')}.png',
        ).writeAsBytesSync(img.encodePng(frames[i]));
        // The decoded frame is what a viewer actually shows: post-palette,
        // post-LZW. Dumped so the quantised result can be eyeballed too.
        File(
          '${dir.path}/$name-gif-${i.toString().padLeft(2, '0')}.png',
        ).writeAsBytesSync(
          img.encodePng(decoded.frames[i].convert(numChannels: 3)),
        );
      }
    }

    debugPrint(
      'GIF $name.gif  ${decoded.width}x${decoded.height}  '
      '${frames.length} frames  ${bytes.length} bytes  '
      '${holds.join('/')} centis -> ${gif.path}',
    );
    debugPrint('STILL $name.png  ${still.lengthSync()} bytes');
  }
}

// ----------------------------------------------------------------- seeding

/// Ids the flows navigate to.
final class _KitchenIds {
  _KitchenIds({required this.activeEventId, required this.upcomingEventId});

  final String activeEventId;
  final String upcomingEventId;
}

/// A community kitchen feeding ~150 a night: the eight starter folders with
/// priced counted items, two closed-out past dinners (real history, so the
/// cost prediction has something to say), one dinner held yesterday whose
/// closeout is pending, and one planned for Friday with a generated packing
/// list. Everything goes through the real services.
///
/// Deliberately WITHOUT a "Chicken soup" item: `add-item.gif` creates one,
/// and the catalog rejects a duplicate name.
Future<_KitchenIds> _seedKitchen(AppHarness h) async {
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
    ),
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
    // Comfortably above what the two past dinners take back out of it — a
    // negative on-hand would put a red "Negative" warning in frame one.
    count: 62,
    serves: 4,
    unitLabel: 'quarts',
    priceCents: 300,
  );
  await item(
    'Sandwich platters',
    folder: 'Bought ready to serve',
    count: 8,
    priceCents: 2200,
    serves: 10,
  );
  final chips = await item(
    'Tortilla chips (party bag)',
    folder: 'Bought ready to serve',
    count: 62,
    priceCents: 499,
  );
  final water = await item(
    'Bottled water',
    folder: 'Drinks',
    count: 380,
    priceCents: 35,
  );
  await item(
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
  final cutlery = await item(
    'Cutlery packs',
    folder: 'Disposables',
    count: 665,
    priceCents: 5,
  );
  await item(
    'Napkins (pack of 250)',
    folder: 'Disposables',
    count: 10,
    priceCents: 399,
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
  final cookbooks = await item(
    'Cookbooks',
    folder: 'Sales table',
    count: 28,
    priceCents: 1500,
  );
  await item('Tote bags', folder: 'Sales table', count: 30, priceCents: 1200);
  // One unfiled row, so the Unfiled section exists before anything is added.
  await item('Dinner rolls (dozen)', count: 15);

  // ------------------------------------------- history: two closed dinners
  final events = h.read(eventServiceProvider);
  final closeout = h.read(closeoutServiceProvider);
  final forecast = h.read(forecastServiceProvider);

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
    chili: 14,
    rice: 5,
    chips: 18,
    water: 150,
    plates: 160,
    cutlery: 150,
    soap: 1,
    bags: 3,
    cookbooks: 2,
  });
  await pastDinner('Community dinner (Aug 7)', '2026-08-07', 160, 165, {
    chili: 16,
    rice: 6,
    chips: 20,
    water: 170,
    plates: 180,
    cutlery: 165,
    soap: 1,
    bags: 4,
    cookbooks: 1,
  });

  // ---------------------- yesterday's dinner: four lines, closeout pending
  final now = DateTime.now();
  final activeEventId = _ok(
    await events.createEvent(
      EventDraft(
        name: 'Saturday community dinner',
        scheduledDate: _date(now.subtract(const Duration(days: 1))),
        plannedExposure: 150,
        plannedItemIds: [chili, chips, water, plates],
      ),
    ),
  );
  // Snapshot BEFORE activating: the closeout cards read their "loaded" from
  // the packing list, which is what makes 'All gone' a one-tap answer.
  _ok(await forecast.generateSnapshot(activeEventId));
  _ok(await events.activate(activeEventId));

  // ---------------- Friday's dinner: a short priced list and a packing list
  final upcomingEventId = _ok(
    await events.createEvent(
      EventDraft(
        name: 'Friday community dinner',
        scheduledDate: _date(now.add(const Duration(days: 4))),
        plannedExposure: 150,
        plannedItemIds: [chips, water, plates, cutlery],
      ),
    ),
  );
  _ok(await forecast.generateSnapshot(upcomingEventId));

  return _KitchenIds(
    activeEventId: activeEventId,
    upcomingEventId: upcomingEventId,
  );
}

// ------------------------------------------------------------------- flows

void main() {
  group('README GIF capture', () {
    setUpAll(_loadRealFonts);

    tearDownAll(() {
      if (_caveats.isEmpty) {
        debugPrint('GIF CAPTURE CAVEATS: none');
      } else {
        debugPrint('GIF CAPTURE CAVEATS (${_caveats.length}):');
        for (final caveat in _caveats) {
          debugPrint('  - $caveat');
        }
      }
    });

    // ---------------------------------------------------------- add-item.gif

    testWidgets('add-item.gif — the four-field form, start to finished row', (
      tester,
    ) async {
      _phoneView(tester);
      final h = await _startWorkspace(tester);
      await tester.runAsync(() => _seedKitchen(h));
      await h.pumpApp(tester);
      final reel = _Reel('add-item');

      // 1. The items list, folder sections and all.
      await h.go(tester, '/items');
      await reel.shoot(tester, hold: 110);

      // 2. The FAB pushes the form (a push, so saving pops straight back).
      await _tap(tester, find.byType(FloatingActionButton));
      expect(find.widgetWithText(FilledButton, 'Add item'), findsOneWidget);
      await reel.shoot(tester);

      // 3. Name.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Item name'),
        'Chicken soup',
      );
      await tester.pumpAndSettle();
      await reel.shoot(tester);

      // 4. How many, and what to call them.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'How many do you have?'),
        '18',
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('unit-label')), 'quarts');
      await tester.pumpAndSettle();
      await reel.shoot(tester, hold: 110);

      // 5. Folder — the fourth field, and the reason the new row lands where
      //    the loop started rather than at the bottom under Unfiled.
      await _tap(tester, find.widgetWithText(InputDecorator, 'Folder'));
      expect(find.text('Cooked on site'), findsWidgets);
      await reel.shoot(tester);
      await _tap(tester, find.text('Cooked on site'));
      await reel.shoot(tester);

      // 6. Save; the form pops back to the list.
      await _tap(tester, find.widgetWithText(FilledButton, 'Add item'));
      await tester.pumpAndSettle();
      await h.flushTimers(tester);

      // 7. The new row, in the same viewport the loop opened on.
      expect(find.text('Chicken soup'), findsWidgets);
      await reel.shoot(tester, last: true);

      reel.write();
    });

    // ---------------------------------------------------------- closeout.gif

    testWidgets('closeout.gif — one question per card, progress advancing', (
      tester,
    ) async {
      _phoneView(tester);
      final h = await _startWorkspace(tester);
      final ids = (await tester.runAsync(() => _seedKitchen(h)))!;
      await h.pumpApp(tester);
      final reel = _Reel('closeout');

      Finder card(String itemName) => find.ancestor(
        of: find.text(itemName),
        matching: find.byType(CloseoutLineCard),
      );
      Finder inCard(String itemName, Finder matching) =>
          find.descendant(of: card(itemName), matching: matching);

      // The card list builds lazily, so a card is scrolled into range before
      // it can be found at all.
      Future<void> reveal(String itemName) async {
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

      Future<void> toTop() async {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
        await tester.pumpAndSettle();
      }

      // 1. Yesterday's dinner, nothing counted yet.
      await h.go(tester, '/events/${ids.activeEventId}/closeout');
      expect(find.textContaining('0 of 4'), findsOneWidget);
      await reel.shoot(tester, hold: 120);

      // 2. The one question, answered on the first card — which confirms and
      //    folds itself to a single row.
      await reveal('Beef chili');
      final leftover = inCard(
        'Beef chili',
        find.widgetWithText(TextFormField, 'How many are left?'),
      );
      await tester.ensureVisible(leftover.first);
      await tester.pumpAndSettle();
      await tester.enterText(leftover.first, '6');
      await tester.pumpAndSettle();
      await toTop();
      expect(find.textContaining('1 of 4'), findsOneWidget);
      await reel.shoot(tester, hold: 120);

      // 3. 'All gone' — the shortcut for the tray that came back empty.
      await reveal('Tortilla chips (party bag)');
      await _tap(
        tester,
        inCard('Tortilla chips (party bag)', find.text('All gone')),
      );
      await toTop();
      expect(find.textContaining('2 of 4'), findsOneWidget);
      await reel.shoot(tester, hold: 110);

      // 4 + 5. The last two lines, so the progress header runs out.
      await reveal('Bottled water');
      await _tap(tester, inCard('Bottled water', find.text('None used')));
      await toTop();
      expect(find.textContaining('3 of 4'), findsOneWidget);
      await reel.shoot(tester, hold: 100);

      await reveal('Paper plates');
      await _tap(tester, inCard('Paper plates', find.text('All gone')));
      // Flush the 500 ms draft autosave before the closing frame.
      await tester.pump(const Duration(seconds: 1));
      await toTop();
      expect(find.textContaining('4 of 4'), findsOneWidget);

      // 6. Finish is live: every line answered, and the attendance prefilled
      //    from the plan.
      final finish = find.widgetWithText(FilledButton, 'Finish closeout');
      expect(tester.widget<FilledButton>(finish.first).onPressed, isNotNull);
      await reel.shoot(tester, last: true);

      reel.write();
    });

    // -------------------------------------------------------- event-cost.gif

    testWidgets('event-cost.gif — money landing live in the tally bar', (
      tester,
    ) async {
      _phoneView(tester);
      final h = await _startWorkspace(tester);
      final ids = (await tester.runAsync(() => _seedKitchen(h)))!;
      await h.pumpApp(tester);
      final reel = _Reel('event-cost');

      // 1. Friday's dinner.
      await h.go(tester, '/events/${ids.upcomingEventId}');
      await reel.shoot(tester, hold: 100);

      // 2. Scrolled to "Estimated cost" — what this event is going to cost,
      //    while it can still be changed.
      await tester.scrollUntilVisible(
        find.text('Estimated cost'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await reel.shoot(tester, hold: 130);

      // 3. Edit, where the planned list lives.
      await _tap(
        tester,
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.edit_outlined),
        ),
      );
      await reel.shoot(tester);

      // 4. The planned-items picker, tally bar already carrying the four
      //    items on the list.
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add items'));
      expect(find.text('Plan items'), findsOneWidget);
      await reel.shoot(tester, hold: 120);

      // 5 + 6. Two priced items ticked; the running total climbs. Tapped
      // WITHOUT ensureVisible: both rows are already on screen, and
      // ensureVisible re-aligns the sliver under its pinned header, sliding
      // the list out from under the loop's fixed framing.
      await tester.tap(find.text('Beef chili'));
      await tester.pumpAndSettle();
      await reel.shoot(tester, hold: 110);
      await tester.tap(find.text('Sandwich platters'));
      await tester.pumpAndSettle();
      await reel.shoot(tester, last: true);

      reel.write();
    });
  }, skip: _skip);
}
