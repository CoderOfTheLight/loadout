/// Gate 5 OCR widget tests over a fake [RecipeOcrService] (the real one
/// needs a device camera): the 'Scan a recipe' button hides when both
/// probes say no and shows when either says yes; a capture's lines are
/// normalized ('½' → '1/2'), prose-filtered, and land on the form through
/// the SAME review sheet as "Paste ingredients"; the saved revision records
/// `source_kind = 'ocr'`; a cancelled capture changes nothing; a failed
/// capture says so content-free (never the channel code).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/recipes/application/recipe_ocr_service.dart';
import 'package:loadout/features/recipes/domain/recipe.dart';

import '../../support/app_harness.dart';
import 'recipe_test_support.dart';

final class _FakeRecipeOcrService implements RecipeOcrService {
  _FakeRecipeOcrService({
    this.cameraAvailable = false,
    this.photoAvailable = false,
    this.capture,
    this.failure,
  });

  final bool cameraAvailable;
  final bool photoAvailable;

  /// What a capture resolves to; null = the owner cancelled.
  final RecipeOcrCapture? capture;

  /// When set, every capture throws this instead.
  final RecipeOcrException? failure;

  int cameraCalls = 0;
  int photoCalls = 0;

  @override
  Future<bool> isCameraScanAvailable() async => cameraAvailable;

  @override
  Future<bool> isPhotoPickAvailable() async => photoAvailable;

  @override
  Future<RecipeOcrCapture?> scanWithCamera() {
    cameraCalls++;
    return _capture();
  }

  @override
  Future<RecipeOcrCapture?> pickPhoto() {
    photoCalls++;
    return _capture();
  }

  Future<RecipeOcrCapture?> _capture() async {
    final failure = this.failure;
    if (failure != null) throw failure;
    return capture;
  }
}

Future<AppHarness> _startWith(
  WidgetTester tester,
  _FakeRecipeOcrService fake,
) async {
  final h = (await tester.runAsync(
    () => AppHarness.start(
      state: AppHarnessState.workspace,
      overrides: [recipeOcrServiceProvider.overrideWithValue(fake)],
    ),
  ))!;
  addTearDown(h.dispose);
  await h.pumpApp(tester);
  await h.go(tester, '/recipes/new');
  return h;
}

void main() {
  testWidgets('scan button stays hidden when both probes say no', (
    tester,
  ) async {
    final h = await _startWith(tester, _FakeRecipeOcrService());

    expect(find.byKey(const Key('paste-ingredients')), findsOneWidget);
    expect(find.byKey(const Key('scan-recipe')), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets(
    'camera-only availability shows the button and goes straight to the '
    'camera — no chooser',
    (tester) async {
      final fake = _FakeRecipeOcrService(cameraAvailable: true);
      final h = await _startWith(tester, fake);

      await tapVisible(tester, find.byKey(const Key('scan-recipe')));

      expect(fake.cameraCalls, 1);
      expect(fake.photoCalls, 0);
      expect(find.text('Take a photo'), findsNothing);
      expect(find.text('Choose a photo'), findsNothing);
      // The null capture (cancel) changed nothing.
      expect(find.text('Review before adding'), findsNothing);
      await h.flushTimers(tester);
    },
  );

  testWidgets(
    'both paths available: a labeled chooser, and "Take a photo" drives '
    'the camera',
    (tester) async {
      final fake = _FakeRecipeOcrService(
        cameraAvailable: true,
        photoAvailable: true,
      );
      final h = await _startWith(tester, fake);

      await tapVisible(tester, find.byKey(const Key('scan-recipe')));
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose a photo'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('scan-take-photo')));
      expect(fake.cameraCalls, 1);
      expect(fake.photoCalls, 0);
      await h.flushTimers(tester);
    },
  );

  testWidgets(
    'a capture lands through the review sheet: fractions normalized, prose '
    'dropped, rows appended, and the revision saved as scanned',
    (tester) async {
      final fake = _FakeRecipeOcrService(
        photoAvailable: true,
        capture: const RecipeOcrCapture(
          lines: [
            'Beef stew',
            '2 lbs beef',
            '½ cup flour',
            'Simmer gently until the meat is falling apart and tender',
          ],
        ),
      );
      final h = await _startWith(tester, fake);

      await tester.enterText(
        find.byKey(const Key('recipe-name')),
        'Beef stew dinner',
      );
      await tester.enterText(find.byKey(const Key('recipe-yield')), '8');

      // One tap: photo is the only path, so no chooser — straight to the
      // (fake) picker, then the SAME review sheet paste uses, already on
      // its review stage.
      await tapVisible(tester, find.byKey(const Key('scan-recipe')));
      expect(fake.photoCalls, 1);
      expect(find.text('Review before adding'), findsOneWidget);

      // The prose line never reached the review.
      expect(find.textContaining('Simmer gently'), findsNothing);

      // '2 lbs beef' parsed: amount 2, display label lbs; '½ cup flour'
      // normalized to '1/2 cup flour': amount 0.5, label cup. Nothing in
      // the (empty) catalog matches, so all three arrive as keep-ticked
      // free-line offers.
      expect(find.text('Add «Beef stew»'), findsOneWidget);
      expect(find.text('Add «beef»'), findsOneWidget);
      expect(find.text('Add «flour»'), findsOneWidget);
      expect(find.textContaining('2 lbs per batch'), findsOneWidget);
      expect(find.textContaining('0.5 cup per batch'), findsOneWidget);

      // The review is a real review: untick the title line — it is the
      // dish, not an ingredient.
      await tapVisible(tester, find.text('Add «Beef stew»'));
      expect(find.text('Add 2 ingredients'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('paste-confirm')));
      await h.flushTimers(tester);

      // Two rows landed (the pristine starter row was replaced): each with
      // its parsed amount and unit label.
      expect(find.text('beef'), findsOneWidget);
      expect(find.text('flour'), findsOneWidget);
      expect(find.text('lbs'), findsOneWidget);
      expect(find.text('cup'), findsOneWidget);
      expect(find.text('0.5'), findsOneWidget);
      expect(find.text('Beef stew'), findsNothing);

      await tapVisible(tester, find.byKey(const Key('save-recipe')));

      // The saved revision: both lines free (no catalog), amounts intact,
      // and the provenance says scanned.
      final detail = (await tester.runAsync(() async {
        final summaries = await h
            .read(recipeServiceProvider)
            .watchRecipes()
            .first;
        expect(summaries, hasLength(1));
        return h
            .read(recipeServiceProvider)
            .watchRecipe(summaries.first.id)
            .first;
      }))!;
      final revision = detail.revisions.first;
      expect(revision.sourceKind, RecipeSourceKind.ocr);
      expect(revision.lines, hasLength(2));
      expect([for (final line in revision.lines) line.name], ['beef', 'flour']);
      expect(
        [for (final line in revision.lines) line.unitLabel],
        ['lbs', 'cup'],
      );
      expect(
        [for (final line in revision.lines) line.quantityPerBatch],
        [
          Quantity.whole(2),
          Quantity.fromMicros(500000), // 1/2
        ],
      );
      expect(
        [for (final line in revision.lines) line.ingredientItemId],
        [null, null],
      );
      await h.flushTimers(tester);
    },
  );

  testWidgets('a cancelled capture leaves the form untouched', (tester) async {
    final fake = _FakeRecipeOcrService(photoAvailable: true);
    final h = await _startWith(tester, fake);

    await tapVisible(tester, find.byKey(const Key('scan-recipe')));

    expect(fake.photoCalls, 1);
    expect(find.text('Review before adding'), findsNothing);
    // The pristine starter row is still alone.
    expect(find.byKey(const ValueKey('ingredient-row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('ingredient-row-1')), findsNothing);
    await h.flushTimers(tester);
  });

  testWidgets('a failed capture says so content-free', (tester) async {
    final fake = _FakeRecipeOcrService(
      photoAvailable: true,
      failure: const RecipeOcrException('camera_failed'),
    );
    final h = await _startWith(tester, fake);

    await tapVisible(tester, find.byKey(const Key('scan-recipe')));

    expect(find.text("Couldn't read that photo. Try again."), findsOneWidget);
    // Never the channel code, and never a review of nothing.
    expect(find.textContaining('camera_failed'), findsNothing);
    expect(find.text('Review before adding'), findsNothing);
    expect(find.byKey(const ValueKey('ingredient-row-1')), findsNothing);

    // Let the snackbar timer expire so the test ends clean.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });

  testWidgets('a capture that filters down to nothing says no text found', (
    tester,
  ) async {
    final fake = _FakeRecipeOcrService(
      photoAvailable: true,
      capture: const RecipeOcrCapture(
        lines: [
          '',
          'Simmer gently until the meat is falling apart and tender',
          'Serve piping hot with plenty of crusty bread on the side',
        ],
      ),
    );
    final h = await _startWith(tester, fake);

    await tapVisible(tester, find.byKey(const Key('scan-recipe')));

    expect(find.text('No text found in that photo.'), findsOneWidget);
    expect(find.text('Review before adding'), findsNothing);
    expect(find.byKey(const ValueKey('ingredient-row-1')), findsNothing);

    // Let the snackbar timer expire so the test ends clean.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await h.flushTimers(tester);
  });
}
