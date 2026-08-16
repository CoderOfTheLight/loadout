/// Canonical encoding pins (design §6.4): stable kind strings and
/// byte-for-byte payload shapes — the encoding IS the idempotency
/// comparison, so these bytes are pinned exactly.
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

  group('v6 barcode payload keys ride next to the unit_label keys', () {
    test('CreateItem: barcode written explicitly, null when never scanned', () {
      const command = CreateItem(name: 'Buns', barcode: '5000112637922');
      expect(commandKind(command), 'CreateItem');
      expect(
        encodeCommandPayload(command),
        '{"name":"Buns","unit":"each","pack_size_micros":1000000,'
        '"unit_label":null,"barcode":"5000112637922",'
        '"serves_per_unit_micros":null,"per_person_numerator":null,'
        '"per_person_denominator":null,"folder_id":null,'
        '"demand_basis":null,"per_event_baseline_micros":null,'
        '"opening_count_micros":null,"category":null,"notes":""}',
      );
    });

    test('UpdateItem: barcode and clear_barcode both encode', () {
      final command = UpdateItem(
        itemId: ItemId('A' * 26),
        barcode: '5000112637922',
      );
      expect(commandKind(command), 'UpdateItem');
      expect(
        encodeCommandPayload(command),
        '{"item_id":"${'A' * 26}","name":null,"unit":null,'
        '"pack_size_micros":null,"unit_label":null,"clear_unit_label":false,'
        '"barcode":"5000112637922","clear_barcode":false,'
        '"serves_per_unit_micros":null,"clear_serves_per_unit":false,'
        '"per_person_numerator":null,"per_person_denominator":null,'
        '"clear_per_person_ratio":false,"folder_id":null,'
        '"clear_folder":false,"demand_basis":null,"clear_demand_basis":false,'
        '"per_event_baseline_micros":null,"clear_per_event_baseline":false,'
        '"category":null,"notes":null}',
      );
    });

    test('UpdateItem: a clear encodes null + true, byte-stable', () {
      final command = UpdateItem(itemId: ItemId('A' * 26), clearBarcode: true);
      expect(
        encodeCommandPayload(command),
        contains('"barcode":null,"clear_barcode":true'),
      );
    });
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
