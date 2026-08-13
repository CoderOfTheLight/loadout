/// `/recovery` (§7.3, §9), interrupted-restore branch.
///
/// The service-level proof that a parked workspace comes back intact lives in
/// `test/infrastructure/startup_parked_recovery_test.dart`. What matters here
/// is that the owner is TOLD what happened and handed a button — before this
/// screen had one, the data was recoverable only with a debugger attached.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/features/onboarding/presentation/recovery_screen.dart';
import 'package:loadout/infrastructure/startup/startup_service.dart';

import '../../support/app_harness.dart';

Future<AppHarness> _start(WidgetTester tester, AppHarnessState state) async {
  final h = (await tester.runAsync(() => AppHarness.start(state: state)))!;
  addTearDown(h.dispose);
  return h;
}

const _putBackLabel = 'Put my workspace back';

/// Taps [button] and lets the real work behind it finish.
///
/// Putting a workspace back stages a copy, probes it through SQLCipher, and
/// renames real files. None of that can progress under FakeAsync, so the tap
/// itself has to happen inside `runAsync` — pumping only afterwards.
Future<void> _tapAwaitingRealIo(WidgetTester tester, Finder button) async {
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(button);
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an interrupted restore boots to /recovery and says so', (
    tester,
  ) async {
    final h = await _start(tester, AppHarnessState.recoveryParked);
    await h.pumpApp(tester);

    expect(h.boot.state, isA<StartupParkedWorkspace>());
    expect(h.boot.initialLocation, '/recovery');
    expect(find.byType(RecoveryScreen), findsOneWidget);

    // The headline is not the "can't unlock" one: nothing is broken here.
    expect(
      find.text('Your workspace is still on this device.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('A restore was interrupted.'),
      findsOneWidget,
      reason: 'the owner is told what actually happened',
    );
    expect(find.textContaining('Nothing has been deleted.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, _putBackLabel), findsOneWidget);
    // The other two ways out stay available.
    expect(find.text('Restore from backup file'), findsOneWidget);
    expect(find.text('Start fresh'), findsOneWidget);
  });

  testWidgets('putting the workspace back opens it and leaves /recovery', (
    tester,
  ) async {
    final h = await _start(tester, AppHarnessState.recoveryParked);
    await h.pumpApp(tester);
    final keyBefore = await tester.runAsync(
      () => h.keyManager.getOrCreateDatabaseKey(),
    );
    final parked = File('${h.paths.databaseFile.path}$preRestoreSuffix');
    expect(parked.existsSync(), isTrue);

    await _tapAwaitingRealIo(
      tester,
      find.widgetWithText(FilledButton, _putBackLabel),
    );

    // Where the redirect lands afterwards is the harness's in-memory
    // database's business (it has no workspace row); leaving /recovery at all
    // is this screen's.
    expect(find.byType(RecoveryScreen), findsNothing);
    expect(
      h.paths.databaseFile.existsSync(),
      isTrue,
      reason: 'the parked copy is back where the app looks for it',
    );
    expect(parked.existsSync(), isFalse);
    expect(h.startup.isOpen, isTrue);
    expect(
      await tester.runAsync(() => h.keyManager.getOrCreateDatabaseKey()),
      keyBefore,
      reason: 'the key that opens the workspace is never rotated',
    );
  });

  testWidgets('a parked copy no key opens is refused honestly and kept', (
    tester,
  ) async {
    final h = await _start(tester, AppHarnessState.recoveryParkedUnreadable);
    await h.pumpApp(tester);
    final parked = File('${h.paths.databaseFile.path}$preRestoreSuffix');
    final bytesBefore = parked.readAsBytesSync();

    await _tapAwaitingRealIo(
      tester,
      find.widgetWithText(FilledButton, _putBackLabel),
    );

    expect(find.byType(RecoveryScreen), findsOneWidget);
    expect(
      find.textContaining('None of the keys on this device opens that copy.'),
      findsOneWidget,
      reason: 'say it plainly instead of silently discarding the file',
    );
    expect(find.textContaining('has not been deleted'), findsOneWidget);
    expect(
      parked.readAsBytesSync(),
      bytesBefore,
      reason: 'a refusal changes nothing on disk',
    );
    expect(h.paths.databaseFile.existsSync(), isFalse);
  });

  testWidgets('the key-missing recovery screen is unchanged', (tester) async {
    final h = await _start(tester, AppHarnessState.recoveryKeyMissing);
    await h.pumpApp(tester);

    expect(
      find.text("This device can't unlock the existing data."),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, _putBackLabel),
      findsNothing,
      reason: 'there is nothing parked to put back',
    );
    expect(
      find.widgetWithText(FilledButton, 'Restore from backup file'),
      findsOneWidget,
      reason: 'restore stays the primary action in this state',
    );
  });
}
