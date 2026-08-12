/// `/settings/diagnostics` (design §9, §10): content-free log viewer over
/// the [RingFileDiag] ring buffer (newest first, monospace) plus "Save
/// diagnostics file…" through the [FileGateway] seam — deliberately the
/// only way logs leave the device.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../infrastructure/diagnostics/diag_sink.dart';
import '../../backup/presentation/file_gateway.dart';

enum _ExportOutcome { none, saved, cancelled, failed }

class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
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
    // Newest first (§9 diagnostics viewer).
    final lines = (ring?.bufferedLines ?? const <String>[]).reversed.toList();
    final canExport = !_busy && ring != null && ring.logFile.existsSync();
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: SafeArea(
        child: Column(
          children: [
            ContentColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Every line is content-free: a timestamp, an event code, '
                    'and numbers. Item names, quantities, and notes '
                    'physically cannot appear here. Newest first.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
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
                  if (_outcome != _ExportOutcome.none)
                    const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: canExport ? () => _export(ring) : null,
                    style: FilledButton.styleFrom(
                      minimumSize: primaryButtonMinSize,
                    ),
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Save diagnostics file…'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Saving the file is the only way these lines leave the '
                    'device.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: lines.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No diagnostic events recorded this session.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    )
                  : Scrollbar(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: lines.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            lines[index],
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
