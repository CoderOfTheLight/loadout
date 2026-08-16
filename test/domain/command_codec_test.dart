/// Canonical encoding for the delete commands (design §6.4): stable kind
/// strings and byte-for-byte payload shapes — the encoding IS the
/// idempotency comparison, so these bytes are pinned exactly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/core/ids.dart';
import 'package:loadout/core/quantity.dart';
import 'package:loadout/features/approval/domain/command_codec.dart';
import 'package:loadout/features/approval/domain/commands.dart';
import 'package:loadout/features/recipes/domain/recipe_drafts.dart';

void main() {
  test('DeleteItem: kind and the bare item_id payload', () {
    final command = DeleteItem(itemId: ItemId('A' * 26));
    expect(commandKind(command), 'DeleteItem');
    expect(encodeCommandPayload(command), '{"item_id":"${'A' * 26}"}');
  });

  test('DeleteAllItems: kind and the empty-object payload', () {
    const command = DeleteAllItems();
    expect(commandKind(command), 'DeleteAllItems');
    expect(encodeCommandPayload(command), '{}');
  });

  group('AddRecipeRevision carries the optional rename', () {
    final revision = RecipeRevisionDraft(
      yieldQuantity: Quantity.whole(10),
      lines: [
        RecipeLineDraft(name: 'Cumin', quantityPerBatch: Quantity.whole(1)),
      ],
    );
    final revisionJson =
        '{"yield_micros":10000000,"yield_label":null,"note":"",'
        '"source_kind":"form","lines":[{"name":"Cumin","unit_label":null,'
        '"ingredient_item_id":null,"quantity_per_batch_micros":1000000}]}';

    test('name null (keep the current name) is written explicitly', () {
      final command = AddRecipeRevision(
        recipeId: RecipeId('R' * 26),
        revision: revision,
      );
      expect(commandKind(command), 'AddRecipeRevision');
      expect(
        encodeCommandPayload(command),
        '{"recipe_id":"${'R' * 26}","name":null,"revision":$revisionJson}',
      );
    });

    test('a set name rides between recipe_id and revision', () {
      final command = AddRecipeRevision(
        recipeId: RecipeId('R' * 26),
        revision: revision,
        name: 'Chilli supreme',
      );
      expect(
        encodeCommandPayload(command),
        '{"recipe_id":"${'R' * 26}","name":"Chilli supreme",'
        '"revision":$revisionJson}',
      );
    });
  });
}
