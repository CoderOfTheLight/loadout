/// `/settings/export`: four spreadsheets, one button each.
///
/// The backup file is encrypted and only Loadout can open it. That is right
/// for a backup and useless to a treasurer. This screen is the other door:
/// plain CSV, no passphrase, opens in Excel by double-click.
///
/// Deliberately four rows and a sentence. Every question this screen could
/// ask — which columns, which date range, which format — has been answered
/// in the code instead, because the owner asked for less to decide, not
/// more. The only question left is the one that cannot be answered for her:
/// WHICH event a count belongs to.
///
/// Saving reuses the backup flow's [FileGateway] seam (save-file-only
/// egress, §12.19): the CSV is written into a scratch session, handed to
/// the platform save dialog, and the session is disposed whatever happens.
/// Nothing about the file's CONTENT is ever logged or shown in an error.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../backup/presentation/file_gateway.dart';
import '../application/spreadsheet_export_service.dart';
import '../domain/spreadsheet_export.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  /// Which export is running, if any. One at a time: two save dialogs at
  /// once is not a thing any platform does well.
  SpreadsheetExport? _busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Export a spreadsheet')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            padding: const EdgeInsets.fromLTRB(
              Space.l,
              Space.l,
              Space.l,
              Space.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Each of these saves a CSV file — a plain spreadsheet '
                  'Excel opens by double-clicking. Nothing is uploaded; you '
                  'choose where the file goes.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Space.l),
                for (final export in SpreadsheetExport.values) ...[
                  _ExportCard(
                    export: export,
                    busy: _busy == export,
                    enabled: _busy == null,
                    onPressed: () => _start(export),
                  ),
                  const SizedBox(height: Space.m),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _start(SpreadsheetExport export) async {
    final service = ref.read(spreadsheetExportServiceProvider);
    final fileName = exportFileName(export, datePart: _today());
    switch (export) {
      case SpreadsheetExport.items:
        await _run(export, service.itemsCsv, fileName: fileName);
      case SpreadsheetExport.events:
        await _run(export, service.eventsCsv, fileName: fileName);
      case SpreadsheetExport.recipes:
        await _run(export, service.recipesCsv, fileName: fileName);
      case SpreadsheetExport.eventCount:
        await _startEventCount(service);
    }
  }

  /// The one export that cannot be started without asking: which event.
  Future<void> _startEventCount(SpreadsheetExportService service) async {
    final events = await service.countedEvents();
    if (!mounted) return;
    if (events.isEmpty) {
      _say('No event has been counted yet, so there is nothing to export.');
      return;
    }
    final chosen = await _pickEvent(events);
    if (chosen == null || !mounted) return;
    await _run(
      SpreadsheetExport.eventCount,
      () => service.eventCountCsv(chosen.id),
      // Stamped with the event's own date and name: a count file that does
      // not say which day it describes is an orphan the moment it is
      // emailed on.
      fileName: exportFileName(
        SpreadsheetExport.eventCount,
        datePart: chosen.scheduledDate,
        subject: chosen.name,
      ),
    );
  }

  Future<void> _run(
    SpreadsheetExport export,
    Future<String> Function() build, {
    required String fileName,
  }) async {
    setState(() => _busy = export);
    final gateway = ref.read(fileGatewayProvider);
    final scratch = ref.read(scratchSpaceProvider);
    var message = "The file couldn't be saved. Nothing was changed.";
    Directory? session;
    try {
      final csv = await build();
      session = await scratch.createSession('export');
      final file = File(p.join(session.path, fileName));
      await file.writeAsBytes(utf8.encode(csv), flush: true);
      final savedTo = await gateway.saveFile(
        sourcePath: file.path,
        suggestedName: fileName,
      );
      message = savedTo == null ? 'Nothing was saved.' : 'Saved as $fileName.';
    } catch (_) {
      // Content-free by design (§10): no row, name or path ever surfaces.
    }
    if (session != null) {
      try {
        await scratch.disposeSession(session);
      } catch (_) {
        // Swept on next start (§10).
      }
    }
    if (!mounted) return;
    setState(() => _busy = null);
    _say(message);
  }

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<CountedEvent?> _pickEvent(List<CountedEvent> events) =>
      showDialog<CountedEvent>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Which event?'),
          children: [
            for (final event in events)
              ListTile(
                title: Text(event.name),
                subtitle: Text(event.scheduledDate),
                onTap: () => Navigator.of(dialogContext).pop(event),
              ),
          ],
        ),
      );

  static String _today() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }
}

/// One export: what it is, one line of why, and the button that saves it.
class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.export,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final SpreadsheetExport export;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(export.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: Space.xs),
            Text(export.blurb, style: theme.textTheme.bodyMedium),
            const SizedBox(height: Space.m),
            FilledButton(
              onPressed: enabled ? onPressed : null,
              style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
              child: Text(busy ? 'Saving…' : export.buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
