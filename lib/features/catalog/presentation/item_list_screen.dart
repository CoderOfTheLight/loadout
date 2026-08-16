/// `/items` — the catalog in the owner's packing order (folders proposal
/// §3): folder sections with pinned headers, not a flat alphabet.
///
/// * Sections come from `watchFoldersWithItems`: live folders in the
///   owner's order (empty ones included — she must see where things can
///   go), then "Unfiled" last whenever anything is unfiled, never hidden.
///   "Archived" renders after everything, only via the Show archived
///   toggle.
/// * Rows are TABLE-LIKE (owner's ruling): the amount+unit is the LEADING
///   column — the amount in the tabular `titleLarge` row-quantity role, the
///   display unit label quietly after it ("12 packages", "0.5 cup", bare
///   "12" without a label) — then the name. The column is one consistent
///   width per section, so rows align like a table. The per-row 40 dp
///   [FolderChip] is DROPPED inside folder sections (the header already
///   names the folder); Unfiled rows keep a neutral [UnfiledChip], and an
///   item shown outside its own section keeps its folder's chip. Negative
///   amounts keep icon + word + sign. Data rows stay monochrome and
///   motionless — a chip is the only color.
/// * Moving an item is first-class: every live row carries an overflow menu
///   with "Move to folder…" → the folder picker → `MoveItemToFolder`.
/// * A recipe-output item's row gains a quiet expand affordance. Expanded,
///   it shows the recipe's CURRENT lines as extra rows — a VIEW, not data
///   nesting: lines linked to catalog items render as those items' own rows
///   (with the chip of the folder they actually live in), unlinked lines
///   render dimmed with an "Add to items" way into the recipe.
/// * Headers pin while their section scrolls (SliverMainAxisGroup +
///   SliverPersistentHeader — framework only): 24 dp chip, name, count,
///   chevron (`AnimatedRotation`), on opaque `surfaceContainerLow` with a
///   hairline so the pin edge reads in sunlight. Tap to collapse; collapse
///   is remembered for the session ([collapsedSectionsProvider]).
/// * Search and the jump-to-folder chips live in a floating header
///   (`SliverFloatingHeader`): gone scrolling down, back on the first
///   upward flick — mid-scroll pinned chrome is the 52 dp section header
///   alone (spec §4 pinned-chrome budget).
/// * The jump row is the food-delivery-menu pattern: a color dot + name +
///   count per chip, tap scrolls to the section (offsets are exact because
///   every row is a fixed-extent sliver child), and the active chip tracks
///   the scroll position.
///
/// The only command this screen issues is `MoveItemToFolder` (the row and
/// picker are otherwise read-only). Folder management is its own screen,
/// reached from the overflow menu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/folder_chip.dart';
import '../../../core/result.dart';
import '../../../core/units.dart';
import '../../recipes/domain/recipe.dart';
import '../application/catalog_service.dart';
import '../domain/folder.dart';
import 'catalog_format.dart';
import 'catalog_providers.dart';
import 'folder_management_screen.dart';
import 'folder_picker_sheet.dart';
import 'unfiled_chip.dart';

/// Section ids for the two non-folder sections. Folder ids are 26-char
/// ULIDs, so these can never collide.
const String unfiledSectionId = 'unfiled';
const String archivedSectionId = 'archived';

/// The horizontal jump-to-folder row, for tests and tooling.
const Key itemListJumpRowKey = Key('folder-jump-row');

/// Fixed extents keep chip-jump arithmetic exact and scrolling cheap at
/// 150+ items: every header is 52 dp (spec §4), every row 72 dp — expanded
/// recipe lines included, so expansion only ADDS rows to the sums below.
const double _headerExtent = 52;
const double _itemExtent = 72;

/// The amount column's floor and cap: at least a digit column wide, never
/// so wide (a long label at a big text scale) that the name loses its line.
const double _amountColumnMin = 40;
const double _amountColumnMax = 168;

/// Amount + optional display label, kept separate so the label can render
/// quietly beside the big tabular numerals.
typedef _AmountParts = ({String amount, String? label});

/// One rendered row of a section: an item, or one line of an expanded
/// recipe-output item (a view over the recipe — no data nesting anywhere).
sealed class _Row {
  const _Row();
}

final class _ItemRow extends _Row {
  const _ItemRow(this.summary);

  final ItemSummary summary;
}

/// A recipe line linked to a catalog item: rendered as that item's own row,
/// wearing the chip of the folder it actually lives in.
final class _LinkedLineRow extends _Row {
  const _LinkedLineRow({required this.summary, required this.folder});

  final ItemSummary summary;
  final Folder? folder;
}

/// An unlinked (or no-longer-live) recipe line: quiet, dimmed, with an
/// "Add to items" way into the recipe when the line is truly free.
final class _FreeLineRow extends _Row {
  const _FreeLineRow({
    required this.line,
    required this.recipeId,
    required this.offerAdd,
  });

  final RecipeLine line;
  final String recipeId;
  final bool offerAdd;
}

final class _Section {
  const _Section({
    required this.id,
    required this.title,
    required this.items,
    required this.rows,
    required this.amountWidth,
    this.folder,
  });

  final String id;
  final String title;

  /// The section's items — header and jump-chip counts read this.
  final List<ItemSummary> items;

  /// What actually renders: items plus any expanded recipe lines.
  final List<_Row> rows;

  /// The measured amount-column width shared by every row in this section.
  final double amountWidth;

  /// Null for the Unfiled and Archived sections — no identity chip there.
  final Folder? folder;
}

class ItemListScreen extends ConsumerStatefulWidget {
  const ItemListScreen({super.key});

  @override
  ConsumerState<ItemListScreen> createState() => _ItemListScreenState();
}

class _ItemListScreenState extends ConsumerState<ItemListScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _floatingHeaderKey = GlobalKey();
  final Map<String, GlobalKey> _chipKeys = {};
  bool _includeArchived = false;
  String _query = '';

  /// Recipe-output item ids whose rows are expanded to show their lines.
  /// Screen-local: leaving the list folds every group again.
  final Set<String> _expandedRecipes = {};

  /// The section the scroll position currently sits in — the jump row's
  /// highlighted chip. Null until the list first scrolls or jumps.
  String? _activeSectionId;

  /// The sections currently on screen, in order — the jump chips read this.
  List<_Section> _visibleSections = const [];

  /// Const-canonicalized so the provider-family key stays identical across
  /// rebuilds (the filter type has no value equality).
  static const _archivedFilter = ItemFilter(includeArchived: true);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_trackActiveSection);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toggleSection(String id) {
    final notifier = ref.read(collapsedSectionsProvider.notifier);
    final current = notifier.state;
    notifier.state = current.contains(id)
        ? {
            for (final other in current)
              if (other != id) other,
          }
        : {...current, id};
  }

  void _toggleRecipe(String itemId) {
    setState(() {
      if (!_expandedRecipes.remove(itemId)) {
        _expandedRecipes.add(itemId);
      }
    });
  }

  /// "Move to folder…" from a row's overflow menu: the folder picker over
  /// the owner's live folders, then the single `MoveItemToFolder` command.
  Future<void> _moveItem(ItemSummary summary) async {
    final pick = await showFolderPickerSheet(
      context,
      selectedFolderId: summary.item.folderId?.value,
    );
    if (pick == null || !mounted) {
      return;
    }
    if (pick.folderId == summary.item.folderId?.value) {
      return;
    }
    // Resolve the destination's name from the already-watched sections (the
    // picker only offers live folders, so the id is in there — or Unfiled).
    var destination = 'Unfiled';
    for (final section
        in ref.read(foldersWithItemsProvider).valueOrNull ??
            const <FolderWithItems>[]) {
      if (section.folder?.id.value == pick.folderId) {
        destination = section.folder!.name;
      }
    }
    final result = await ref
        .read(catalogServiceProvider)
        .moveItemToFolder(
          itemId: summary.item.id.value,
          folderId: pick.folderId,
        );
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok():
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Moved to $destination.')));
      case Err():
        // Content-free by design (§9): no names or quantities in errors.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't move this item. Try again.")),
        );
    }
  }

  /// The floating search+chips header's current height — part of the exact
  /// jump offset. Zero before the first layout.
  double get _floatingHeaderHeight =>
      _floatingHeaderKey.currentContext?.size?.height ?? 0;

  /// The exact scroll offset where [section]'s header rests, given the
  /// fixed extents and the collapse state.
  double _sectionOffset(String sectionId, Set<String> collapsed) {
    var offset = _floatingHeaderHeight;
    for (final section in _visibleSections) {
      if (section.id == sectionId) {
        break;
      }
      offset += _headerExtent;
      if (!collapsed.contains(section.id)) {
        offset += section.rows.length * _itemExtent;
      }
    }
    return offset;
  }

  /// Scrolls so [sectionId]'s header lands at the top. Exact, not
  /// estimated: headers and rows have fixed extents, and pinned headers
  /// stay inside their own group, so the sum below IS the offset.
  void _jumpToSection(String sectionId) {
    if (!_scroll.hasClients) {
      return;
    }
    final collapsed = ref.read(collapsedSectionsProvider);
    setState(() => _activeSectionId = sectionId);
    _scroll.animateTo(
      _sectionOffset(
        sectionId,
        collapsed,
      ).clamp(0.0, _scroll.position.maxScrollExtent),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
    );
  }

  /// Keeps the highlighted jump chip in step with the scroll position
  /// (spec §4: the active chip tracks scroll and scrolls itself into view).
  void _trackActiveSection() {
    if (!_scroll.hasClients || _visibleSections.isEmpty) {
      return;
    }
    final collapsed = ref.read(collapsedSectionsProvider);
    final position = _scroll.offset + 1;
    String active = _visibleSections.first.id;
    for (final section in _visibleSections) {
      if (_sectionOffset(section.id, collapsed) <= position) {
        active = section.id;
      } else {
        break;
      }
    }
    if (active == _activeSectionId) {
      return;
    }
    final wasTracking = _activeSectionId != null;
    setState(() => _activeSectionId = active);
    // Auto-scroll the active chip into view only once tracking is already
    // under way: the first activation (list barely moved) must not yank a
    // hand-scrolled chip row back to the start.
    if (!wasTracking) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chipContext = _chipKeys[active]?.currentContext;
      final renderObject = chipContext?.findRenderObject();
      if (chipContext == null || renderObject == null || !mounted) {
        return;
      }
      // ONLY the horizontal chip row scrolls — Scrollable.ensureVisible
      // would climb into the vertical list too and fight the user's scroll.
      Scrollable.of(chipContext).position.ensureVisible(
        renderObject,
        alignment: 0.5,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _openFolderManagement() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => const FolderManagementScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sectionsAsync = ref.watch(foldersWithItemsProvider);
    final archivedSummaries = _includeArchived
        ? ref.watch(itemListProvider(_archivedFilter)).valueOrNull ??
              const <ItemSummary>[]
        : const <ItemSummary>[];
    final collapsed = ref.watch(collapsedSectionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Items'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (value) {
              switch (value) {
                case 'archived':
                  setState(() => _includeArchived = !_includeArchived);
                case 'folders':
                  _openFolderManagement();
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'archived',
                checked: _includeArchived,
                child: const Text('Show archived'),
              ),
              const PopupMenuItem(
                value: 'folders',
                child: Text('Manage folders'),
              ),
            ],
          ),
        ],
      ),
      // Words on every FAB (spec §2: no icon-only actions).
      floatingActionButton: FloatingActionButton.extended(
        // Shell branches stay mounted together, so every FAB needs its own
        // hero tag.
        heroTag: 'fab-items',
        onPressed: () => context.push('/items/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: sectionsAsync.when(
        data: (folderSections) =>
            _buildSections(folderSections, archivedSummaries, collapsed),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyState(
          message: "Items couldn't be loaded.",
          icon: Icons.error_outline,
        ),
      ),
    );
  }

  /// The rows a section renders: its items, plus the current recipe lines
  /// under each expanded recipe-output row. [itemsById] maps every LIVE
  /// item to where it lives, so linked lines render as real item rows.
  List<_Row> _rowsFor(
    List<ItemSummary> items,
    Map<String, ({ItemSummary summary, Folder? folder})> itemsById,
  ) {
    final rows = <_Row>[];
    for (final summary in items) {
      rows.add(_ItemRow(summary));
      final recipeId = summary.recipeId;
      if (recipeId == null ||
          !_expandedRecipes.contains(summary.item.id.value)) {
        continue;
      }
      final detail = ref.watch(recipeDetailProvider(recipeId)).valueOrNull;
      final lines = detail == null || detail.revisions.isEmpty
          ? const <RecipeLine>[]
          : detail.revisions.first.lines;
      for (final line in lines) {
        final linked = line.ingredientItemId == null
            ? null
            : itemsById[line.ingredientItemId!.value];
        if (linked != null) {
          rows.add(
            _LinkedLineRow(summary: linked.summary, folder: linked.folder),
          );
        } else {
          // Free line — or a linked line whose item is no longer live; the
          // latter renders quietly too, but never offers "Add to items".
          rows.add(
            _FreeLineRow(
              line: line,
              recipeId: recipeId,
              offerAdd: !line.isLinked,
            ),
          );
        }
      }
    }
    return rows;
  }

  Widget _buildSections(
    List<FolderWithItems> folderSections,
    List<ItemSummary> archivedSummaries,
    Set<String> collapsed,
  ) {
    final query = _query.trim().toLowerCase();
    final searching = query.isNotEmpty;
    final archivedItems = [
      for (final summary in archivedSummaries)
        if (summary.item.isArchived) summary,
    ];

    List<ItemSummary> matching(List<ItemSummary> items) => searching
        ? [
            for (final summary in items)
              if (summary.item.name.toLowerCase().contains(query)) summary,
          ]
        : items;

    final itemsById = <String, ({ItemSummary summary, Folder? folder})>{
      for (final section in folderSections)
        for (final summary in section.items)
          summary.item.id.value: (summary: summary, folder: section.folder),
    };

    _Section section({
      required String id,
      required String title,
      required List<ItemSummary> items,
      Folder? folder,
    }) {
      final rows = _rowsFor(items, itemsById);
      return _Section(
        id: id,
        title: title,
        items: items,
        rows: rows,
        amountWidth: _amountColumnWidth(rows),
        folder: folder,
      );
    }

    final all = <_Section>[
      for (final folderSection in folderSections)
        section(
          id: folderSection.folder?.id.value ?? unfiledSectionId,
          title: folderSection.folder?.name ?? 'Unfiled',
          items: matching(folderSection.items),
          folder: folderSection.folder,
        ),
      if (archivedItems.isNotEmpty)
        section(
          id: archivedSectionId,
          title: 'Archived',
          items: matching(archivedItems),
        ),
    ];

    final totalItems =
        archivedItems.length +
        folderSections.fold(0, (sum, section) => sum + section.items.length);
    if (totalItems == 0 && !searching) {
      _visibleSections = const [];
      // Unchanged from the pre-folders screen: an empty catalog explains
      // what an item is, folders or not.
      return EmptyState(
        title: 'Nothing in your list yet',
        message:
            'Items are the things you bring and sell — burgers, buns, cups. '
            'Add one with its name and how many you have, and Loadout keeps '
            'count from there.',
        actionLabel: 'Add your first item',
        onAction: () => context.push('/items/new'),
      );
    }

    final visible = searching
        ? [
            for (final section in all)
              if (section.items.isNotEmpty) section,
          ]
        : all;
    _visibleSections = visible;
    _chipKeys.removeWhere(
      (id, _) => !visible.any((section) => section.id == id),
    );
    for (final section in visible) {
      _chipKeys.putIfAbsent(section.id, GlobalKey.new);
    }

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        // Search + jump chips float: gone scrolling down, back on the
        // first upward flick (spec §4 pinned-chrome budget — mid-scroll
        // pinned chrome is the section header alone).
        SliverFloatingHeader(child: _floatingHeader(searching)),
        if (visible.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              message: 'No items match your search.',
              icon: Icons.search_off_outlined,
            ),
          )
        else ...[
          for (final section in visible)
            SliverMainAxisGroup(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SectionHeaderDelegate(
                    title: section.title,
                    folder: section.folder,
                    count: section.items.length,
                    collapsed: !searching && collapsed.contains(section.id),
                    onTap: searching ? null : () => _toggleSection(section.id),
                  ),
                ),
                if (searching || !collapsed.contains(section.id))
                  SliverFixedExtentList(
                    itemExtent: _itemExtent,
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Align(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: contentMaxWidth,
                          ),
                          child: _buildRow(section, section.rows[index]),
                        ),
                      ),
                      childCount: section.rows.length,
                    ),
                  ),
              ],
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 88)),
        ],
      ],
    );
  }

  Widget _buildRow(_Section section, _Row row) => switch (row) {
    _ItemRow(:final summary) => _ItemTile(
      summary: summary,
      amountWidth: section.amountWidth,
      chip: section.id == unfiledSectionId ? const UnfiledChip() : null,
      expanded: summary.isRecipeOutput && !summary.item.isArchived
          ? _expandedRecipes.contains(summary.item.id.value)
          : null,
      onToggleExpanded: () => _toggleRecipe(summary.item.id.value),
      onMove: summary.item.isArchived ? null : () => _moveItem(summary),
    ),
    _LinkedLineRow(:final summary, :final folder) => _ItemTile(
      summary: summary,
      amountWidth: section.amountWidth,
      chip: folder == null ? const UnfiledChip() : FolderChip.forFolder(folder),
      indent: true,
      expanded: null,
      onToggleExpanded: null,
      onMove: () => _moveItem(summary),
    ),
    _FreeLineRow(:final line, :final recipeId, :final offerAdd) =>
      _FreeLineTile(
        line: line,
        recipeId: recipeId,
        offerAdd: offerAdd,
        amountWidth: section.amountWidth,
      ),
  };

  /// One consistent amount-column width for [rows] — the widest measured
  /// amount+label cell, clamped so a big text scale can't eat the name.
  double _amountColumnWidth(List<_Row> rows) {
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    var width = _amountColumnMin;
    for (final row in rows) {
      final (parts, negative) = switch (row) {
        _ItemRow(:final summary) || _LinkedLineRow(:final summary) => (
          _itemAmountParts(summary),
          summary.isNegative,
        ),
        _FreeLineRow(:final line) => (_lineAmountParts(line), false),
      };
      final painter = TextPainter(
        text: _amountTextSpan(theme, parts),
        textDirection: direction,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      var cell = painter.width;
      painter.dispose();
      if (negative) {
        final word = TextPainter(
          text: TextSpan(text: 'Negative', style: theme.textTheme.labelSmall),
          textDirection: direction,
          textScaler: textScaler,
          maxLines: 1,
        )..layout();
        if (word.width > cell) {
          cell = word.width;
        }
        word.dispose();
        cell += _negativeIconWidth;
      }
      if (cell > width) {
        width = cell;
      }
    }
    // A pixel of slack so rounding never ellipsizes the widest cell.
    return (width + 1).clamp(_amountColumnMin, _amountColumnMax);
  }

  /// The floating search + jump-chips region. Opaque on `surface` so it
  /// never ghosts over rows while snapping back in.
  Widget _floatingHeader(bool searching) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      key: _floatingHeaderKey,
      color: scheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: contentMaxWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SearchBar(
                  controller: _search,
                  hintText: 'Search all items',
                  leading: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.search),
                  ),
                  elevation: const WidgetStatePropertyAll(0),
                  onChanged: (text) => setState(() => _query = text),
                ),
              ),
            ),
          ),
          if (!searching)
            SizedBox(
              height: 48,
              child: SingleChildScrollView(
                key: itemListJumpRowKey,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final section in _visibleSections)
                      if (section.id != archivedSectionId)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _JumpChip(
                            key: _chipKeys[section.id],
                            title: section.title,
                            count: section.items.length,
                            folder: section.folder,
                            active: section.id == _activeSectionId,
                            onTap: () => _jumpToSection(section.id),
                          ),
                        ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Width of the warning glyph + gap beside a negative amount.
const double _negativeIconWidth = 30;

/// The amount cell's parts for an item row: the label rides after the
/// amount for counted things; a legacy measured row's real unit stays glued
/// to the numerals exactly as before (never masked by a label).
_AmountParts _itemAmountParts(ItemSummary summary) {
  final item = summary.item;
  if (item.unit != ItemUnit.each) {
    return (amount: formatCount(summary.onHandMicros, item.unit), label: null);
  }
  return (amount: formatMicros(summary.onHandMicros), label: item.unitLabel);
}

/// The amount cell's parts for a recipe line: its per-batch quantity and
/// its own display label.
_AmountParts _lineAmountParts(RecipeLine line) =>
    (amount: formatMicros(line.quantityPerBatch.micros), label: line.unitLabel);

/// Amount in the tabular row-quantity role, label quietly after it in
/// `bodyMedium`. One span so measurement and rendering can never disagree.
TextSpan _amountTextSpan(
  ThemeData theme,
  _AmountParts parts, {
  Color? amountColor,
  Color? labelColor,
}) => TextSpan(
  text: parts.amount,
  style: Numerals.rowQuantity(theme.textTheme)?.copyWith(color: amountColor),
  children: [
    if (parts.label != null)
      TextSpan(
        text: ' ${parts.label}',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: labelColor ?? theme.colorScheme.onSurfaceVariant,
        ),
      ),
  ],
);

/// One jump-to-folder chip (spec §4): 8 dp color dot, name, count. The
/// active chip fills with the folder tint and inks its text; identity is
/// never the dot alone — the name is always beside it.
class _JumpChip extends StatelessWidget {
  const _JumpChip({
    super.key,
    required this.title,
    required this.count,
    required this.folder,
    required this.active,
    required this.onTap,
  });

  final String title;
  final int count;
  final Folder? folder;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = folder == null
        ? null
        : FolderPalette.of(context).pair(folder!.effectiveHue);
    final dotColor = folder == null
        ? scheme.outline
        : folderHueSeeds[folder!.effectiveHue]!;
    final fill = active
        ? (colors?.tint ?? scheme.surfaceContainerHigh)
        : Colors.transparent;
    final ink = active ? (colors?.ink ?? scheme.onSurface) : scheme.onSurface;
    return Semantics(
      button: true,
      selected: active,
      label: 'Jump to $title, $count item${count == 1 ? '' : 's'}',
      child: ExcludeSemantics(
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.small),
            side: active
                ? BorderSide.none
                : BorderSide(color: scheme.outlineVariant),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Radii.small),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: Space.m),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(color: ink),
                  ),
                  const SizedBox(width: Space.xs + 2),
                  Text(
                    '$count',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: active ? ink : scheme.onSurfaceVariant,
                      fontFeatures: Numerals.tabular,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned section header (spec §4): 24 dp chip, name, count, chevron, on
/// opaque `surfaceContainerLow` with a bottom hairline. Whole row tappable
/// to collapse/expand. Fixed 52 dp so jump offsets stay exact.
class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SectionHeaderDelegate({
    required this.title,
    required this.folder,
    required this.count,
    required this.collapsed,
    required this.onTap,
  });

  final String title;
  final Folder? folder;
  final int count;
  final bool collapsed;
  final VoidCallback? onTap;

  @override
  double get minExtent => _headerExtent;

  @override
  double get maxExtent => _headerExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          header: true,
          button: onTap != null,
          label:
              '$title, $count item${count == 1 ? '' : 's'}'
              '${collapsed ? ', collapsed' : ''}',
          excludeSemantics: true,
          child: Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Align(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  child: Row(
                    children: [
                      if (folder != null) ...[
                        FolderChip.forFolder(
                          folder!,
                          size: FolderChipSize.small,
                        ),
                        const SizedBox(width: Space.s + 2),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '$count',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: Numerals.tabular,
                        ),
                      ),
                      if (onTap != null) ...[
                        const SizedBox(width: Space.s),
                        AnimatedRotation(
                          turns: collapsed ? -0.25 : 0,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.expand_more,
                            size: 20,
                            color: scheme.onSurfaceVariant,
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
      ),
    );
  }

  @override
  bool shouldRebuild(_SectionHeaderDelegate oldDelegate) =>
      oldDelegate.title != title ||
      oldDelegate.count != count ||
      oldDelegate.collapsed != collapsed ||
      oldDelegate.folder != folder ||
      (oldDelegate.onTap == null) != (onTap == null);
}

/// The leading amount cell: big tabular numerals (+ quiet label), the §9
/// negative treatment (icon + sign + the word) when on-hand is below zero.
class _AmountCell extends StatelessWidget {
  const _AmountCell({
    required this.parts,
    required this.negative,
    this.dimmed = false,
  });

  final _AmountParts parts;
  final bool negative;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final amountColor = negative
        ? scheme.error
        : dimmed
        ? scheme.onSurfaceVariant
        : null;
    final amount = Text.rich(
      _amountTextSpan(theme, parts, amountColor: amountColor),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (!negative) {
      return Align(alignment: Alignment.centerLeft, child: amount);
    }
    return Row(
      children: [
        Icon(Icons.warning_amber_outlined, color: scheme.error, size: 24),
        const SizedBox(width: _negativeIconWidth - 24),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              amount,
              Text(
                'Negative',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One item row, table-like (owner's ruling): [chip when the row is outside
/// its own folder section] → amount+unit column → name and caption →
/// [expand affordance on recipe outputs] → per-row overflow with the
/// first-class "Move to folder…".
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.summary,
    required this.amountWidth,
    required this.chip,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onMove,
    this.indent = false,
  });

  final ItemSummary summary;
  final double amountWidth;

  /// Identity chip when this row appears outside its own folder section
  /// (Unfiled rows, linked recipe lines); null inside a folder section.
  final Widget? chip;

  /// Null = no expand affordance; otherwise whether the recipe group is
  /// currently expanded.
  final bool? expanded;
  final VoidCallback? onToggleExpanded;

  /// Null hides the overflow (archived rows — the command would refuse).
  final VoidCallback? onMove;

  /// True for rows inside an expanded recipe group — inset a step so the
  /// view reads as contained (a view, never data nesting).
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = summary.item;
    final parts = _itemAmountParts(summary);
    final amountText = parts.label == null
        ? parts.amount
        : '${parts.amount} ${parts.label}';
    final subtitle = [
      if (item.category != null) item.category!,
      if (item.servesPerUnit != null)
        'One serves ${formatMicros(item.servesPerUnit!.micros)}',
      if (item.perPersonRatio != null)
        perPersonRatioPhrase(item.perPersonRatio!),
      if (item.perEventBaseline != null)
        'Usually bring ${formatMicros(item.perEventBaseline!.micros)}',
      if (item.isArchived) 'Archived',
    ].join(' · ');
    final showExpand = expanded != null;
    return ListTile(
      minTileHeight: 56,
      contentPadding: EdgeInsets.only(
        left: indent ? Space.xl + Space.xs : Space.l,
        right: Space.xs,
      ),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chip != null) ...[chip!, const SizedBox(width: Space.m)],
          Semantics(
            label:
                'You have $amountText'
                '${summary.isNegative ? ', negative' : ''}',
            excludeSemantics: true,
            child: SizedBox(
              width: amountWidth,
              child: _AmountCell(parts: parts, negative: summary.isNegative),
            ),
          ),
        ],
      ),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: (showExpand || onMove != null)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showExpand)
                  IconButton(
                    tooltip: expanded!
                        ? 'Hide ingredients'
                        : 'Show ingredients',
                    onPressed: onToggleExpanded,
                    icon: AnimatedRotation(
                      turns: expanded! ? 0.5 : 0,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.expand_more,
                        size: 22,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (onMove != null)
                  PopupMenuButton<String>(
                    tooltip: 'Options for ${item.name}',
                    onSelected: (_) => onMove!(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'move',
                        child: Text('Move to folder…'),
                      ),
                    ],
                  ),
              ],
            )
          : null,
      onTap: () => context.push('/items/${item.id.value}'),
    );
  }
}

/// An unlinked recipe line inside an expanded group: its per-batch amount
/// and name, dimmed, with the "Add to items" way into the recipe (the add
/// flow itself lives on the recipe's own screen).
class _FreeLineTile extends StatelessWidget {
  const _FreeLineTile({
    required this.line,
    required this.recipeId,
    required this.offerAdd,
    required this.amountWidth,
  });

  final RecipeLine line;
  final String recipeId;
  final bool offerAdd;
  final double amountWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      minTileHeight: 56,
      contentPadding: const EdgeInsets.only(
        left: Space.xl + Space.xs,
        right: Space.s,
      ),
      leading: SizedBox(
        width: amountWidth,
        child: _AmountCell(
          parts: _lineAmountParts(line),
          negative: false,
          dimmed: true,
        ),
      ),
      title: Text(
        line.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: offerAdd
          ? TextButton(
              onPressed: () => context.push('/recipes/$recipeId'),
              child: const Text('Add to items'),
            )
          : null,
      onTap: null,
    );
  }
}
