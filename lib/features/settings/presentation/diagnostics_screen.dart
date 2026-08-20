/// `/settings/diagnostics` (design §9, §10): content-free log viewer over
/// the [RingFileDiag] ring buffer (newest first, monospace) plus
/// [SaveDiagnosticsButton] — the save-file dialog is deliberately the only
/// way logs leave the device, and the startup-failure screen offers the
/// same button for when this screen cannot be reached.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/widgets/content_column.dart';
import '../../../infrastructure/diagnostics/diag_sink.dart';
import 'save_diagnostics_button.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final diag = ref.watch(diagProvider);
    final ring = diag is RingFileDiag ? diag : null;
    // Newest first (§9 diagnostics viewer).
    final lines = (ring?.bufferedLines ?? const <String>[]).reversed.toList();
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
                  const SaveDiagnosticsButton(
                    caption:
                        'Saving the file is the only way these lines leave '
                        'the device.',
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
