/// The one way diagnostics leave the device (design §9, §10): hands the
/// rotating `support/diag/diag.log` to the platform save dialog through the
/// [FileGateway] seam. No share sheet, no upload, no copy to clipboard.
///
/// Shared by `/settings/diagnostics` and the startup-failure screen. The
/// second one is the point: until now the log lived behind an app that,
/// when it would not open, could not be asked for it.
///
/// Disables itself when no [RingFileDiag] is wired or the file does not
/// exist yet — a screen that cannot offer the export should not render this
/// at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/diagnostics/diag.dart';
import '../../../infrastructure/diagnostics/diag_sink.dart';
import '../../backup/presentation/file_gateway.dart';

enum _ExportOutcome { none, saved, cancelled, failed }

class SaveDiagnosticsButton extends ConsumerStatefulWidget {
  const SaveDiagnosticsButton({super.key, this.caption});

  /// Small print under the button. Null renders nothing.
  final String? caption;

  @override
  ConsumerState<SaveDiagnosticsButton> createState() =>
      _SaveDiagnosticsButtonState();
}

class _SaveDiagnosticsButtonState extends ConsumerState<SaveDiagnosticsButton> {
  bool _busy = false;
  _ExportOutcome _outcome = _ExportOutcome.none;

  Future<void> _export(RingFileDiag ring) async {
    final gateway = ref.read(fileGatewayProvider);
    setState(() {
      _busy = true;
      _outcome = _ExportOutcome.none;
    });
    try {
      final saved = await gateway.saveFile(
        sourcePath: ring.logFile.path,
        suggestedName: 'loadout-diagnostics.log',
      );
      _finish(saved == null ? _ExportOutcome.cancelled : _ExportOutcome.saved);
    } catch (_) {
      // Content-free by design (§10).
      _finish(_ExportOutcome.failed);
    }
  }

  void _finish(_ExportOutcome outcome) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = outcome;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diag = ref.watch(diagProvider);
    final ring = diag is RingFileDiag ? diag : null;
    final canExport = !_busy && ring != null && ring.logFile.existsSync();
    final caption = widget.caption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_outcome == _ExportOutcome.saved)
          Text(
            'Diagnostics file saved.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        if (_outcome == _ExportOutcome.cancelled)
          Text(
            "The diagnostics file wasn't saved.",
            style: theme.textTheme.bodyMedium,
          ),
        if (_outcome == _ExportOutcome.failed)
          Text(
            "The diagnostics file couldn't be saved. Try again.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        if (_outcome != _ExportOutcome.none) const SizedBox(height: Space.m),
        Semantics(
          label: 'Save the diagnostics file',
          button: true,
          child: FilledButton.tonalIcon(
            onPressed: canExport ? () => _export(ring) : null,
            style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
            icon: const Icon(Icons.save_alt),
            label: const Text('Save diagnostics file…'),
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: Space.xs),
          Text(caption, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// True when there is a diagnostics file worth offering to save. Screens use
/// it to decide whether to render [SaveDiagnosticsButton] at all rather than
/// show a button that can only be dead.
bool canSaveDiagnostics(Diag diag) =>
    diag is RingFileDiag && diag.logFile.existsSync();
