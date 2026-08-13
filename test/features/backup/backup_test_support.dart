/// Shared helpers for the settings/backup widget tests: a fake
/// [FileGateway] (platform channels don't exist in host tests), a
/// cheap-KDF backup facade, and pump/settle helpers for flows that do real
/// file IO behind a button tap.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/app/providers.dart';
import 'package:loadout/app/theme.dart';
import 'package:loadout/features/backup/application/backup_facade.dart';
import 'package:loadout/features/backup/presentation/file_gateway.dart';
import 'package:loadout/infrastructure/backup/backup_service_impl.dart';

import '../../support/app_harness.dart';
import '../../support/schema_version.dart';

/// One captured save-dialog interaction. Bytes are copied synchronously at
/// save time because the source (a scratch session) is disposed right after.
final class FakeSave {
  FakeSave(this.sourcePath, this.suggestedName, this.bytes);

  final String sourcePath;
  final String suggestedName;
  final Uint8List bytes;
}

/// Fake dialog seam. All file IO is synchronous so it is FakeAsync-safe.
final class FakeFileGateway implements FileGateway {
  String? pickResult;
  bool cancelSave = false;
  final List<FakeSave> saves = [];

  @override
  Future<String?> saveFile({
    required String sourcePath,
    required String suggestedName,
  }) async {
    if (cancelSave) return null;
    final bytes = File(sourcePath).readAsBytesSync();
    saves.add(FakeSave(sourcePath, suggestedName, bytes));
    return '/fake-saved/$suggestedName';
  }

  @override
  Future<String?> pickFile() async => pickResult;
}

/// Cheap Argon2id cost so widget tests don't pay the production KDF.
const Argon2Cost fastKdfCost = Argon2Cost(
  memoryKiB: 32,
  iterations: 1,
  parallelism: 1,
  hashLength: 32,
);

/// A real facade over the harness's startup/key/scratch wiring, with the
/// cheap KDF cost. Behavior-identical to production otherwise.
BackupFacade fastBackupFacade(AppHarness h) => DefaultBackupFacade(
  BackupServiceImpl(
    host: h.startup,
    keyManager: h.keyManager,
    scratch: h.read(scratchSpaceProvider),
    databaseFile: h.paths.databaseFile,
    appSchemaVersion: appSchemaVersionUnderTest,
    kdfCost: fastKdfCost,
  ),
);

/// A container composed exactly like the harness's own, plus test
/// overrides (fake gateway, cheap facade). Root-level overrides — no
/// nested-scope subtleties.
ProviderContainer containerWith(AppHarness h, List<Override> extra) =>
    ProviderContainer(overrides: [...h.boot.overrides, ...extra]);

/// Pumps one screen over [container] without a router (like
/// `AppHarness.pumpScreen`).
Future<void> pumpScreenWith(
  WidgetTester tester,
  ProviderContainer container,
  Widget screen,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: loadoutTheme(Brightness.light),
        darkTheme: loadoutTheme(Brightness.dark),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Lets a tapped flow that awaits REAL file IO / KDF work make progress:
/// alternates slices of real event-loop time (`runAsync`) with pumps that
/// flush the FakeAsync microtask queue, until [done] or timeout.
Future<void> settleUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 30),
  String reason = 'condition',
}) async {
  final stopwatch = Stopwatch()..start();
  while (!done()) {
    if (stopwatch.elapsed > timeout) {
      fail('settleUntil timed out waiting for: $reason');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pump();
}

/// True when [finder] currently matches at least one widget.
bool visible(Finder finder) => finder.evaluate().isNotEmpty;

/// Scrolls [finder] into view, then taps it. Screens here are long forms in
/// a `SingleChildScrollView`; a plain tap can miss below the fold.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}
