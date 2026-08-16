/// One per-item closeout card (design §9 CloseoutScreen): the direct
/// depletion shortcut plus an expandable Loaded / Returned / Waste
/// worksheet. When all three worksheet fields are set the depletion becomes
/// derived, read-only, shown live as `loaded − returned − waste` and
/// captioned "Depletion excludes waste" (§12.3: forecasts learn what SELLS).
/// Toggles: "Ran out" (stockout) and "Estimate" (approximate); "Skip item"
/// records no line. The prefill caption "Planned load was N" comes from the
/// latest snapshot's load/override, blank when none exists.
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
/// Quick fills ("a faster way to check what was used"): two plain word
/// chips for the common extremes. 'Nothing used' writes a direct depletion
/// of 0 — everything came back. 'All gone' writes the loaded value, else
/// the planned-load prefill, and flags the stockout (all gone usually
/// means demand was censored; untoggle it when supply exactly met demand);
/// with neither number on record it invents nothing — it only flags the
/// stockout and focuses the depletion field. Both flow through the same
/// [CloseoutLineCard.onChanged] path typing does, so state recompute, the
/// confirm-flip haptic, and the debounced autosave all fire normally.
/// Hidden on skipped lines and behind a completed worksheet (where the
/// depletion is derived and read-only).
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

  /// Marks the direct-depletion field's subtree so 'All gone' can focus it
  /// when it has no number to offer.
  final GlobalKey _depletionFieldKey = GlobalKey();

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
                          'Planned load was '
                          '${QuantityCodec.format(Quantity.fromMicros(line.plannedLoadMicros!))}'
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

  /// 'Nothing used': everything came back — a confirmed zero, through the
  /// same handler typing reaches (§5: zero is a legal label).
  void _quickFillNothingUsed() {
    widget.line.depletion.text = QuantityCodec.format(Quantity.zero);
    widget.onChanged();
  }

  /// 'All gone': depletion = the loaded value if set, else the planned-load
  /// prefill — and the stockout flag flips ON either way, because all gone
  /// usually means demand was censored (the owner untoggles it when supply
  /// exactly met demand). With neither number on record the chip invents
  /// nothing: it only sets the flag and focuses the depletion field.
  void _quickFillAllGone() {
    final line = widget.line;
    line.stockout = true;
    final loaded = line.loadedQuantity;
    if (loaded != null) {
      line.depletion.text = QuantityCodec.format(loaded);
    } else if (line.plannedLoadMicros != null) {
      line.depletion.text = QuantityCodec.format(
        Quantity.fromMicros(line.plannedLoadMicros!),
      );
    } else {
      _focusDepletionField();
    }
    widget.onChanged();
  }

  /// Focuses the direct-depletion field. [QuantityFormField] owns its
  /// [TextFormField] and exposes no focus node, so walk the keyed subtree —
  /// it contains exactly one [EditableText] — and focus that node.
  void _focusDepletionField() {
    final fieldContext = _depletionFieldKey.currentContext;
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

  /// The counting body shared by both bases: the quick-fill chips, direct
  /// depletion (or the derived read-only display), the expandable
  /// worksheet, and the flags.
  List<Widget> _entryFields(ThemeData theme) {
    final line = widget.line;
    return [
      if (!line.worksheetComplete) ...[
        // Quick fills: plain word chips, one tap for the common extremes.
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              label: const Text('Nothing used'),
              tooltip: 'Everything came back',
              onPressed: _quickFillNothingUsed,
            ),
            ActionChip(
              label: const Text('All gone'),
              tooltip: 'Nothing came back',
              onPressed: _quickFillAllGone,
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      if (line.worksheetComplete)
        _derivedDepletion(theme)
      else
        KeyedSubtree(
          key: _depletionFieldKey,
          child: QuantityFormField(
            controller: line.depletion,
            labelText: 'Depletion',
            unitLabel: line.unitLabel,
            isRequired: false,
            allowZero: true,
            helperText: line.demandBasis == DemandBasis.perEvent
                ? 'What was used or sold — excludes waste.'
                : 'What sold — excludes waste.',
            onChanged: (_) => widget.onChanged(),
            validator: (value) => value.micros > maxDepletionMicros
                ? 'Larger than Loadout supports'
                : null,
          ),
        ),
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
          onChanged: (_) => widget.onChanged(),
        ),
        const SizedBox(height: 12),
        QuantityFormField(
          controller: line.returned,
          labelText: 'Returned',
          unitLabel: line.unitLabel,
          isRequired: false,
          allowZero: true,
          onChanged: (_) => widget.onChanged(),
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

  Widget _derivedDepletion(ThemeData theme) {
    final line = widget.line;
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
    final confirmed = line.confirmed;
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Depletion: '
          '${QuantityCodec.format(Quantity.fromMicros(derived))}'
          '${line.unitSuffix}',
          style: theme.textTheme.titleMedium?.copyWith(
            color: confirmed ? scheme.onPrimaryContainer : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Depletion excludes waste — derived from the worksheet.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: confirmed ? scheme.onPrimaryContainer : null,
          ),
        ),
      ],
    );
  }
}
