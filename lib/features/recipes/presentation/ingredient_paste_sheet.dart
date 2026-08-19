/// "Paste ingredients" bottom sheet (proposal §3, recipe screen): paste
/// multi-line text, review what each line matched, and on confirm hand the
/// resolved rows back to the form. v5 (recipe decoupling): NOTHING is
/// created here any more — a matched line is handed back with its catalog
/// LINK, every other kept line is a free line carrying its own text. Items
/// are created later only if the owner asks ("Add to items"). Cancel/Back/
/// dismiss hand back nothing.
///
/// GATE 5 SEAM: the review stage renders `List<PasteCandidateLine>` — the
/// producer-agnostic shape `ingredient_paste.dart` defines — so the OCR
/// flow becomes a second producer feeding this same reviewer. No OCR is
/// built here.
///
/// THE REVIEW HAS TWO STATES, not four. A line is either KEPT — a ticked
/// checkbox you can untick — or SKIPPED, greyed out with a plain reason.
/// The parser's four-way `PasteLineStatus` (matched / ambiguous / unmatched
/// / excluded) is plumbing: "this line found exactly one item in your
/// catalog" versus "it found two" changes nothing the owner does or
/// decides, and it used to be signalled by three silent status glyphs in
/// three different colours. Matching still happens — a matched line comes
/// back LINKED — it is simply not narrated. Only `excluded` (a sales-table
/// item, which no recipe may use) reaches the second state.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/quantity_codec.dart';
import '../../catalog/application/catalog_service.dart';
import '../../catalog/domain/item.dart';
import 'ingredient_paste.dart';
import 'recipe_catalog_filters.dart';

/// Opens the sheet; resolves to the confirmed rows for the form to append,
/// or null when dismissed without confirming.
///
/// [initialText] is the Gate 5 seam in action: a second producer (OCR)
/// hands its lines here and the sheet opens straight on the SAME review
/// stage a paste reaches via "Review" — the text stays editable behind the
/// review's Back button.
Future<List<PastedIngredient>?> showIngredientPasteSheet(
  BuildContext context, {
  String? initialText,
}) => showModalBottomSheet<List<PastedIngredient>>(
  context: context,
  isScrollControlled: true,
  builder: (_) => IngredientPasteSheet(initialText: initialText),
);

class IngredientPasteSheet extends ConsumerStatefulWidget {
  const IngredientPasteSheet({super.key, this.initialText});

  /// When set, the sheet pre-fills the input with this text and opens on
  /// the review stage as soon as the catalog is ready.
  final String? initialText;

  @override
  ConsumerState<IngredientPasteSheet> createState() =>
      _IngredientPasteSheetState();
}

class _IngredientPasteSheetState extends ConsumerState<IngredientPasteSheet> {
  final _textController = TextEditingController();

  /// Null while typing; parsed candidates once "Review" is pressed.
  List<PasteCandidateLine>? _candidates;

  /// Producer-supplied text still waiting for the catalog so it can be
  /// auto-reviewed (consumed on the first ready build).
  String? _pendingInitialText;

  /// Per-candidate "keep this one" ticks. EVERY keepable line carries one,
  /// ticked by default — the owner can drop any line she does not want,
  /// including one the parser happened to match.
  final Map<int, bool> _keep = {};

  @override
  void initState() {
    super.initState();
    final initialText = widget.initialText;
    if (initialText != null) {
      _textController.text = initialText;
      _pendingInitialText = initialText;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  int get _addCount {
    final candidates = _candidates ?? const <PasteCandidateLine>[];
    var count = 0;
    for (var i = 0; i < candidates.length; i++) {
      if (_keep[i] ?? false) count++;
    }
    return count;
  }

  /// The one line the review draws differently: a sales-table item, which
  /// no recipe may use. Everything else is a ticked, untickable row.
  static bool _isSkipped(PasteCandidateLine candidate) =>
      candidate.status == PasteLineStatus.excluded;

  void _review(List<Item> catalog, Set<String> salesTableFolderIds) {
    setState(() => _applyReview(catalog, salesTableFolderIds));
  }

  /// Parses the input text and installs the review state. Called inside
  /// setState by [_review], and directly (pre-frame) by the build-time
  /// auto-review of producer-supplied text.
  void _applyReview(List<Item> catalog, Set<String> salesTableFolderIds) {
    final candidates = parseIngredientPaste(
      _textController.text,
      catalog: catalog,
      salesTableFolderIds: salesTableFolderIds,
    );
    _candidates = candidates;
    _keep.clear();
    for (var i = 0; i < candidates.length; i++) {
      if (!_isSkipped(candidates[i])) _keep[i] = true;
    }
  }

  /// v5: writes NOTHING — a line the parser matched comes back LINKED, and
  /// every other kept line comes back as a free line with its own text. The
  /// recipe itself still saves only via the form's Save button.
  void _confirm() {
    final candidates = _candidates;
    if (candidates == null) return;
    final results = <PastedIngredient>[];
    for (var i = 0; i < candidates.length; i++) {
      if (!(_keep[i] ?? false)) continue;
      final candidate = candidates[i];
      results.add(
        PastedIngredient(
          // Only an exact single match carries a link; an ambiguous line
          // arrives free and the owner links it from the row's overflow.
          itemId: candidate.status == PasteLineStatus.matched
              ? candidate.match!.id.value
              : null,
          name: candidate.name,
          unitLabel: candidate.unitLabel,
          quantityPerBatch: candidate.quantityPerBatch,
        ),
      );
    }
    Navigator.of(context).pop(results);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = ref.watch(itemListProvider(const ItemFilter()));
    final salesTableFolderIds = ref.watch(salesTableFolderIdsProvider);
    final ready = items.valueOrNull != null && salesTableFolderIds != null;
    if (ready && _pendingInitialText != null) {
      // Producer-supplied text (OCR): review it on the first ready build —
      // state is installed before this frame uses it, so no setState.
      _pendingInitialText = null;
      _applyReview([
        for (final summary in items.value!) summary.item,
      ], salesTableFolderIds);
    }
    return SafeArea(
      child: Padding(
        // The sheet holds a text field: keep it above the keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: !ready
                ? SizedBox(
                    height: 160,
                    child: items.hasError
                        ? const Center(
                            child: Text('Items could not be loaded.'),
                          )
                        : const Center(child: CircularProgressIndicator()),
                  )
                : _candidates == null
                ? _buildInput(theme, items.value!, salesTableFolderIds)
                : _buildReview(theme),
          ),
        ),
      ),
    );
  }

  Widget _buildInput(
    ThemeData theme,
    List<ItemSummary> summaries,
    Set<String> salesTableFolderIds,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Paste ingredients', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'One ingredient per line. A leading amount and measure — '
          '"2x carrots", "1 1/2 cups sugar" — become the per-batch amount '
          'and unit; anything unclear is left blank for you.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: TextField(
            key: const Key('paste-input'),
            controller: _textController,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: '2x carrots\n3 bags onions\nrolls',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const Spacer(),
            FilledButton(
              key: const Key('paste-review'),
              onPressed: () => _review([
                for (final summary in summaries) summary.item,
              ], salesTableFolderIds),
              child: const Text('Review'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReview(ThemeData theme) {
    final candidates = _candidates!;
    final count = _addCount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Review before adding', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Lines are added to the recipe only — nothing goes into your '
          'items unless you add it later.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: candidates.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nothing to review — the pasted text was empty.'),
                )
              // Non-lazy on purpose: a paste is a handful of lines, and the
              // whole review must be walkable (and testable) as one column.
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < candidates.length; i++)
                        _buildCandidateRow(i, candidates[i]),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: () => setState(() => _candidates = null),
              child: const Text('Back'),
            ),
            const Spacer(),
            FilledButton(
              key: const Key('paste-confirm'),
              onPressed: count == 0 ? null : _confirm,
              child: Text(
                'Add $count ${count == 1 ? 'ingredient' : 'ingredients'}',
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Two states, one shape. KEPT: a ticked checkbox, the pasted line, and
  /// the amount that was read off it. SKIPPED: the same line greyed out
  /// with the reason in words. No status glyphs, no colours carrying
  /// meaning, nothing about how the parser felt about the line.
  Widget _buildCandidateRow(int index, PasteCandidateLine candidate) {
    final amount = candidate.quantityPerBatch;
    final unit = candidate.unitLabel;
    final amountNote = amount == null
        ? 'Amount left for you'
        : '${QuantityCodec.format(amount)}'
              '${unit == null ? '' : ' $unit'} per batch';
    if (_isSkipped(candidate)) {
      return ListTile(
        key: ValueKey('paste-skipped-$index'),
        contentPadding: EdgeInsets.zero,
        enabled: false,
        title: Text(candidate.rawText),
        subtitle: const Text(
          'Skipped: this is something you sell, not something you cook with.',
        ),
      );
    }
    return CheckboxListTile(
      key: ValueKey('paste-keep-$index'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: _keep[index] ?? false,
      onChanged: (checked) => setState(() => _keep[index] = checked ?? false),
      title: Text(candidate.rawText),
      subtitle: Text(amountNote),
    );
  }
}
