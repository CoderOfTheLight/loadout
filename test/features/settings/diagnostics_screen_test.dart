/// §11.3 diagnostics viewer: renders the ring buffer's content-free lines
/// newest first in monospace, explains the content-free guarantee, and
/// exports the log file through the file-gateway seam.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/diagnostics/diag.dart';
import 'package:loadout/features/settings/presentation/diagnostics_screen.dart';
import 'package:loadout/features/backup/presentation/file_gateway.dart';
import 'package:loadout/infrastructure/diagnostics/diag_sink.dart';
import 'package:path/path.dart' as p;

import '../../support/app_harness.dart';
import '../backup/backup_test_support.dart';

void main() {
  testWidgets('renders content-free lines newest first and exports the log', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('diag_screen_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final ring = RingFileDiag(logFile: File(p.join(tempDir.path, 'diag.log')));

    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace, diag: ring),
    ))!;
    addTearDown(h.dispose);

    // Two extra events on top of whatever bootstrap logged through the ring.
    ring.event(DiagEvent.backupCreateOk, count: 3);
    ring.event(DiagEvent.commandRejected, errorType: 'ValidationError');

    final gateway = FakeFileGateway();
    final container = containerWith(h, [
      fileGatewayProvider.overrideWithValue(gateway),
    ]);
    addTearDown(container.dispose);
    await pumpScreenWith(tester, container, const DiagnosticsScreen());

    // The explainer copy states the content-free guarantee.
    expect(
      find.textContaining('a timestamp, an event code, and numbers'),
      findsOneWidget,
    );

    // Newest first: the last event emitted is the first line rendered.
    final listTexts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data ?? '')
        .toList();
    expect(listTexts, isNotEmpty);
    expect(listTexts.first, contains('commandRejected'));
    expect(listTexts.first, contains('err=ValidationError'));
    expect(listTexts[1], contains('backupCreateOk'));
    expect(listTexts[1], contains('count=3'));
    // Bootstrap events flowed through the same ring and are shown too.
    expect(listTexts.join('\n'), contains('dbOpenOk'));

    // Lines are monospace (§9: monospace list).
    final firstLine = tester.widget<Text>(
      find
          .descendant(of: find.byType(ListView), matching: find.byType(Text))
          .first,
    );
    expect(firstLine.style?.fontFamily, 'monospace');

    // Export goes through the file-gateway seam, source = the rotating file.
    await tester.tap(find.text('Save diagnostics file…'));
    await tester.pumpAndSettle();
    final save = gateway.saves.single;
    expect(save.suggestedName, 'loadout-diagnostics.log');
    expect(save.sourcePath, ring.logFile.path);
    expect(String.fromCharCodes(save.bytes), contains('backupCreateOk'));
    expect(find.text('Diagnostics file saved.'), findsOneWidget);
  });

  testWidgets('shows an empty state when no ring sink is wired', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => AppHarness.start(state: AppHarnessState.workspace),
    ))!;
    addTearDown(h.dispose);
    await h.pumpScreen(tester, const DiagnosticsScreen());

    expect(
      find.text('No diagnostic events recorded this session.'),
      findsOneWidget,
    );
  });
}
