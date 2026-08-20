/// One per-item closeout card (design §9 CloseoutScreen), rebuilt AGAIN for
/// the person actually doing the count: a volunteer at the end of a long day
/// who knows Excel and Word and nothing else.
///
/// Yesterday's card asked for two numbers and carried eight controls
/// (`Loaded`, `Left`, `Everything left`, `None left`, `Ran out`, `Skip`,
/// `Some was thrown out`, `More`). The owner's verdict was that it is still
/// too complicated. So the face of the card is now ONE question and three
/// words:
///
///  * **`How many are left?`** — one box. That is the job.
///  * **`All gone`** and **`None used`** — the two shortcuts. `All gone`
///    writes left = 0; `None used` writes left = loaded (nothing used).
///  * **`More`** — the overflow that holds everything else: *Change what was
///    loaded*, *Some was thrown out*, *Enter what was used instead*, *Skip
///    this item*.
///
/// Four controls on a normal card, down from eight.
///
/// **Loaded is no longer a box on the face.** It is still prefilled from the
/// plan exactly as it was, but it reads as a quiet line of text — `Loaded
/// 42` — and is edited through More → *Change what was loaded*. The one
/// exception is a line the plan says nothing about ([plannedLoadMicros] is
/// null): a leftover count is meaningless without a loaded figure, so THERE
/// the box comes back inline. That keeps a single grammar — count what is
/// left, let the app do the arithmetic — on every line, and keeps both
/// shortcuts meaningful (`All gone` cannot say what was used without a
/// loaded figure either).
///
/// **`Ran out` is contextual, not permanent.** It drives stockout handling
/// in the forecast — a sold-out item that is not marked teaches the forecast
/// that demand was exactly what you brought — so it may never disappear
/// silently, but it has no business on a card where nothing ran out. It
/// appears as a question, `Did you run out?` / Yes / No, exactly when the
/// line reads as empty: a leftover count of 0, or the flag already on.
/// `All gone` answers it Yes on the way past (all gone usually means demand
/// was censored; the owner taps No when supply exactly met demand). A hand-
/// typed 0 leaves it UNANSWERED: the line still confirms — the question is
/// never a gate — but the card stays open so the question is asked rather
/// than lost.
///
/// THE one leftover rule, shared verbatim with the scan-to-count sheet via
/// [CloseoutLineController.applyLeftoverDefaults]: committing a leftover
/// count fills a blank loaded from the planned load, and whenever a leftover
/// count and a loaded value coexist a blank waste counts as 0 — so a
/// leftover count alone completes a line.
///
/// The card carries the design-spec §4 checklist grammar — every state is
/// color + icon + word, the name always fully legible, no strikethrough
/// ever:
///  * **Confirmed** — card tint animates to `primaryContainer` (150 ms, on
///    the owner's own edit), filled check, the word "Confirmed", one light
///    haptic on the flip.
///  * **In progress** — a started-but-incomplete line gets a thin
///    `secondary` left stripe + the word "In progress": partial must never
///    look like done.
///  * **Skipped** — neutral, dimmed, the literal word "Skipped".
///
/// A card that is DONE (confirmed or skipped) collapses to one row — name,
/// "Used: N", the state word — and is tappable to reopen. That is most of
/// the scrolling win on a sixty-item worksheet. It re-opens on its own if
/// focus lands inside it, and never collapses out from under a typing
/// finger: the collapse waits for focus to leave.
///
/// 'Estimate' is gone from the card; `approximate` is still written, just
/// never set here.
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

/// Above this text scale the state word drops under the item's name instead
/// of sitting beside it: at 200 % on a 320 dp phone the word alone is wider
/// than what is left of the row.
const double _stackStateWordAboveScale = 1.3;

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
  }) {
    fillLoadedFromPlan();
  }

  final String itemId;
  final String itemName;

  /// The resolved demand basis this line closes out under: the latest
  /// snapshot line's stored value when one exists, else resolved from the
  /// item/folder via [effectiveDemandBasis]. Drives the screen's
  /// fresh-closeout skip default; never arithmetic, and never the card's
  /// wording — Skip is one word for both bases now.
  DemandBasis demandBasis;

  /// The item's live folder, for the section headers; null = Unfiled.
  String? folderId;

  /// Unit suffix for a legacy measured row ('kg', 'L', …); null for a
  /// counted thing, which is every item created since schema v2.
  final String? unitLabel;

  /// The suffix as it appears in running text: `' kg'`, or nothing.
  String get unitSuffix => unitLabel == null ? '' : ' $unitLabel';

  /// What the plan says was loaded; null when no snapshot exists. It is
  /// PREFILLED into [loaded] and read out as a quiet line of text rather
  /// than asked for again.
  final int? plannedLoadMicros;

  final TextEditingController depletion = TextEditingController();
  final TextEditingController loaded = TextEditingController();

  /// The leftover count — "How many are left?". `returned` stays the stored
  /// name (schema and domain rename NOTHING); only the UI words changed.
  final TextEditingController returned = TextEditingController();
  final TextEditingController waste = TextEditingController();

  /// Bumped when something OTHER than this card's own controls changes the
  /// line — the scan-to-count sheet, a draft restore, "skip the rest" — so a
  /// card that is only listening to its text controllers still rebuilds.
  final ValueNotifier<int> externalChanges = ValueNotifier<int>(0);

  bool stockout = false;
  bool approximate = false;
  bool skipped = false;

  /// True once somebody has actually answered "did you run out?" — either by
  /// tapping Yes/No, or by taking the `All gone` shortcut, which answers it
  /// Yes on the way past. A hand-typed leftover 0 leaves it false.
  bool stockoutAnswered = false;

  /// True when the owner asked for the thrown-out box; the value itself
  /// defaults to 0 and is written whether or not the box was ever shown.
  bool wasteOpen = false;

  /// True when the owner asked to change what was loaded. Loaded is a quiet
  /// line of text until then — except on a line the plan says nothing about,
  /// where [showsLoadedBox] puts the box on the face regardless.
  bool loadedOpen = false;

  /// True on the lines where counting leftovers means nothing and the owner
  /// entered what was USED directly. A mode, not a fourth field: the box is
  /// swapped rather than added, so nothing has to take precedence over
  /// anything.
  bool directEntry = false;

  void dispose() {
    depletion.dispose();
    loaded.dispose();
    returned.dispose();
    waste.dispose();
    externalChanges.dispose();
  }

  /// Announces a change made from outside the card's own controls.
  void markExternallyChanged() => externalChanges.value++;

  static Quantity? _parse(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : QuantityFormField.tryParse(text);
  }

  Quantity? get loadedQuantity => _parse(loaded);
  Quantity? get returnedQuantity => _parse(returned);
  Quantity? get wasteQuantity => _parse(waste);
  Quantity? get directDepletion => _parse(depletion);

  /// The planned load as it goes into the Loaded box: display-rounded,
  /// because the snapshot carries the engine's micros residue and nobody
  /// should meet "5.999999" in an editable field.
  String? get plannedLoadText => plannedLoadMicros == null
      ? null
      : QuantityCodec.formatDisplayMicros(plannedLoadMicros!);

  /// True while Loaded still holds exactly the number the plan put there —
  /// what the header says is "just a starting value", and what keeps an
  /// untouched line from claiming to be in progress.
  bool get loadedIsPlanPrefill {
    final text = plannedLoadText;
    return text != null && loaded.text == text;
  }

  /// Fills a blank Loaded from the plan. Runs once at construction and
  /// again when the card comes back from direct entry.
  void fillLoadedFromPlan() {
    final text = plannedLoadText;
    if (text != null && loaded.text.trim().isEmpty) {
      loaded.text = text;
    }
  }

  /// Whether Loaded is a BOX on the face of the card rather than a quiet
  /// line of text: because the owner asked to change it, or because the plan
  /// says nothing about this line and a leftover count would otherwise have
  /// nothing to subtract from.
  bool get showsLoadedBox =>
      !directEntry && (loadedOpen || plannedLoadMicros == null);

  /// What the quiet `Loaded 42` line reads: whatever is actually on the
  /// line, which is the plan's prefill until somebody changes it (a draft
  /// restore or a revise can put its own figure there).
  String get loadedReadout {
    final text = loaded.text.trim();
    return text.isEmpty ? (plannedLoadText ?? '—') : text;
  }

  /// Both numbers the derivation needs are on record.
  bool get canDerive => loadedQuantity != null && returnedQuantity != null;

  /// `loaded − left − thrown out` in micros (a blank thrown-out counts as
  /// 0); null while the two numbers are not both there. May be negative.
  int? get derivedDepletionMicros => canDerive
      ? loadedQuantity!.micros -
            returnedQuantity!.micros -
            (wasteQuantity?.micros ?? 0)
      : null;

  /// The depletion this line would confirm, or null while invalid or
  /// incomplete. A zero is a legal label (§5).
  Quantity? get effectiveDepletion {
    if (!directEntry) {
      final derived = derivedDepletionMicros;
      if (derived != null) {
        if (derived < 0 || derived > maxDepletionMicros) return null;
        return Quantity.fromMicros(derived);
      }
    }
    // 'None used' on a line with no numbers at all writes a used of 0
    // straight here; so does the overflow's direct-entry mode.
    final direct = directDepletion;
    if (direct == null || direct.micros > maxDepletionMicros) return null;
    return direct;
  }

  /// Done = confirmed (has a legal depletion) or deliberately skipped.
  bool get done => skipped || effectiveDepletion != null;

  /// Counts toward "X of Y confirmed" (skips never do).
  bool get confirmed => !skipped && effectiveDepletion != null;

  /// True once anything has been entered on a still-unconfirmed line — the
  /// §4 mid-state: partial must never look like done. A Loaded still equal
  /// to the plan's prefill is not "entered".
  bool get inProgress =>
      !done &&
      (wasteOpen ||
          directEntry ||
          loadedOpen ||
          depletion.text.trim().isNotEmpty ||
          returned.text.trim().isNotEmpty ||
          waste.text.trim().isNotEmpty ||
          (loaded.text.trim().isNotEmpty && !loadedIsPlanPrefill));

  /// True when a leftover count could complete this line by itself: a
  /// loaded value exists, or the planned load stands ready to fill one.
  bool get leftoverCanComplete =>
      loaded.text.trim().isNotEmpty || plannedLoadMicros != null;

  /// The line reads as EMPTY — nothing was left — so "did you run out?" is
  /// a question worth asking. A flag already on keeps it on screen too: it
  /// must never vanish from under an answer somebody gave.
  ///
  /// Direct entry has no leftover count to read, and the flag would
  /// otherwise be unreachable there, so any direct figure asks.
  bool get asksStockout =>
      !skipped &&
      (stockout ||
          (directEntry
              ? directDepletion != null
              : returnedQuantity?.micros == 0));

  /// A hand-typed leftover 0 that nobody has interpreted yet. The line still
  /// confirms — this is never a gate — but the card refuses to fold away
  /// with the question unasked.
  bool get stockoutUnanswered =>
      !skipped &&
      !directEntry &&
      !stockoutAnswered &&
      returnedQuantity?.micros == 0;

  /// Swaps the leftover question for one "Used" box. The leftover numbers
  /// are cleared so the draft never carries two contradictory stories.
  void useDirectEntry() {
    directEntry = true;
    loaded.clear();
    returned.clear();
    waste.clear();
    wasteOpen = false;
    loadedOpen = false;
  }

  /// Back to counting leftovers: the direct number goes, the plan's
  /// starting value comes back.
  void useLeftoverEntry() {
    directEntry = false;
    depletion.clear();
    fillLoadedFromPlan();
  }

  /// Records an answer to "did you run out?".
  void answerStockout(bool ranOut) {
    stockout = ranOut;
    stockoutAnswered = true;
  }

  /// THE one leftover rule — the card's leftover box, its shortcuts, and the
  /// scan-to-count sheet all commit through here so there are never two
  /// subtly different behaviours. On a leftover commit: a blank loaded
  /// fills from the planned load, and once a leftover count and a loaded
  /// value coexist a blank waste counts as 0 — so a leftover count alone
  /// can complete a line. No leftover count, no defaults.
  ///
  /// [fillLoadedFromPlan] is false when the trigger is the Loaded box
  /// itself (clearing it must not snap the planned load straight back in);
  /// the waste-counts-as-0 half still applies, so leftover-then-loaded and
  /// loaded-then-leftover land identically.
  void applyLeftoverDefaults({bool fillLoadedFromPlan = true}) {
    if (returned.text.trim().isEmpty) return;
    if (fillLoadedFromPlan) {
      this.fillLoadedFromPlan();
    }
    if (loaded.text.trim().isNotEmpty && waste.text.trim().isEmpty) {
      waste.text = QuantityCodec.format(Quantity.zero);
    }
  }
}

/// The items behind the card's overflow.
enum _LineMenuAction {
  changeLoaded,
  throwSomeOut,
  useDirect,
  useLeftover,
  skip,
  unskip,
}

class CloseoutLineCard extends StatefulWidget {
  const CloseoutLineCard({
    super.key,
    required this.line,
    required this.onChanged,
  });

  final CloseoutLineController line;

  /// Fires on every edit/toggle — the screen refreshes its counters and
  /// schedules the debounced draft autosave. It does NOT rebuild the card
  /// list: each card owns its own listeners.
  final VoidCallback onChanged;

  @override
  State<CloseoutLineCard> createState() => _CloseoutLineCardState();
}

class _CloseoutLineCardState extends State<CloseoutLineCard> {
  /// Last seen confirmed state, so the check-off haptic fires exactly once
  /// per flip into confirmed — never per keystroke, never on rebuilds.
  late bool _wasConfirmed = widget.line.confirmed;

  /// False = the one-row summary. A line that is already done when the card
  /// first builds (draft restore, revise, the per-event skip default) opens
  /// collapsed.
  late bool _open = _wantsOpen;

  /// Whether focus is anywhere inside this card — the signal that says a
  /// finger is still working here, so a card that just became done must not
  /// fold up yet.
  bool _hasFocus = false;

  /// Marks the Loaded box's subtree so 'All gone' can focus it when it has
  /// no number to derive from.
  final GlobalKey _loadedFieldKey = GlobalKey();

  /// True while this card's overflow menu is showing. The menu takes focus,
  /// which would otherwise fold a finished card away underneath itself —
  /// and the item you were about to pick with it.
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    _subscribe(widget.line);
  }

  @override
  void dispose() {
    _unsubscribe(widget.line);
    super.dispose();
  }

  /// Everything that can change a line's numbers without going through one
  /// of this card's own handlers.
  static List<Listenable> _listenablesOf(CloseoutLineController line) => [
    line.loaded,
    line.returned,
    line.waste,
    line.depletion,
    line.externalChanges,
  ];

  void _subscribe(CloseoutLineController line) {
    for (final listenable in _listenablesOf(line)) {
      listenable.addListener(_onLineChanged);
    }
  }

  void _unsubscribe(CloseoutLineController line) {
    for (final listenable in _listenablesOf(line)) {
      listenable.removeListener(_onLineChanged);
    }
  }

  void _onLineChanged() {
    if (!mounted) return;
    setState(_sync);
  }

  @override
  void didUpdateWidget(CloseoutLineCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.line, widget.line)) {
      _unsubscribe(oldWidget.line);
      _subscribe(widget.line);
      _open = _wantsOpen;
      _wasConfirmed = widget.line.confirmed;
    }
    _sync();
  }

  /// A card wants to be open while there is still something to do on it —
  /// including an unanswered "did you run out?", which is the one question
  /// that confirms the line without being answered.
  bool get _wantsOpen =>
      _menuOpen || !widget.line.done || widget.line.stockoutUnanswered;

  /// The once-per-flip side effects, shared by every path that can change
  /// the line: the §4 check-off haptic, and re-opening a card that stopped
  /// being done.
  void _sync() {
    final nowConfirmed = widget.line.confirmed;
    if (nowConfirmed && !_wasConfirmed) {
      // The §4 check-off moment: light impact per line confirmed.
      HapticFeedback.lightImpact();
    }
    _wasConfirmed = nowConfirmed;
    if (_wantsOpen) _open = true;
  }

  /// One of the card's own controls changed something. [collapseWhenDone]
  /// is for the controls that FINISH a line in a single tap — a shortcut,
  /// Skip — where folding the card away immediately is the point. Typing
  /// never collapses under the finger; that waits for focus to leave.
  void _edited({bool collapseWhenDone = false}) {
    setState(() {
      _sync();
      if (collapseWhenDone && !_wantsOpen) {
        _open = false;
        FocusScope.of(context).unfocus();
      }
    });
    widget.onChanged();
  }

  /// Focus moved in or out of this card. A done card folds up as soon as
  /// the keyboard leaves it; deferred to the next frame because focus
  /// notifications can land mid-build.
  void _onFocusChange(bool hasFocus) {
    final wantOpen = hasFocus || _wantsOpen;
    if (wantOpen == _open) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final stillWanted = _hasFocus || _wantsOpen;
      if (_open != stillWanted) setState(() => _open = stillWanted);
    });
  }

  /// True once the system text is big enough that a row of two things stops
  /// fitting side by side on a narrow phone: the state word then goes under
  /// the item's name rather than beside it.
  bool get _bigText =>
      MediaQuery.textScalerOf(context).scale(16) >
      16 * _stackStateWordAboveScale;

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
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (hasFocus) {
          _hasFocus = hasFocus;
          _onFocusChange(hasFocus);
        },
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
              if (_open)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _headerRow(theme, contentInk, stateWord, stateColor),
                      if (skipped) ...[
                        const SizedBox(height: Space.s),
                        Text(
                          'Nothing will be recorded for this item.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: contentInk,
                          ),
                        ),
                      ] else
                        ..._entryFields(theme, contentInk),
                      const SizedBox(height: Space.s),
                      _controls(theme),
                    ],
                  ),
                )
              else
                _collapsed(theme, contentInk, stateWord, stateColor),
              // The §4 mid-state stripe: thin secondary left border + the
              // word — a started line must never look like done.
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
      ),
    );
  }

  /// The one-row summary a finished line folds down to: name, what it says
  /// was used, and the state word. The whole row re-opens it.
  Widget _collapsed(
    ThemeData theme,
    Color contentInk,
    String? stateWord,
    Color stateColor,
  ) {
    final line = widget.line;
    final used = line.effectiveDepletion;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _open = true),
        child: Semantics(
          button: true,
          label: '${line.itemName}: ${stateWord ?? 'to do'}. Tap to change.',
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: Space.m,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Icon(
                      line.confirmed
                          ? Icons.check_circle
                          : Icons.remove_circle_outline,
                      color: line.confirmed
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: Space.s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            line.itemName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: contentInk,
                            ),
                          ),
                          if (used != null)
                            Text(
                              'Used: ${QuantityCodec.format(used)}'
                              '${line.unitSuffix}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: contentInk,
                              ),
                            ),
                          // At 200 % the word does not fit beside the name,
                          // so it goes under it rather than crushing it.
                          if (stateWord != null && _bigText)
                            Text(
                              stateWord,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: stateColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (stateWord != null && !_bigText) ...[
                      const SizedBox(width: Space.s),
                      Text(
                        stateWord,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: stateColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerRow(
    ThemeData theme,
    Color contentInk,
    String? stateWord,
    Color stateColor,
  ) {
    final line = widget.line;
    final word = stateWord == null
        ? null
        : Text(
            stateWord,
            style: theme.textTheme.labelLarge?.copyWith(color: stateColor),
          );
    final nameRow = Row(
      children: [
        Icon(
          line.confirmed
              ? Icons.check_circle
              : line.skipped
              ? Icons.remove_circle_outline
              : Icons.radio_button_unchecked,
          color: line.confirmed
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
          semanticLabel: line.done
              ? '${line.itemName}: done'
              : '${line.itemName}: to do',
        ),
        const SizedBox(width: Space.s),
        Expanded(
          child: Text(
            line.itemName,
            style: theme.textTheme.titleMedium?.copyWith(color: contentInk),
          ),
        ),
        // Beside the name only while it fits: at 200 % the word alone is
        // wider than the card, which would squeeze the name to nothing.
        if (word != null && !_bigText) ...[
          const SizedBox(width: Space.s),
          word,
        ],
      ],
    );
    if (word == null || !_bigText) return nameRow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [nameRow, word],
    );
  }

  /// 'None used': left = loaded, else the planned load, and the one leftover
  /// rule derives a used of 0. With neither number on record nothing-used
  /// needs no count at all — it IS a direct used of 0 (§5: zero is a legal
  /// label), written through the same handler typing reaches. Never touches
  /// the stockout flag.
  void _quickFillNoneUsed() {
    final line = widget.line;
    final loaded = line.loadedQuantity;
    // Never ride on a used figure an earlier tap left behind.
    line.depletion.clear();
    if (loaded != null) {
      line.returned.text = QuantityCodec.format(loaded);
      line.applyLeftoverDefaults();
    } else if (line.plannedLoadMicros != null) {
      line.fillLoadedFromPlan();
      line.returned.text = line.loaded.text;
      line.applyLeftoverDefaults();
    } else {
      line.depletion.text = QuantityCodec.format(Quantity.zero);
    }
    _edited(collapseWhenDone: true);
  }

  /// 'All gone': left = 0 — a real count, not an invention — and it answers
  /// "did you run out?" with Yes, because all gone usually means demand was
  /// censored (the owner taps No when supply exactly met demand). The one
  /// leftover rule then derives used from loaded or the planned load; with
  /// neither on record the zero alone cannot say how many were used, so the
  /// shortcut hands focus to Loaded — the one number that now determines
  /// the line.
  void _quickFillAllGone() {
    final line = widget.line;
    line.answerStockout(true);
    line.depletion.clear();
    line.returned.text = QuantityCodec.format(Quantity.zero);
    line.applyLeftoverDefaults();
    final incomplete = line.effectiveDepletion == null;
    _edited(collapseWhenDone: true);
    if (incomplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusLoadedField());
    }
  }

  /// Focuses the Loaded box. [QuantityFormField] owns its [TextFormField]
  /// and exposes no focus node, so walk the keyed subtree — it contains
  /// exactly one [EditableText] — and focus that node.
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

  /// The Loaded box, for the two cases that put it on the face of the card:
  /// a line the plan says nothing about, and one where the owner asked to
  /// change what was loaded.
  Widget _loadedBox() {
    final line = widget.line;
    return KeyedSubtree(
      key: _loadedFieldKey,
      child: QuantityFormField(
        controller: line.loaded,
        labelText: 'Loaded',
        unitLabel: line.unitLabel,
        isRequired: false,
        allowZero: true,
        allowFractions: true,
        onChanged: (_) {
          // The waste-counts-as-0 half of the rule only: clearing Loaded
          // must not snap the planned load straight back in.
          line.applyLeftoverDefaults(fillLoadedFromPlan: false);
          _edited();
        },
      ),
    );
  }

  /// The counting body: the one question, the boxes the rare cases add to
  /// it, and the read-out that does the arithmetic so nobody else has to.
  List<Widget> _entryFields(ThemeData theme, Color contentInk) {
    final line = widget.line;
    return [
      const SizedBox(height: Space.m),
      if (line.directEntry)
        QuantityFormField(
          controller: line.depletion,
          labelText: 'Used',
          unitLabel: line.unitLabel,
          isRequired: false,
          allowZero: true,
          allowFractions: true,
          helperText: 'What was used or sold.',
          onChanged: (_) => _edited(),
          validator: (value) => value.micros > maxDepletionMicros
              ? 'Larger than Loadout supports'
              : null,
        )
      else ...[
        // Loaded reads as a quiet line of text, not a box: it came from the
        // plan and is right on almost every line. More → 'Change what was
        // loaded' turns it into the box below.
        if (line.showsLoadedBox) ...[
          _loadedBox(),
          const SizedBox(height: Space.m),
        ] else ...[
          Text(
            'Loaded ${line.loadedReadout}${line.unitSuffix}',
            style: theme.textTheme.bodyMedium?.copyWith(color: contentInk),
          ),
          const SizedBox(height: Space.s),
        ],
        QuantityFormField(
          controller: line.returned,
          labelText: 'How many are left?',
          unitLabel: line.unitLabel,
          isRequired: false,
          allowZero: true,
          allowFractions: true,
          onChanged: (_) {
            line.applyLeftoverDefaults();
            _edited();
          },
        ),
      ],
      if (line.wasteOpen) ...[
        const SizedBox(height: Space.m),
        QuantityFormField(
          controller: line.waste,
          labelText: 'Thrown out',
          unitLabel: line.unitLabel,
          isRequired: false,
          allowZero: true,
          allowFractions: true,
          onChanged: (_) => _edited(),
        ),
      ],
      const SizedBox(height: Space.s),
      ..._readout(theme, contentInk),
    ];
  }

  /// What the numbers add up to — "Used: 34" — or the one thing that is
  /// missing, or the warning when they do not add up at all.
  List<Widget> _readout(ThemeData theme, Color contentInk) {
    final line = widget.line;
    final derived = line.derivedDepletionMicros;
    if (!line.directEntry && derived != null && derived < 0) {
      return [
        WarningBanner(
          message: (line.wasteQuantity?.micros ?? 0) > 0
              ? 'That plus what was thrown out is more than was loaded — '
                    'check the numbers.'
              : 'That is more than was loaded — check the numbers.',
        ),
      ];
    }
    if (!line.directEntry && derived != null && derived > maxDepletionMicros) {
      return const [
        WarningBanner(message: 'Used is larger than Loadout supports.'),
      ];
    }
    final used = line.effectiveDepletion;
    if (used != null) {
      return [
        Text(
          'Used: ${QuantityCodec.format(used)}${line.unitSuffix}',
          style: theme.textTheme.titleMedium?.copyWith(color: contentInk),
        ),
      ];
    }
    if (!line.directEntry &&
        line.returnedQuantity != null &&
        line.loadedQuantity == null) {
      return [
        Text(
          'Fill in Loaded to work out what was used.',
          style: theme.textTheme.bodySmall?.copyWith(color: contentInk),
        ),
      ];
    }
    // The plan-prefill explanation is deliberately NOT here: it was true on
    // every card at once, so a thirteen-item count repeated one sentence
    // thirteen times. It is said once, under the progress header.
    return const [];
  }

  /// The question that used to be a permanent chip. It appears only once the
  /// line reads as empty, in words a volunteer can answer, and it never
  /// blocks the line from confirming.
  Widget _stockoutQuestion(ThemeData theme, Color contentInk) {
    final line = widget.line;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Wrap(
        spacing: Space.s,
        runSpacing: Space.s,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Did you run out?',
            style: theme.textTheme.bodyMedium?.copyWith(color: contentInk),
          ),
          ChoiceChip(
            label: const Text('Yes'),
            tooltip:
                'Demand was at least this — the forecast will allow for '
                'more next time',
            selected: line.stockoutAnswered && line.stockout,
            onSelected: (_) {
              line.answerStockout(true);
              _edited(collapseWhenDone: true);
            },
          ),
          ChoiceChip(
            label: const Text('No'),
            tooltip: 'There was enough — this is what people wanted',
            selected: line.stockoutAnswered && !line.stockout,
            onSelected: (_) {
              line.answerStockout(false);
              _edited(collapseWhenDone: true);
            },
          ),
        ],
      ),
    );
  }

  /// Every control the card carries: the two shortcuts and the overflow —
  /// four things counting the box above them, where yesterday there were
  /// eight. Wraps rather than Rows so 200 % text simply takes more lines.
  Widget _controls(ThemeData theme) {
    final line = widget.line;
    final scheme = theme.colorScheme;
    final contentInk = line.confirmed
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (line.asksStockout) _stockoutQuestion(theme, contentInk),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!line.skipped && !line.directEntry) ...[
              ActionChip(
                label: const Text('All gone'),
                tooltip: 'Nothing was left',
                onPressed: _quickFillAllGone,
              ),
              ActionChip(
                label: const Text('None used'),
                tooltip: 'It all came back',
                onPressed: _quickFillNoneUsed,
              ),
            ],
            _overflow(theme),
          ],
        ),
      ],
    );
  }

  /// The card's overflow — everything that is not the one number: changing
  /// what was loaded, thrown-out, the used-instead mode, and Skip.
  Widget _overflow(ThemeData theme) {
    final line = widget.line;
    return PopupMenuButton<_LineMenuAction>(
      tooltip: 'Other ways to fill this in',
      position: PopupMenuPosition.under,
      onOpened: () => setState(() => _menuOpen = true),
      onCanceled: () => setState(() => _menuOpen = false),
      onSelected: (action) {
        _menuOpen = false;
        switch (action) {
          case _LineMenuAction.changeLoaded:
            line.loadedOpen = true;
            line.fillLoadedFromPlan();
          case _LineMenuAction.throwSomeOut:
            line.wasteOpen = true;
            if (line.waste.text.trim().isEmpty) {
              line.waste.text = QuantityCodec.format(Quantity.zero);
            }
          case _LineMenuAction.useDirect:
            line.useDirectEntry();
          case _LineMenuAction.useLeftover:
            line.useLeftoverEntry();
          case _LineMenuAction.skip:
            line.skipped = true;
          case _LineMenuAction.unskip:
            line.skipped = false;
        }
        // Everything but Skip reveals something to fill in, so the card
        // stays open to show it even on a line that already confirmed.
        if (action != _LineMenuAction.skip) _open = true;
        _edited(collapseWhenDone: action == _LineMenuAction.skip);
      },
      itemBuilder: (context) => [
        if (line.skipped)
          const PopupMenuItem(
            value: _LineMenuAction.unskip,
            child: Text('Count this item after all'),
          )
        else ...[
          if (line.directEntry)
            const PopupMenuItem(
              value: _LineMenuAction.useLeftover,
              child: Text("Count what's left instead"),
            )
          else ...[
            if (!line.showsLoadedBox)
              const PopupMenuItem(
                value: _LineMenuAction.changeLoaded,
                child: Text('Change what was loaded'),
              ),
            if (!line.wasteOpen)
              const PopupMenuItem(
                value: _LineMenuAction.throwSomeOut,
                child: Text('Some was thrown out'),
              ),
            const PopupMenuItem(
              value: _LineMenuAction.useDirect,
              child: Text('Enter what was used instead'),
            ),
          ],
          const PopupMenuItem(
            value: _LineMenuAction.skip,
            child: Text('Skip this item'),
          ),
        ],
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          child: Align(
            alignment: Alignment.center,
            widthFactor: 1,
            child: Text(
              'More',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
