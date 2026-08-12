/// `/events/:eventId/forecast/:itemId` — the full story for one forecast
/// line (design §9, §6.6): result with the arithmetic narrated, the stored
/// evidence value-copies, assumptions, warnings verbatim, override entry
/// (mandatory reason ≥ 3 chars, clear-override appends a NULL-load row) and
/// the append-only override history, plus the method/version footer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/quantity_form_field.dart';
import '../../catalog/domain/item.dart';
import '../../events/domain/event.dart';
import '../domain/forecast_engine.dart';
import '../domain/snapshot.dart';
import 'forecast_presentation_support.dart';

class ForecastLineDetailScreen extends ConsumerStatefulWidget {
  const ForecastLineDetailScreen({
    super.key,
    required this.eventId,
    required this.itemId,
  });

  final String eventId;
  final String itemId;

  @override
  ConsumerState<ForecastLineDetailScreen> createState() =>
      _ForecastLineDetailScreenState();
}

class _ForecastLineDetailScreenState
    extends ConsumerState<ForecastLineDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonFieldKey = GlobalKey<FormFieldState<String>>();
  final _load = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;
  bool _reasonPrefilled = false;

  @override
  void dispose() {
    _load.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _apply(String snapshotId) async {
    if (!_formKey.currentState!.validate()) return;
    final load = QuantityFormField.tryParse(_load.text);
    if (load == null) return;
    setState(() => _busy = true);
    final result = await ref
        .read(forecastServiceProvider)
        .setOverride(
          snapshotId: snapshotId,
          itemId: widget.itemId,
          load: load,
          reason: _reason.text.trim(),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    result.fold(
      (_) {
        _load.clear();
        _reason.clear();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Override applied')));
      },
      (error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      },
    );
  }

  /// Clear-override appends a NULL-load row — also with a mandatory reason
  /// (§12.17). Only the reason field is validated here.
  Future<void> _clear(String snapshotId) async {
    if (!(_reasonFieldKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final result = await ref
        .read(forecastServiceProvider)
        .clearOverride(
          snapshotId: snapshotId,
          itemId: widget.itemId,
          reason: _reason.text.trim(),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    result.fold(
      (_) {
        _load.clear();
        _reason.clear();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Override cleared')));
      },
      (error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(latestSnapshotProvider(widget.eventId));
    return Scaffold(
      appBar: AppBar(title: const Text('Forecast line')),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyState(
          icon: Icons.error_outline,
          message: 'The forecast could not be loaded.',
        ),
        data: (snapshot) {
          if (snapshot == null) {
            return const EmptyState(
              icon: Icons.insights_outlined,
              message: 'No forecast has been generated for this event yet.',
            );
          }
          ForecastLineView? line;
          for (final candidate in snapshot.lines) {
            if ((candidate.itemId as String) == widget.itemId) {
              line = candidate;
            }
          }
          if (line == null) {
            return const EmptyState(
              icon: Icons.search_off_outlined,
              message:
                  'This item is not part of the latest forecast '
                  'snapshot.',
            );
          }
          return _body(context, snapshot, line);
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ForecastSnapshotView snapshot,
    ForecastLineView line,
  ) {
    final theme = Theme.of(context);
    final item = ref
        .watch(forecastItemIndexProvider)
        .valueOrNull?[widget.itemId];
    final unit = item?.unit.dbValue ?? '';
    final status = ref
        .watch(eventDetailProvider(widget.eventId))
        .valueOrNull
        ?.event
        .status;
    final editable =
        status == EventStatus.planned || status == EventStatus.active;
    // "Set a baseline" entry (§9): prefill the reason once for lines with
    // no history and no override yet.
    if (!_reasonPrefilled &&
        editable &&
        line.evidenceGrade == EvidenceGrade.insufficientData &&
        line.override == null &&
        _reason.text.isEmpty) {
      _reason.text = 'baseline';
      _reasonPrefilled = true;
    }
    final exposureLabel = exposureLabelOf(snapshot);
    return ContentColumn(
      child: ListView(
        children: [
          _resultCard(theme, snapshot, line, item, unit, exposureLabel),
          _sectionTitle(theme, 'Evidence'),
          if (line.evidence.isEmpty)
            Text(
              'No comparable confirmed outcomes were available when this '
              'forecast was generated.',
              style: theme.textTheme.bodyMedium,
            )
          else
            for (final evidence in line.evidence)
              _EvidenceRow(
                evidence: evidence,
                unit: unit,
                exposureLabel: exposureLabel,
              ),
          _sectionTitle(theme, 'Assumptions'),
          _assumptionsCard(theme, snapshot, line, unit, exposureLabel),
          if (line.warnings.isNotEmpty) ...[
            _sectionTitle(theme, 'Warnings'),
            for (final warning in line.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 20,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(warning, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
          _sectionTitle(theme, 'Override'),
          if (editable) _overrideForm(theme, snapshot, line, unit),
          _overrideHistory(theme, snapshot, unit),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '${snapshot.method} · v${snapshot.methodVersion}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(title, style: theme.textTheme.titleMedium),
  );

  // ------------------------------------------------------------- result

  Widget _resultCard(
    ThemeData theme,
    ForecastSnapshotView snapshot,
    ForecastLineView line,
    Item? item,
    String unit,
    String exposureLabel,
  ) {
    final overridden = line.isOverridden;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item?.name ?? widget.itemId,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _figure(
                  theme,
                  'Expected',
                  formatQuantity(line.expectedUseMicros, unit),
                ),
                _figure(
                  theme,
                  'Planned',
                  formatQuantity(line.plannedMicros, unit),
                ),
                _figure(
                  theme,
                  'Load',
                  formatQuantity(line.effectiveLoadMicros, unit),
                  struck: overridden
                      ? formatQuantity(line.loadMicros, unit)
                      : null,
                ),
                _figure(
                  theme,
                  'Acquire',
                  formatQuantity(line.acquireMicros, unit),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _narration(snapshot, line, unit, exposureLabel),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (overridden) ...[
              const SizedBox(height: 8),
              Text(
                'Overridden: ${line.override!.reason}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _figure(
    ThemeData theme,
    String label,
    String value, {
    String? struck,
  }) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 110),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(value, style: theme.textTheme.titleMedium),
            if (struck != null)
              Text(
                struck,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
          ],
        ),
      ],
    ),
  );

  /// §9: "median of 2 observed rates × 150 attendance, +10 % reserve,
  /// rounded up to packs of 12, minus 10 on hand".
  String _narration(
    ForecastSnapshotView snapshot,
    ForecastLineView line,
    String unit,
    String exposureLabel,
  ) {
    if (line.evidenceGrade == EvidenceGrade.insufficientData) {
      return 'No comparable confirmed outcomes — set a baseline load below '
          'to plan this item.';
    }
    final count = line.evidence.length;
    final usableOnHand = line.onHandMicros < 0 ? 0 : line.onHandMicros;
    final available = usableOnHand + line.confirmedInboundMicros;
    return 'Median of $count observed rate${count == 1 ? '' : 's'} × '
        '${snapshot.upcomingExposure} $exposureLabel, '
        '+${snapshot.policy.reservePercent} % reserve, rounded up to packs '
        'of ${formatMicros(line.packSizeMicros)} $unit, minus '
        '${formatMicros(available)} $unit on hand.';
  }

  // -------------------------------------------------------- assumptions

  Widget _assumptionsCard(
    ThemeData theme,
    ForecastSnapshotView snapshot,
    ForecastLineView line,
    String unit,
    String exposureLabel,
  ) {
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            row('Exposure', '${snapshot.upcomingExposure} $exposureLabel'),
            row('Policy', '${policyChipLabel(snapshot.policy)} reserve'),
            row(
              'Pack rounding',
              '${formatMicros(line.packSizeMicros)} $unit per pack',
            ),
            row(
              'On hand at generation',
              '${formatMicros(line.onHandMicros)} $unit · '
                  '${absoluteTimeLabel(snapshot.createdAt)}',
            ),
            row(
              'Confirmed inbound',
              '${formatMicros(line.confirmedInboundMicros)} $unit',
            ),
            row(
              'History window',
              'last ${snapshot.historyWindow} closed '
                  'events',
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------- override

  Widget _overrideForm(
    ThemeData theme,
    ForecastSnapshotView snapshot,
    ForecastLineView line,
    String unit,
  ) {
    final snapshotId = snapshot.id as String;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overrides change this plan only. Forecasts learn from '
            'closeouts, never from overrides.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          QuantityFormField(
            key: const ValueKey('override-load'),
            controller: _load,
            labelText: 'New load',
            unitLabel: unit.isEmpty ? null : unit,
            allowZero: true,
            requiredMessage: 'Enter the load to plan instead',
          ),
          const SizedBox(height: 12),
          TextFormField(
            // GlobalKey so the clear path can validate ONLY this field.
            key: _reasonFieldKey,
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Reason (required)',
              helperText: 'Why this plan differs from the engine value',
              border: OutlineInputBorder(),
            ),
            validator: (text) => (text ?? '').trim().length < 3
                ? 'Give a reason (at least 3 characters)'
                : null,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : () => _apply(snapshotId),
            style: FilledButton.styleFrom(minimumSize: primaryButtonMinSize),
            child: const Text('Apply override'),
          ),
          if (line.isOverridden) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _clear(snapshotId),
              style: OutlinedButton.styleFrom(
                minimumSize: primaryButtonMinSize,
              ),
              child: const Text('Clear override'),
            ),
          ],
        ],
      ),
    );
  }

  /// The append-only override log, newest first (§9).
  Widget _overrideHistory(
    ThemeData theme,
    ForecastSnapshotView snapshot,
    String unit,
  ) {
    final history = ref.watch(
      overrideHistoryProvider((
        eventId: widget.eventId,
        snapshotId: snapshot.id as String,
        itemId: widget.itemId,
      )),
    );
    final rows = history.valueOrNull ?? const <OverrideView>[];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 4),
          child: Text('Override history', style: theme.textTheme.titleSmall),
        ),
        for (final entry in rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              entry.overrideLoadMicros == null
                  ? Icons.undo_outlined
                  : Icons.edit_outlined,
            ),
            title: Text(
              entry.overrideLoadMicros == null
                  ? 'Cleared — back to the engine value'
                  : 'Load set to '
                        '${formatQuantity(entry.overrideLoadMicros, unit)}',
            ),
            subtitle: Text(
              '${entry.reason} · ${absoluteTimeLabel(entry.createdAt)}',
            ),
          ),
      ],
    );
  }
}

/// One stored `forecast_evidence` value-copy — exactly what the engine
/// consumed, frozen at generation time. Tap → source event detail.
class _EvidenceRow extends ConsumerWidget {
  const _EvidenceRow({
    required this.evidence,
    required this.unit,
    required this.exposureLabel,
  });

  final EvidenceView evidence;
  final String unit;
  final String exposureLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sourceEventId = evidence.sourceEventId as String;
    final source = ref.watch(eventDetailProvider(sourceEventId)).valueOrNull;
    final title = source == null
        ? sourceEventId
        : '${source.event.name} · ${source.event.scheduledDate}';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => context.push('/events/$sourceEventId'),
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${evidence.exposure} $exposureLabel · depletion '
              '${formatQuantity(evidence.depletionMicros, unit)}',
            ),
            if (evidence.stockout || evidence.approximate)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 12,
                  children: [
                    if (evidence.stockout)
                      _flag(theme, Icons.warning_amber_outlined, 'Ran out'),
                    if (evidence.approximate)
                      _flag(theme, Icons.help_outline, 'Estimate'),
                  ],
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _flag(ThemeData theme, IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
      const SizedBox(width: 4),
      Text(label, style: theme.textTheme.bodySmall),
    ],
  );
}
