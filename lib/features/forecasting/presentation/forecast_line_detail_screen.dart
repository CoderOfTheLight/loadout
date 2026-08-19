/// `/events/:eventId/forecast/:itemId` — one forecast line, said once.
///
/// This screen used to be the data model with a Scaffold around it: a
/// four-cell grid (Expected / Planned / Load / Acquire), then an
/// "Assumptions" table of Exposure, Policy, Basis, "You had at generation",
/// "Confirmed inbound" and "History window", then the arithmetic narrated a
/// second time underneath. Six of those rows are inputs to a calculation
/// nobody standing in a kitchen is going to re-run, and none of them is
/// something she can check.
///
/// What she CAN check is the past events themselves. So the screen is now:
///
///  1. ONE sentence — what to bring, what that rests on, what is on the
///     shelf ([forecastLineSentence]), read off exactly the fields the table
///     printed;
///  2. the stored evidence value-copies, one tappable row each, which are
///     the only thing on the screen a human can verify against her own
///     memory;
///  3. any warning the sentence does not already speak for;
///  4. the override — the one ACTION here — and its append-only log (§9,
///     §12.17: mandatory reason >= 3 chars, clear appends a NULL-load row).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/unit_display.dart';
import '../../../app/widgets/content_column.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/quantity_form_field.dart';
import '../../../core/units.dart';
import '../../catalog/domain/demand_basis.dart';
import '../../events/domain/event.dart';
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
    final item = ref
        .watch(forecastItemIndexProvider)
        .valueOrNull?[widget.itemId];
    return Scaffold(
      appBar: AppBar(title: Text(item?.name ?? 'Forecast line')),
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
          return _body(context, snapshot, line, item?.unit);
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ForecastSnapshotView snapshot,
    ForecastLineView line,
    ItemUnit? unit,
  ) {
    final theme = Theme.of(context);
    final status = ref
        .watch(eventDetailProvider(widget.eventId))
        .valueOrNull
        ?.event
        .status;
    final editable =
        status == EventStatus.planned || status == EventStatus.active;
    // "Set a baseline" entry (§9): prefill the reason once for lines with
    // no number at all and no override yet. A "1 serves N" line already has
    // a plan, so it is not a baseline-setting exercise.
    if (!_reasonPrefilled &&
        editable &&
        line.basis == ForecastBasis.insufficientData &&
        line.override == null &&
        _reason.text.isEmpty) {
      _reason.text = 'baseline';
      _reasonPrefilled = true;
    }
    final exposureLabel = exposureLabelOf(snapshot);
    // The cold-start warnings say, in the engine's vocabulary, exactly what
    // the sentence already said in the owner's. Everything else still
    // renders verbatim.
    final warnings = isColdStartLine(line)
        ? [
            for (final warning in line.warnings)
              if (!isColdStartWarning(warning)) warning,
          ]
        : line.warnings;
    return ContentColumn(
      child: ListView(
        children: [
          _AnswerCard(
            line: line,
            unit: unit,
            upcomingExposure: snapshot.upcomingExposure,
            exposureLabel: exposureLabel,
          ),
          if (line.evidence.isNotEmpty) ...[
            _sectionTitle(theme, 'What this is based on'),
            for (final evidence in line.evidence)
              _EvidenceRow(
                evidence: evidence,
                unit: unit,
                exposureLabel: exposureLabel,
                perEvent: line.demandBasis == DemandBasis.perEvent,
                contextYear: instantYear(snapshot.createdAt),
              ),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: Space.l),
            // Verbatim stored warnings — engine and application-layer notes
            // alike — on the semantic amber container (spec §5), the same
            // visual weight the review screen gives them.
            for (final warning in warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: StatusColors.of(context).warning,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_outlined,
                        size: 20,
                        color: StatusColors.of(context).onWarning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          warning,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: StatusColors.of(context).onWarning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          _sectionTitle(theme, 'Change this number'),
          if (editable) _overrideForm(theme, snapshot, line, unit),
          _overrideHistory(theme, snapshot, unit),
          const SizedBox(height: Space.xl),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(title, style: theme.textTheme.titleMedium),
  );

  // ----------------------------------------------------------- override

  Widget _overrideForm(
    ThemeData theme,
    ForecastSnapshotView snapshot,
    ForecastLineView line,
    ItemUnit? unit,
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
            unitLabel: unitFieldLabel(unit ?? ItemUnit.each),
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
    ItemUnit? unit,
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

/// The whole answer, in one sentence.
///
/// The instruction leads in [Numerals.glance] and the evidence follows in
/// body text, in ONE paragraph rather than a figure floating over a caption:
/// at 200 % scale a wrapped paragraph simply grows, where a grid of labelled
/// figures has to choose between clipping and reflowing into nonsense.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.line,
    required this.unit,
    required this.upcomingExposure,
    required this.exposureLabel,
  });

  final ForecastLineView line;
  final ItemUnit? unit;
  final int upcomingExposure;
  final String exposureLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '${forecastLineInstruction(line, unit: unit)} ',
                style: Numerals.glance(theme.textTheme),
              ),
              TextSpan(
                text: forecastLineExplanation(
                  line,
                  upcomingExposure: upcomingExposure,
                  exposureLabel: exposureLabel,
                  unit: unit,
                ),
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
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
    required this.perEvent,
    required this.contextYear,
  });

  final EvidenceView evidence;
  final ItemUnit? unit;
  final String exposureLabel;

  /// True when the line ignores headcount, in which case quoting one here
  /// would suggest the number moves with it.
  final bool perEvent;

  /// The year a bare "Aug 7" is read against — see [shortEventDate].
  final int contextYear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sourceEventId = evidence.sourceEventId as String;
    final source = ref.watch(eventDetailProvider(sourceEventId)).valueOrNull;
    final used = 'used ${formatQuantity(evidence.depletionMicros, unit)}';
    final title = source == null
        ? '$sourceEventId — $used'
        : '${source.event.name} '
              '(${shortEventDate(source.event.scheduledDate, contextYear: contextYear)})'
              ' — $used';
    final flagged = evidence.stockout || evidence.approximate;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => context.push('/events/$sourceEventId'),
        title: Text(title),
        subtitle: perEvent && !flagged
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!perEvent)
                    Text('for ${evidence.exposure} $exposureLabel'),
                  if (flagged)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 12,
                        children: [
                          if (evidence.stockout)
                            _flag(
                              theme,
                              Icons.warning_amber_outlined,
                              'Ran out',
                            ),
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
