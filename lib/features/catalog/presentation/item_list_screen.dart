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
///   chevron (`AnimatedRotation`), on the FOLDER'S OWN TINT (opaque, with a
///   hairline so the pin edge reads in sunlight) and named in its ink — a
///   section is the folder, so its header is not a grey band. Tap to
///   collapse; collapse is remembered for the session
///   ([collapsedSectionsProvider]).
/// * Search and the jump-to-folder chips live in a floating header
///   (`SliverFloatingHeader`): gone scrolling down, back on the first
///   upward flick — mid-scroll pinned chrome is the 52 dp section header
///   alone (spec §4 pinned-chrome budget).
/// * The jump row is the food-delivery-menu pattern: the folder's small
///   [FolderChip] + name + count per chip — the chip is the ONLY folder
///   mark this app draws, never a hand-mixed dot — tap scrolls to the
///   section (offsets are exact because every row is a fixed-extent sliver
///   child), and the active chip tracks the scroll position.
/// * Rows carry the item's price (v7) as a caption-tier figure on the
///   second line; an unpriced item shows nothing there. The list's viewport
///   stops above the floating "Add item" pill, so no row is ever under it.
///
/// The commands this screen issues are `MoveItemToFolder` and the two
/// deletes — `DeleteItem` from a row's overflow, `DeleteAllItems` from the
/// app-bar overflow, each behind its confirmation (delete_dialogs.dart).
/// Folder management is its own screen, reached from the overflow menu.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/empty_state.dart';
import '../../../app/widgets/folder_chip.dart';
import '../../../core/money_codec.dart';
import '../../../core/result.dart';
import '../../../core/units.dart';
import '../../recipes/domain/recipe.dart';
import '../application/catalog_service.dart';
import '../domain/folder.dart';
import 'catalog_format.dart';
import 'catalog_providers.dart';
import 'delete_dialogs.dart';
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

/// The strip the floating "Add item" button owns: the Scaffold's 16 dp FAB
/// margin, the 56 dp extended pill, and 16 dp of air. The list's viewport
/// stops here, so no row can ever be underneath the button.
const double _fabGutter = 88;

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

  /// Barcode-scanner capability, probed once (false until answered). The
  /// "Scan items in…" entry simply stays hidden until the probe says yes —
  /// availability is a capability, not an error.
  bool _scanAvailable = false;

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
    unawaited(_probeScanner());
  }

  Future<void> _probeScanner() async {
    final available = await ref.read(barcodeScanServiceProvider).isAvailable();
    if (mounted && available) {
      setState(() => _scanAvailable = true);
    }
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

  /// "Delete…" from a row's overflow: the confirmation, then the single
  /// `DeleteItem` command (safe by construction — the applier archives an
  /// item with event history and hard-deletes one without; either way the
  /// row leaves the list).
  Future<void> _deleteItem(ItemSummary summary) async {
    final name = summary.item.name;
    final confirmed = await confirmDeleteItem(context, itemName: name);
    if (!confirmed || !mounted) {
      return;
    }
    final result = await ref
        .read(catalogServiceProvider)
        .deleteItem(itemId: summary.item.id.value);
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok():
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Deleted "$name"')));
      case Err():
        // Content-free by design (§9): no names or quantities in errors.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't delete this item. Try again."),
          ),
        );
    }
  }

  /// "Delete all items…" from the app-bar overflow: one confirmation over
  /// the live count, then the single `DeleteAllItems` command. Previously
  /// archived items are left alone (the service's rule).
  Future<void> _deleteAllItems(int itemCount) async {
    final confirmed = await confirmDeleteAllItems(
      context,
      itemCount: itemCount,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final result = await ref.read(catalogServiceProvider).deleteAllItems();
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok():
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('All items deleted')));
      case Err():
        // Content-free by design (§9): no names or quantities in errors.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't delete your items. Try again."),
          ),
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
    // The live count "Delete all items…" confirms over (archived items are
    // outside both the sections and the command's reach).
    final liveItemCount =
        sectionsAsync.valueOrNull?.fold<int>(
          0,
          (sum, section) => sum + section.items.length,
        ) ??
        0;
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
                case 'scan-in':
                  context.push('/items/scan-in');
                case 'delete-all':
                  _deleteAllItems(liveItemCount);
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
              if (_scanAvailable)
                const PopupMenuItem(
                  value: 'scan-in',
                  child: Text('Scan items in…'),
                ),
              PopupMenuItem(
                value: 'delete-all',
                // Disabled instead of failing after the tap: with no live
                // items there is nothing the command would touch.
                enabled: liveItemCount > 0,
                child: const Text('Delete all items…'),
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

    // The FAB floats over the body, so the list's VIEWPORT stops above it
    // rather than the list merely ending with a spacer: a trailing spacer
    // only clears the button at full scroll, and mid-scroll the "Add item"
    // pill sat on top of whichever row happened to be at the bottom edge —
    // over its overflow menu, the one target on the row that is not the
    // row. Nothing scrolls under the button now.
    return Padding(
      padding: const EdgeInsets.only(bottom: _fabGutter),
      child: CustomScrollView(
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
          else
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
                      onTap: searching
                          ? null
                          : () => _toggleSection(section.id),
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
        ],
      ),
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
      onDelete: summary.item.isArchived ? null : () => _deleteItem(summary),
    ),
    _LinkedLineRow(:final summary, :final folder) => _ItemTile(
      summary: summary,
      amountWidth: section.amountWidth,
      chip: folder == null ? const UnfiledChip() : FolderChip.forFolder(folder),
      indent: true,
      expanded: null,
      onToggleExpanded: null,
      onMove: () => _moveItem(summary),
      onDelete: () => _deleteItem(summary),
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
              // Grows with the system text size so the chips' names are
              // never clipped by a hard 48 dp strip at 200 % scale.
              height: MediaQuery.textScalerOf(
                context,
              ).scale(48).clamp(48.0, 96.0),
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

/// One jump-to-folder chip (spec §4): the folder's own small [FolderChip],
/// its name, its count. The active chip fills with the folder tint;
/// identity is never the mark alone — the name is always beside it.
///
/// The mark used to be a hand-rolled 8 dp dot painted straight from
/// [folderHueSeeds], and that was a real defect: the seeds are dark by
/// construction (fern is #356859) because they are seeds for a light page,
/// so on the dark ramp's #141613 surface the eight dots measured 2.8-3.7:1
/// — under the 4.5:1 every folder ink is built to clear, and under the 3:1
/// UI floor for four of them. [FolderPalette] exists precisely so that no
/// widget derives a folder colour by hand: `pair(hue).ink` is the hue's
/// solid-mark colour for the LIVE brightness, and the chip that draws it is
/// the same one every other folder surface uses.
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
    final fill = active
        ? (colors?.tint ?? scheme.surfaceContainerHigh)
        : Colors.transparent;
    // The label carries the hue too, not just the mark: `ink` is built to
    // clear 4.5:1 on the page in BOTH brightnesses, so a folder-coloured
    // name is legible where a seed-coloured one would not be.
    final ink = colors?.ink ?? scheme.onSurface;
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
              // Constraints, not a fixed height: at 200 % text scale the
              // name has to be allowed to grow the chip.
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.m,
                vertical: Space.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  folder == null
                      ? const UnfiledChip(size: FolderChipSize.small)
                      : FolderChip.forFolder(
                          folder!,
                          size: FolderChipSize.small,
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

/// Pinned section header (spec §4). Fixed 52 dp so jump offsets stay exact.
///
/// The delegate holds DATA ONLY and resolves no theme: a
/// `SliverPersistentHeader` caches the widget its delegate built and only
/// re-runs `build` when `shouldRebuild` says so, and `shouldRebuild` cannot
/// see a `ColorScheme`. A delegate that read `Theme.of(context)` therefore
/// froze the colours of whichever brightness happened to be live when the
/// section first appeared — flipping the system to dark left cream headers
/// stranded on a near-black list. The colours live in [_SectionHeaderBar],
/// an ordinary widget whose own element depends on the theme and rebuilds
/// with it.
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
  ) => _SectionHeaderBar(
    title: title,
    folder: folder,
    count: count,
    collapsed: collapsed,
    onTap: onTap,
  );

  @override
  bool shouldRebuild(_SectionHeaderDelegate oldDelegate) =>
      oldDelegate.title != title ||
      oldDelegate.count != count ||
      oldDelegate.collapsed != collapsed ||
      oldDelegate.folder != folder ||
      (oldDelegate.onTap == null) != (onTap == null);
}

/// The header's actual pixels: 24 dp chip, name, count, chevron, on the
/// folder's own tint with a bottom hairline. Whole row tappable to
/// collapse/expand.
///
/// The band is folder-coloured, not grey: a section is the folder, and the
/// tint is the same barely-there wash the chip fills with (opaque, so it
/// still pins cleanly over scrolling rows) with the name in the folder's
/// ink. Unfiled and Archived have no hue and keep the neutral raised
/// surface — which is what makes the coloured ones read as identity.
class _SectionHeaderBar extends StatelessWidget {
  const _SectionHeaderBar({
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = folder == null
        ? null
        : FolderPalette.of(context).pair(folder!.effectiveHue);
    return Material(
      color: colors?.tint ?? scheme.surfaceContainerLow,
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
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colors?.ink,
                          ),
                        ),
                      ),
                      Text(
                        '$count',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors?.ink ?? scheme.onSurfaceVariant,
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
                            color: colors?.ink ?? scheme.onSurfaceVariant,
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
/// first-class "Move to folder…" and "Delete…".
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.summary,
    required this.amountWidth,
    required this.chip,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onMove,
    required this.onDelete,
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

  /// "Delete…" beneath "Move to folder…" — set exactly where [onMove] is.
  final VoidCallback? onDelete;

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
    final facts = [
      if (item.category != null) item.category!,
      if (item.servesPerUnit != null)
        'One serves ${formatMicros(item.servesPerUnit!.micros)}',
      if (item.perPersonRatio != null)
        perPersonRatioPhrase(item.perPersonRatio!),
      if (item.perEventBaseline != null)
        'Usually bring ${formatMicros(item.perEventBaseline!.micros)}',
      if (item.isArchived) 'Archived',
    ].join(' · ');
    // v7: what one costs, at the caption tier — a supporting figure beside
    // the row's own quantity, never a second row-quantity. An item that was
    // never priced shows NOTHING here: "$0" would be a price the owner
    // never gave.
    final price = item.unitPrice;
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
      subtitle: (price == null && facts.isEmpty)
          ? null
          : Text.rich(
              TextSpan(
                children: [
                  if (price != null)
                    TextSpan(
                      text: MoneyCodec.format(price),
                      style: Numerals.caption(
                        theme.textTheme,
                      )?.copyWith(color: theme.colorScheme.onSurface),
                    ),
                  if (price != null && facts.isNotEmpty)
                    const TextSpan(text: ' · '),
                  if (facts.isNotEmpty) TextSpan(text: facts),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
                    onSelected: (value) {
                      switch (value) {
                        case 'move':
                          onMove!();
                        case 'delete':
                          onDelete?.call();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'move',
                        child: Text('Move to folder…'),
                      ),
                      if (onDelete != null)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete…'),
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
