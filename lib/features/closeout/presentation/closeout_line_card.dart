/// One per-item closeout card (design §9 CloseoutScreen), leftover-first:
/// the owner counts what is LEFT in the storeroom, so the card leads with
/// "How many are left?" — the `returned` count — and treats used as the
/// arithmetic consequence. Depletion stays the stored label and the
/// forecasting semantics are untouched: depletion = loaded − left over −
/// waste, shown as a derived read-out ("Used: N", excludes waste) the
/// moment the worksheet determines it (§12.3: forecasts learn what SELLS).
/// The expandable worksheet keeps Loaded and Waste, plus a direct "Used"
/// field for lines where counting leftovers makes no sense; a completed
/// worksheet wins over the direct entry exactly as before. Toggles: "Ran
/// out" (stockout) and "Estimate" (approximate); "Skip item" records no
/// line. The prefill caption "Planned load was N" comes from the latest
/// snapshot's load/override, blank when none exists.
///
/// THE one leftover rule, shared verbatim with the scan-to-count sheet via
/// [CloseoutLineController.applyLeftoverDefaults]: committing a leftover
/// count fills a blank loaded from the planned load, and whenever a
/// leftover count and a loaded value coexist a blank waste counts as 0 —
/// the field captions say so — so a leftover count alone can complete a
/// line. Worksheet entry with no leftover count never defaults anything.
///
/// The card carries the design-spec §4 checklist grammar — every state is
/// color + icon + word, the name always fully legible, no strikethrough
/// ever:
///  * **Confirmed** — card tint animates to `primaryContainer` (150 ms, on
///    the owner's own edit), filled check, the word "Confirmed", one light
///    haptic on the flip. Fields stay editable; unconfirming is plain and
///    instant.
///  * **In progress** — an open-but-incomplete worksheet gets a thin
///    `secondary` left stripe + the word "In progress": partial must never
///    look like done.
///  * **Skipped** — neutral, dimmed, the literal word "Skipped".
/// The worksheet opens and closes through a 200 ms `AnimatedSize`. All
/// durations drop to zero when animations are disabled.
///
/// Per-event lines ("about the same every event") get "didn't count it" as
/// a first-class skip instead — the recommended default, because nobody
/// counts soap at midnight and a made-up number would become permanent
/// history the forecast trusts. A skipped line records nothing and teaches
/// nothing, and the card says so. Per-person lines keep today's behaviour.
///
/// Quick fills ("a faster way to check what was used"), in leftover
/// language: 'Everything left' writes left = loaded (else the planned
/// load) and lets the rule derive a used of 0; with neither number on
/// record nothing-used needs no count at all — it IS a direct used of 0,
/// and that is what the chip writes. 'None left' writes left = 0 and flags
/// the stockout (all gone usually means demand was censored; the owner
/// untoggles it when supply exactly met demand), deriving from loaded or
/// the planned load the same way; with neither number on record it invents
/// nothing — it opens the worksheet and hands focus to Loaded, the one
/// number that now determines the line. Both flow through the same
/// [CloseoutLineCard.onChanged] path typing does, so state recompute, the
/// confirm-flip haptic, and the debounced autosave all fire normally.
/// Hidden on skipped lines and behind a completed worksheet (where used is
/// derived and read-only).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/quantity_form_field.dart';
import '../../../app/widgets/warning_banner.dart';
import '../../../core/quantity.dart';
import '../../../core/quantity_codec.dart';
import '../../catalog/domain/demand_basis.dart';

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
    this.demandBasis = DemandBasis.perPerson,
    this.folderId,
  });

  final String itemId;
  final String itemName;

  /// The resolved demand basis this line closes out under: the latest
  /// snapshot line's stored value when one exists, else resolved from the
  /// item/folder via [effectiveDemandBasis]. Drives the "didn't count it"
  /// treatment; never arithmetic. Mutable: the screen resolves it from its
  /// watched providers once their first data arrives.
  DemandBasis demandBasis;

  /// The item's live folder, for the section headers; null = Unfiled.
  String? folderId;

  /// Unit suffix for a legacy measured row ('kg', 'L', …); null for a
  /// counted thing, which is every item created since schema v2.
  final String? unitLabel;

  /// The suffix as it appears in running text: `' kg'`, or nothing.
  String get unitSuffix => unitLabel == null ? '' : ' $unitLabel';

  /// "Planned load was N" caption source; null when no snapshot exists.
  final int? plannedLoadMicros;

  final TextEditingController depletion = TextEditingController();
  final TextEditingController loaded = TextEditingController();

  /// The leftover count — "How many are left?". `returned` stays the
  /// stored name (schema and domain rename NOTHING); only the UI words
  /// changed.
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

  /// All three worksheet numbers parse — used is derived, read-only.
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

  /// Counts toward "X of Y confirmed" (skips never do).
  bool get confirmed => !skipped && effectiveDepletion != null;

  /// True once anything has been entered on a still-unconfirmed line — the
  /// §4 mid-state: partial must never look like done.
  bool get inProgress =>
      !done &&
      (worksheetOpen ||
          depletion.text.trim().isNotEmpty ||
          loaded.text.trim().isNotEmpty ||
          returned.text.trim().isNotEmpty ||
          waste.text.trim().isNotEmpty);

  /// True when a leftover count could complete this line by itself: a
  /// loaded value exists, or the planned load stands ready to fill one.
  /// Drives the "waste counts as 0" captions here and on the scan sheet.
  bool get leftoverCanComplete =>
      loaded.text.trim().isNotEmpty || plannedLoadMicros != null;

  /// THE one leftover rule — the card's "How many are left?" field, its
  /// quick fills, and the scan-to-count sheet all commit through here so
  /// there are never two subtly different behaviours. On a leftover
  /// commit: a blank loaded fills from the planned load, and once a
  /// leftover count and a loaded value coexist a blank waste counts as 0 —
  /// so a leftover count alone can complete a line. No leftover count, no
  /// defaults: plain worksheet entry never invents a number.
  ///
  /// [fillLoadedFromPlan] is false when the trigger is the Loaded field
  /// itself (clearing it must not snap the planned load straight back in);
  /// the waste-counts-as-0 half still applies, so leftover-then-loaded and
  /// loaded-then-leftover land identically.
  void applyLeftoverDefaults({bool fillLoadedFromPlan = true}) {
    if (returned.text.trim().isEmpty) return;
    if (fillLoadedFromPlan &&
        loaded.text.trim().isEmpty &&
        plannedLoadMicros != null) {
      loaded.text = QuantityCodec.format(
        Quantity.fromMicros(plannedLoadMicros!),
      );
    }
    if (loaded.text.trim().isNotEmpty && waste.text.trim().isEmpty) {
      waste.text = QuantityCodec.format(Quantity.zero);
    }
  }
}

class CloseoutLineCard extends StatefulWidget {
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
  State<CloseoutLineCard> createState() => _CloseoutLineCardState();
}

class _CloseoutLineCardState extends State<CloseoutLineCard> {
  /// Last seen confirmed state, so the check-off haptic fires exactly once
  /// per flip into confirmed — never per keystroke, never on rebuilds.
  late bool _wasConfirmed = widget.line.confirmed;

  /// Marks the Loaded field's subtree so 'None left' can focus it when it
  /// has no number to derive from.
  final GlobalKey _loadedFieldKey = GlobalKey();

  @override
  void didUpdateWidget(CloseoutLineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nowConfirmed = widget.line.confirmed;
    if (nowConfirmed && !_wasConfirmed) {
      // The §4 check-off moment: light impact per line confirmed.
      HapticFeedback.lightImpact();
    }
    _wasConfirmed = nowConfirmed;
  }

  Duration _duration(int milliseconds) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Duration(milliseconds: milliseconds);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final line = widget.line;
    final confirmed = line.confirmed;
    final skipped = line.skipped;
    final inProgress = line.inProgress;

    // §4 grammar: confirmed = primaryContainer tint; skipped = neutral,
    // dimmed; pending = neutral card. Word + icon + color, always.
    final cardColor = confirmed
        ? scheme.primaryContainer
        : scheme.surfaceContainerLow;
    final contentInk = confirmed
        ? scheme.onPrimaryContainer
        : skipped
        ? scheme.onSurfaceVariant
        : scheme.onSurface;
    final (stateWord, stateColor) = confirmed
        ? ('Confirmed', scheme.onPrimaryContainer)
        : skipped
        ? ('Skipped', scheme.onSurfaceVariant)
        : inProgress
        ? ('In progress', scheme.secondary)
        : (null, scheme.onSurface);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        // The check-off tint change: 150 ms on the owner's own edit.
        duration: _duration(150),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: AnimatedSize(
                // Worksheet open/close (§7 motion budget).
                duration: _duration(200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          confirmed
                              ? Icons.check_circle
                              : skipped
                              ? Icons.remove_circle_outline
                              : Icons.radio_button_unchecked,
                          color: confirmed
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                          semanticLabel: line.done
                              ? '${line.itemName}: done'
                              : '${line.itemName}: to do',
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            line.itemName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: contentInk,
                            ),
                          ),
                        ),
                        if (stateWord != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            stateWord,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: stateColor,
                            ),
                          ),
                        ],
                        if (line.demandBasis == DemandBasis.perPerson)
                          TextButton(
                            onPressed: () {
                              line.skipped = !line.skipped;
                              widget.onChanged();
                            },
                            child: Text(
                              line.skipped ? 'Include item' : 'Skip item',
                            ),
                          ),
                      ],
                    ),
                    if (line.plannedLoadMicros != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          // Straight off the forecast snapshot, so it carries
                          // the engine's micros residue — display-rounded.
                          'Planned load was '
                          '${QuantityCodec.formatDisplayMicros(line.plannedLoadMicros!)}'
                          '${line.unitSuffix}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: contentInk,
                          ),
                        ),
                      ),
                    if (line.demandBasis == DemandBasis.perEvent) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilterChip(
                          label: const Text("Didn't count it"),
                          tooltip: 'Recommended when nobody counted',
                          selected: line.skipped,
                          onSelected: (selected) {
                            line.skipped = selected;
                            widget.onChanged();
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (line.skipped)
                        Text(
                          'Nothing recorded — a skipped line teaches the '
                          "forecast nothing, and that's better than a "
                          'made-up number.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: contentInk,
                          ),
                        )
                      else
                        ..._entryFields(theme),
                    ] else if (line.skipped)
                      Text(
                        'Skipped — nothing will be recorded for this item.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: contentInk,
                        ),
                      )
                    else ...[
                      const SizedBox(height: 4),
                      ..._entryFields(theme),
                    ],
                  ],
                ),
              ),
            ),
            // The §4 mid-state stripe: thin secondary left border + the
            // word — an open worksheet must never look like done.
            if (inProgress)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 4, color: scheme.secondary),
              ),
          ],
        ),
      ),
    );
  }

  /// 'Everything left': left = loaded, else the planned load, and the one
  /// leftover rule derives a used of 0. With neither number on record
  /// nothing-used needs no count at all — it IS a direct used of 0 (§5:
  /// zero is a legal label), written through the same handler typing
  /// reaches. Never touches the stockout flag.
  void _quickFillEverythingLeft() {
    final line = widget.line;
    final loaded = line.loadedQuantity;
    if (loaded != null) {
      line.returned.text = QuantityCodec.format(loaded);
      line.applyLeftoverDefaults();
    } else if (line.plannedLoadMicros != null) {
      line.returned.text = QuantityCodec.format(
        Quantity.fromMicros(line.plannedLoadMicros!),
      );
      line.applyLeftoverDefaults();
    } else {
      line.depletion.text = QuantityCodec.format(Quantity.zero);
    }
    widget.onChanged();
  }

  /// 'None left': left = 0 — a real count, not an invention — and the
  /// stockout flag flips ON, because all gone usually means demand was
  /// censored (the owner untoggles it when supply exactly met demand). The
  /// one leftover rule then derives used from loaded or the planned load;
  /// with neither on record the zero alone cannot say how many were used,
  /// so the chip opens the worksheet and hands focus to Loaded — the one
  /// number that now determines the line.
  void _quickFillNoneLeft() {
    final line = widget.line;
    line.stockout = true;
    line.returned.text = QuantityCodec.format(Quantity.zero);
    line.applyLeftoverDefaults();
    if (!line.worksheetComplete && line.effectiveDepletion == null) {
      line.worksheetOpen = true;
      // The field exists only after the rebuild opens the worksheet.
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusLoadedField());
    }
    widget.onChanged();
  }

  /// Focuses the Loaded field. [QuantityFormField] owns its
  /// [TextFormField] and exposes no focus node, so walk the keyed subtree —
  /// it contains exactly one [EditableText] — and focus that node.
  void _focusLoadedField() {
    final fieldContext = _loadedFieldKey.currentContext;
    if (fieldContext == null) return;
    FocusNode? node;
    void visit(Element element) {
      if (node != null) return;
      final candidate = element.widget;
      if (candidate is EditableText) {
        node = candidate.focusNode;
        return;
      }
      element.visitChildren(visit);
    }

    (fieldContext as Element).visitChildren(visit);
    node?.requestFocus();
  }

  /// The counting body shared by both bases: the quick-fill chips, the
  /// leading "How many are left?" count, the derived used read-out, the
  /// expandable worksheet (loaded, waste, and the direct used
  /// alternative), and the flags.
  List<Widget> _entryFields(ThemeData theme) {
    final line = widget.line;
    return [
      if (!line.worksheetComplete) ...[
        // Quick fills: plain word chips, one tap for the common extremes.
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              label: const Text('Everything left'),
              tooltip: 'Nothing was used',
              onPressed: _quickFillEverythingLeft,
            ),
            ActionChip(
              label: const Text('None left'),
              tooltip: 'All gone — turns on Ran out',
              onPressed: _quickFillNoneLeft,
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      // The lead question — the owner counts leftovers, so the card asks
      // for leftovers. Writes the `returned` count; fractions allowed,
      // exactly like the scan sheet (same field, same rule).
      QuantityFormField(
        controller: line.returned,
        labelText: 'How many are left?',
        unitLabel: line.unitLabel,
        isRequired: false,
        allowZero: true,
        allowFractions: true,
        helperText: line.worksheetComplete
            ? null
            : line.leftoverCanComplete
            ? 'Waste counts as 0 unless you set it in the worksheet.'
            : 'Add loaded in the worksheet to work out what was used.',
        onChanged: (_) {
          line.applyLeftoverDefaults();
          widget.onChanged();
        },
      ),
      if (line.worksheetComplete) ...[
        const SizedBox(height: 8),
        _derivedUsed(theme),
      ],
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () {
            line.worksheetOpen = !line.worksheetOpen;
            widget.onChanged();
          },
          icon: Icon(
            line.worksheetOpen ? Icons.expand_less : Icons.expand_more,
          ),
          label: Text(
            line.worksheetOpen
                ? 'Hide worksheet'
                : 'Worksheet (loaded − left over − waste)',
          ),
        ),
      ),
      if (line.worksheetOpen) ...[
        const SizedBox(height: 8),
        KeyedSubtree(
          key: _loadedFieldKey,
          child: QuantityFormField(
            controller: line.loaded,
            labelText: 'Loaded',
            unitLabel: line.unitLabel,
            isRequired: false,
            allowZero: true,
            onChanged: (_) {
              // The waste-counts-as-0 half of the rule only: clearing
              // Loaded must not snap the planned load straight back in.
              line.applyLeftoverDefaults(fillLoadedFromPlan: false);
              widget.onChanged();
            },
          ),
        ),
        const SizedBox(height: 12),
        QuantityFormField(
          controller: line.waste,
          labelText: 'Waste',
          unitLabel: line.unitLabel,
          isRequired: false,
          allowZero: true,
          onChanged: (_) => widget.onChanged(),
        ),
        if (!line.worksheetComplete) ...[
          const SizedBox(height: 12),
          // The alternative for lines where counting leftovers makes no
          // sense; a completed worksheet derivation wins over it, as ever.
          QuantityFormField(
            controller: line.depletion,
            labelText: 'Used',
            unitLabel: line.unitLabel,
            isRequired: false,
            allowZero: true,
            helperText: line.demandBasis == DemandBasis.perEvent
                ? 'Or enter used directly — what was used or sold. '
                      'Excludes waste.'
                : 'Or enter used directly — what sold. Excludes waste.',
            onChanged: (_) => widget.onChanged(),
            validator: (value) => value.micros > maxDepletionMicros
                ? 'Larger than Loadout supports'
                : null,
          ),
        ],
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
              widget.onChanged();
            },
          ),
          FilterChip(
            label: const Text('Estimate'),
            tooltip: 'Approximate numbers',
            selected: line.approximate,
            onSelected: (selected) {
              line.approximate = selected;
              widget.onChanged();
            },
          ),
        ],
      ),
    ];
  }

  /// The derived read-out: used = loaded − left over − waste, in the
  /// depletion's stored semantics (excludes waste). Invalid arithmetic
  /// warns instead — a negative worksheet must never look confirmable.
  Widget _derivedUsed(ThemeData theme) {
    final line = widget.line;
    final derived = line.derivedDepletionMicros!;
    if (derived < 0) {
      return const WarningBanner(
        message: 'Left over and waste exceed loaded — check the worksheet.',
      );
    }
    if (derived > maxDepletionMicros) {
      return const WarningBanner(
        message: 'Used is larger than Loadout supports.',
      );
    }
    final confirmed = line.confirmed;
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Used: '
          '${QuantityCodec.format(Quantity.fromMicros(derived))}'
          '${line.unitSuffix}',
          style: theme.textTheme.titleMedium?.copyWith(
            color: confirmed ? scheme.onPrimaryContainer : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Used excludes waste — derived from the worksheet.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: confirmed ? scheme.onPrimaryContainer : null,
          ),
        ),
      ],
    );
  }
}
