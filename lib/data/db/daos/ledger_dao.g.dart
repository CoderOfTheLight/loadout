// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ledger_dao.dart';

// ignore_for_file: type=lint
mixin _$LedgerDaoMixin on DatabaseAccessor<AppDatabase> {
  $ItemsTable get items => attachedDatabase.items;
  $EventsTable get events => attachedDatabase.events;
  $CommandsTable get commands => attachedDatabase.commands;
  $InventoryMovementsTable get inventoryMovements =>
      attachedDatabase.inventoryMovements;
  LedgerDaoManager get managers => LedgerDaoManager(this);
}

class LedgerDaoManager {
  final _$LedgerDaoMixin _db;
  LedgerDaoManager(this._db);
  $$ItemsTableTableManager get items =>
      $$ItemsTableTableManager(_db.attachedDatabase, _db.items);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db.attachedDatabase, _db.events);
  $$CommandsTableTableManager get commands =>
      $$CommandsTableTableManager(_db.attachedDatabase, _db.commands);
  $$InventoryMovementsTableTableManager get inventoryMovements =>
      $$InventoryMovementsTableTableManager(
        _db.attachedDatabase,
        _db.inventoryMovements,
      );
}
