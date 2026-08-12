/// Feature-local providers for the movement detail / correction screens.
///
/// [movementProvenanceProvider] resolves ONE movement with everything §9's
/// MovementDetailScreen needs: item display fields, correction links (both
/// directions plus the replacement written by the same correction command),
/// and whether the row was written by closeout application — consume-kind
/// and closeout-linked movements are refused by the applier's
/// `CorrectMovement` validator, so the screens surface that state instead
/// of offering the action.
library;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/ids.dart';
import '../../../core/time.dart';
import '../../../core/units.dart';
import '../domain/movement.dart';

/// One movement plus its provenance/correction context.
final class MovementProvenance {
  const MovementProvenance({
    required this.movement,
    required this.itemName,
    required this.itemUnit,
    this.reversedByMovementId,
    this.replacementMovementId,
    required this.isCloseoutLinked,
  });

  final Movement movement;
  final String itemName;
  final ItemUnit itemUnit;

  /// Reversal row targeting this movement, when it has been corrected.
  final String? reversedByMovementId;

  /// Replacement movement written by the same `CorrectMovement` command as
  /// [reversedByMovementId], when the correction carried one. Meaningless
  /// for closeout-written rows (revisions write many rows per command).
  final String? replacementMovementId;

  /// True when a closeout line links this row (consume or waste written by
  /// closeout application).
  final bool isCloseoutLinked;

  bool get isReversal => movement.kind == MovementKind.reversal;

  /// Written by closeout application — corrected only via closeout
  /// revisions, never via `CorrectMovement` (§5).
  bool get isCloseoutWritten =>
      movement.kind == MovementKind.consume || isCloseoutLinked;

  bool get isCorrected => reversedByMovementId != null;

  /// Whether the applier would accept a `CorrectMovement` for this row.
  bool get isCorrectable => !isReversal && !isCloseoutWritten && !isCorrected;
}

const String _provenanceSql =
    'SELECT m.*, i.name AS item_name, i.unit AS item_unit, '
    'r.id AS reversed_by, '
    '(SELECT rep.id FROM inventory_movements rep '
    " WHERE r.id IS NOT NULL AND rep.kind != 'reversal' "
    ' AND rep.source_command_id = r.source_command_id LIMIT 1) '
    ' AS replacement_id, '
    'EXISTS(SELECT 1 FROM closeout_lines cl '
    ' WHERE cl.consumption_movement_id = m.id '
    ' OR cl.waste_movement_id = m.id) AS closeout_linked '
    'FROM inventory_movements m '
    'JOIN items i ON i.id = m.item_id '
    'LEFT JOIN inventory_movements r ON r.reverses_movement_id = m.id '
    'WHERE m.id = ?1';

/// Null for unknown ids (guard in the screen). Live: correcting the row
/// flips [MovementProvenance.isCorrected] through the same stream.
final movementProvenanceProvider = StreamProvider.autoDispose
    .family<MovementProvenance?, String>((ref, movementId) {
      final db = ref.watch(appDatabaseProvider);
      return db
          .customSelect(
            _provenanceSql,
            variables: [Variable<String>(movementId)],
            readsFrom: {db.inventoryMovements, db.items, db.closeoutLines},
          )
          .watchSingleOrNull()
          .map((row) {
            if (row == null) return null;
            return MovementProvenance(
              movement: Movement(
                id: MovementId(row.read<String>('id')),
                itemId: ItemId(row.read<String>('item_id')),
                kind: MovementKind.fromDb(row.read<String>('kind')),
                deltaMicros: row.read<int>('delta_micros'),
                eventId: row.read<String?>('event_id') == null
                    ? null
                    : EventId(row.read<String>('event_id')),
                reverses: row.read<String?>('reverses_movement_id') == null
                    ? null
                    : MovementId(row.read<String>('reverses_movement_id')),
                occurredAt: Instant(row.read<int>('occurred_at_micros')),
                recordedAt: Instant(row.read<int>('recorded_at_micros')),
                sourceCommandId: CommandId(
                  row.read<String>('source_command_id'),
                ),
                note: row.read<String>('note'),
              ),
              itemName: row.read<String>('item_name'),
              itemUnit: ItemUnit.fromDb(row.read<String>('item_unit')),
              reversedByMovementId: row.read<String?>('reversed_by'),
              replacementMovementId: row.read<String?>('replacement_id'),
              isCloseoutLinked: row.read<bool>('closeout_linked'),
            );
          });
    });
