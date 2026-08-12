/// One per-item closeout card (design §9 CloseoutScreen): the direct
/// depletion shortcut plus an expandable Loaded / Returned / Waste
/// worksheet. When all three worksheet fields are set the depletion becomes
/// derived, read-only, shown live as `loaded − returned − waste` and
/// captioned "Depletion excludes waste" (§12.3: forecasts learn what SELLS).
/// Toggles: "Ran out" (stockout) and "Estimate" (approximate); "Skip item"
/// records no line. The prefill caption "Planned load was N" comes from the
/// latest snapshot's load/override, blank when none exists.
library;

import 'package:flutter/material.dart';

import '../../../app/widgets/quantity_form_field.dart';
import '../../../app/widgets/warning_banner.dart';
import '../../../core/quantity.dart';
import '../../../core/quantity_codec.dart';

/// Depletion envelope cap (design §3): the frozen engine's safe range.
const int maxDepletionMicros = 1000000000000;

/// Mutable UI state for one worksheet line, owned by the screen. All
/// parsing goes through [QuantityFormField.tryParse] — exact micros, never
/// a `double`.
final class CloseoutLineController {
  CloseoutLineController({
    required this.itemId,
    required this.itemName,
    required this.unitLabel,
    this.plannedLoadMicros,
  });

  final String itemId;
  final String itemName;

  /// Short unit suffix ('kg', 'each', …).
  final String unitLabel;

  /// "Planned load was N" caption source; null when no snapshot exists.
  final int? plannedLoadMicros;

  final TextEditingController depletion = TextEditingController();
  final TextEditingController loaded = TextEditingController();
  final TextEditingController returned = TextEditingController();
  final TextEditingController waste = TextEditingController();

  bool stockout = false;
  bool approximate = false;
  bool skipped = false;
  bool worksheetOpen = false;

  void dispose() {
    depletion.dispose();
    loaded.dispose();
    returned.dispose();
    waste.dispose();
  }

  static Quantity? _parse(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : QuantityFormField.tryParse(text);
  }

  Quantity? get loadedQuantity => _parse(loaded);
  Quantity? get returnedQuantity => _parse(returned);
  Quantity? get wasteQuantity => _parse(waste);
  Quantity? get directDepletion => _parse(depletion);

  /// All three worksheet fields parse — depletion is derived, read-only.
  bool get worksheetComplete =>
      loadedQuantity != null &&
      returnedQuantity != null &&
      wasteQuantity != null;

  /// `loaded − returned − waste` in micros; may be negative (invalid).
  int? get derivedDepletionMicros => worksheetComplete
      ? loadedQuantity!.micros -
            returnedQuantity!.micros -
            wasteQuantity!.micros
      : null;

  /// The depletion this line would confirm, or null while invalid or
  /// incomplete. A zero is a legal label (§5).
  Quantity? get effectiveDepletion {
    if (worksheetComplete) {
      final derived = derivedDepletionMicros!;
      if (derived < 0 || derived > maxDepletionMicros) return null;
      return Quantity.fromMicros(derived);
    }
    final direct = directDepletion;
    if (direct == null || direct.micros > maxDepletionMicros) return null;
    return direct;
  }

  /// Done = confirmed (has a legal depletion) or deliberately skipped.
  bool get done => skipped || effectiveDepletion != null;

  /// Counts toward "X of Y items confirmed" (skips never do).
  bool get confirmed => !skipped && effectiveDepletion != null;
}

class CloseoutLineCard extends StatelessWidget {
  const CloseoutLineCard({
    super.key,
    required this.line,
    required this.onChanged,
  });

  final CloseoutLineController line;

  /// Fires on every edit/toggle — the screen rebuilds and schedules the
  /// debounced draft autosave.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  line.done
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                  color: line.done
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  semanticLabel: line.done
                      ? '${line.itemName}: done'
                      : '${line.itemName}: to do',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line.itemName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    line.skipped = !line.skipped;
                    onChanged();
                  },
                  child: Text(line.skipped ? 'Include item' : 'Skip item'),
                ),
              ],
            ),
            if (line.plannedLoadMicros != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Planned load was '
                  '${QuantityCodec.format(Quantity.fromMicros(line.plannedLoadMicros!))} '
                  '${line.unitLabel}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (line.skipped)
              Text(
                'Skipped — nothing will be recorded for this item.',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              const SizedBox(height: 4),
              if (line.worksheetComplete)
                _derivedDepletion(theme)
              else
                QuantityFormField(
                  controller: line.depletion,
                  labelText: 'Depletion',
                  unitLabel: line.unitLabel,
                  isRequired: false,
                  allowZero: true,
                  helperText: 'What sold — excludes waste.',
                  onChanged: (_) => onChanged(),
                  validator: (value) => value.micros > maxDepletionMicros
                      ? 'Larger than Loadout supports'
                      : null,
                ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    line.worksheetOpen = !line.worksheetOpen;
                    onChanged();
                  },
                  icon: Icon(
                    line.worksheetOpen ? Icons.expand_less : Icons.expand_more,
                  ),
                  label: Text(
                    line.worksheetOpen
                        ? 'Hide worksheet'
                        : 'Worksheet (loaded − returned − waste)',
                  ),
                ),
              ),
              if (line.worksheetOpen) ...[
                const SizedBox(height: 8),
                QuantityFormField(
                  controller: line.loaded,
                  labelText: 'Loaded',
                  unitLabel: line.unitLabel,
                  isRequired: false,
                  allowZero: true,
                  onChanged: (_) => onChanged(),
                ),
                const SizedBox(height: 12),
                QuantityFormField(
                  controller: line.returned,
                  labelText: 'Returned',
                  unitLabel: line.unitLabel,
                  isRequired: false,
                  allowZero: true,
                  onChanged: (_) => onChanged(),
                ),
                const SizedBox(height: 12),
                QuantityFormField(
                  controller: line.waste,
                  labelText: 'Waste',
                  unitLabel: line.unitLabel,
                  isRequired: false,
                  allowZero: true,
                  onChanged: (_) => onChanged(),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Ran out'),
                    tooltip: 'Stockout — demand was at least this',
                    selected: line.stockout,
                    onSelected: (selected) {
                      line.stockout = selected;
                      onChanged();
                    },
                  ),
                  FilterChip(
                    label: const Text('Estimate'),
                    tooltip: 'Approximate numbers',
                    selected: line.approximate,
                    onSelected: (selected) {
                      line.approximate = selected;
                      onChanged();
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _derivedDepletion(ThemeData theme) {
    final derived = line.derivedDepletionMicros!;
    if (derived < 0) {
      return const WarningBanner(
        message: 'Returned and waste exceed loaded — check the worksheet.',
      );
    }
    if (derived > maxDepletionMicros) {
      return const WarningBanner(
        message: 'This depletion is larger than Loadout supports.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Depletion: ${QuantityCodec.format(Quantity.fromMicros(derived))} '
          '${line.unitLabel}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Depletion excludes waste — derived from the worksheet.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
