import 'package:drift/drift.dart';

import '../../../core/ids.dart';
import '../../../core/time.dart';
import '../../../data/db/app_database.dart';
import '../domain/inventory_ledger.dart';
import '../domain/ledger_math.dart';
import '../domain/movement.dart' as domain;

/// Drift implementation of the [InventoryLedger] seam (design §6.3).
/// Queries are the open read path; the write methods are called ONLY by the
/// CommandApplier inside its transaction (drift zone transactions make the
/// calls participate automatically).
final class DriftInventoryLedger implements InventoryLedger {
  DriftInventoryLedger(
    AppDatabase db, {
    IdGenerator idGenerator = const UlidIdGenerator(),
  }) : _db = db,
       _ids = idGenerator;

  final AppDatabase _db;
  final IdGenerator _ids;

  @override
  Future<StockPosition> position(ItemId item, {Instant? asOf}) async {
    if (asOf == null) {
      return StockPosition(
        onHandMicros: await _db.ledgerDao.onHandMicros(item as String),
      );
    }
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(delta_micros), 0) AS on_hand '
          'FROM inventory_movements '
          'WHERE item_id = ?1 AND occurred_at_micros <= ?2',
          variables: [
            Variable<String>(item as String),
            Variable<int>(asOf.epochMicrosUtc),
          ],
          readsFrom: {_db.inventoryMovements},
        )
        .getSingle();
    return StockPosition(onHandMicros: row.read<int>('on_hand'));
  }

  @override
  Future<Map<ItemId, StockPosition>> positions({Instant? asOf}) async {
    final rows = await _db
        .customSelect(
          'SELECT item_id, SUM(delta_micros) AS on_hand '
          'FROM inventory_movements '
          '${asOf == null ? '' : 'WHERE occurred_at_micros <= ?1 '}'
          'GROUP BY item_id',
          variables: [if (asOf != null) Variable<int>(asOf.epochMicrosUtc)],
          readsFrom: {_db.inventoryMovements},
        )
        .get();
    return {
      for (final row in rows)
        ItemId(row.read<String>('item_id')): StockPosition(
          onHandMicros: row.read<int>('on_hand'),
        ),
    };
  }

  @override
  Future<List<domain.Movement>> movements({
    ItemId? item,
    EventId? event,
    Instant? from,
    Instant? to,
  }) async {
    final query = _db.select(_db.inventoryMovements)
      ..orderBy([
        (m) => OrderingTerm.asc(m.occurredAtMicros),
        (m) => OrderingTerm.asc(m.recordedAtMicros),
        (m) => OrderingTerm.asc(m.id),
      ]);
    if (item != null) {
      query.where((m) => m.itemId.equals(item as String));
    }
    if (event != null) {
      query.where((m) => m.eventId.equals(event as String));
    }
    if (from != null) {
      query.where(
        (m) => m.occurredAtMicros.isBiggerOrEqualValue(from.epochMicrosUtc),
      );
    }
    if (to != null) {
      query.where(
        (m) => m.occurredAtMicros.isSmallerOrEqualValue(to.epochMicrosUtc),
      );
    }
    final rows = await query.get();
    return [for (final row in rows) _toDomain(row)];
  }

  @override
  Future<domain.Movement?> movement(MovementId id) async {
    final row = await (_db.select(
      _db.inventoryMovements,
    )..where((m) => m.id.equals(id as String))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Stream<StockPosition> watchPosition(ItemId item) => _db
      .customSelect(
        'SELECT COALESCE(SUM(delta_micros), 0) AS on_hand '
        'FROM inventory_movements WHERE item_id = ?1',
        variables: [Variable<String>(item as String)],
        readsFrom: {_db.inventoryMovements},
      )
      .watchSingle()
      .map((row) => StockPosition(onHandMicros: row.read<int>('on_hand')));

  @override
  Stream<int> watchVersion() => _db
      .customSelect(
        'SELECT COALESCE(MAX(rowid), 0) AS version FROM inventory_movements',
        readsFrom: {_db.inventoryMovements},
      )
      .watchSingle()
      .map((row) => row.read<int>('version'));

  @override
  Future<domain.Movement> appendMovement(
    MovementDraft draft, {
    required CommandId sourceCommandId,
    required Instant recordedAt,
  }) async {
    final id = _ids.newId();
    final occurredAt = draft.occurredAt ?? recordedAt;
    await _db
        .into(_db.inventoryMovements)
        .insert(
          InventoryMovementsCompanion.insert(
            id: id,
            itemId: draft.itemId as String,
            kind: draft.kind.dbValue,
            deltaMicros: draft.deltaMicros,
            eventId: Value(draft.eventId as String?),
            sourceCommandId: sourceCommandId as String,
            occurredAtMicros: occurredAt.epochMicrosUtc,
            recordedAtMicros: recordedAt.epochMicrosUtc,
            note: Value(draft.note),
          ),
        );
    return (await movement(MovementId(id)))!;
  }

  @override
  Future<domain.Movement> reverseMovement({
    required MovementId target,
    required String reason,
    required Instant occurredAt,
    required CommandId sourceCommandId,
    required Instant recordedAt,
  }) async {
    final targetRow = await (_db.select(
      _db.inventoryMovements,
    )..where((m) => m.id.equals(target as String))).getSingleOrNull();
    if (targetRow == null) {
      throw StateError('reverseMovement target does not exist');
    }
    final id = _ids.newId();
    await _db
        .into(_db.inventoryMovements)
        .insert(
          InventoryMovementsCompanion.insert(
            id: id,
            itemId: targetRow.itemId,
            kind: domain.MovementKind.reversal.dbValue,
            deltaMicros: -targetRow.deltaMicros,
            eventId: Value(targetRow.eventId),
            reversesMovementId: Value(targetRow.id),
            sourceCommandId: sourceCommandId as String,
            occurredAtMicros: occurredAt.epochMicrosUtc,
            recordedAtMicros: recordedAt.epochMicrosUtc,
            note: Value(reason),
          ),
        );
    return (await movement(MovementId(id)))!;
  }

  domain.Movement _toDomain(InventoryMovement row) => domain.Movement(
    id: MovementId(row.id),
    itemId: ItemId(row.itemId),
    kind: domain.MovementKind.fromDb(row.kind),
    deltaMicros: row.deltaMicros,
    eventId: row.eventId == null ? null : EventId(row.eventId!),
    reverses: row.reversesMovementId == null
        ? null
        : MovementId(row.reversesMovementId!),
    occurredAt: Instant(row.occurredAtMicros),
    recordedAt: Instant(row.recordedAtMicros),
    sourceCommandId: CommandId(row.sourceCommandId),
    note: row.note,
  );
}
