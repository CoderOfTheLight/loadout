/// Feature-local catalog filters for the recipe screens.
///
/// The proposal's rule: "Sales-table items simply never appear here" — no
/// recipe can make or consume a CD. The schema carries no structural
/// sales-table marker (folders are just named rows the owner manages), so
/// the recipe screens recognise a sales-table folder BY NAME: any live
/// folder whose name contains the word "sale"/"sales" or
/// "merch"/"merchandise", case-insensitively. The starter folder "Sales
/// table" matches; a folder the owner renames to something else stops
/// matching — a documented limit of a name-based rule, and the only rule
/// the data allows.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../catalog/domain/folder.dart';

final RegExp _salesTableWord = RegExp(
  r'\b(sales?|merch|merchandise)\b',
  caseSensitive: false,
);

/// True when [name] reads as a sales/merch-table folder.
bool isSalesTableFolderName(String name) => _salesTableWord.hasMatch(name);

/// Live folders in the owner's order — the paste sheet's "new items go in"
/// picker reads this.
final recipeFolderListProvider = StreamProvider.autoDispose<List<Folder>>(
  (ref) => ref.watch(catalogServiceProvider).watchFolders(),
);

/// Ids of live folders that read as the sales table, or null while the
/// folder list is still loading (callers gate on null so a late emission
/// can never flash sales-table items into a recipe picker).
final salesTableFolderIdsProvider = Provider.autoDispose<Set<String>?>((ref) {
  final folders = ref.watch(recipeFolderListProvider).valueOrNull;
  if (folders == null) return null;
  return {
    for (final folder in folders)
      if (isSalesTableFolderName(folder.name)) folder.id.value,
  };
});
