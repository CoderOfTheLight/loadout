// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'closeout_dao.dart';

// ignore_for_file: type=lint
mixin _$CloseoutDaoMixin on DatabaseAccessor<AppDatabase> {
  $EventsTable get events => attachedDatabase.events;
  $CommandsTable get commands => attachedDatabase.commands;
  $EventCloseoutsTable get eventCloseouts => attachedDatabase.eventCloseouts;
  $FoldersTable get folders => attachedDatabase.folders;
  $ItemsTable get items => attachedDatabase.items;
  $InventoryMovementsTable get inventoryMovements =>
      attachedDatabase.inventoryMovements;
  $CloseoutLinesTable get closeoutLines => attachedDatabase.closeoutLines;
  $CloseoutDraftsTable get closeoutDrafts => attachedDatabase.closeoutDrafts;
  CloseoutDaoManager get managers => CloseoutDaoManager(this);
}

class CloseoutDaoManager {
  final _$CloseoutDaoMixin _db;
  CloseoutDaoManager(this._db);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db.attachedDatabase, _db.events);
  $$CommandsTableTableManager get commands =>
      $$CommandsTableTableManager(_db.attachedDatabase, _db.commands);
  $$EventCloseoutsTableTableManager get eventCloseouts =>
      $$EventCloseoutsTableTableManager(
        _db.attachedDatabase,
        _db.eventCloseouts,
      );
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db.attachedDatabase, _db.folders);
  $$ItemsTableTableManager get items =>
      $$ItemsTableTableManager(_db.attachedDatabase, _db.items);
  $$InventoryMovementsTableTableManager get inventoryMovements =>
      $$InventoryMovementsTableTableManager(
        _db.attachedDatabase,
        _db.inventoryMovements,
      );
  $$CloseoutLinesTableTableManager get closeoutLines =>
      $$CloseoutLinesTableTableManager(_db.attachedDatabase, _db.closeoutLines);
  $$CloseoutDraftsTableTableManager get closeoutDrafts =>
      $$CloseoutDraftsTableTableManager(
        _db.attachedDatabase,
        _db.closeoutDrafts,
      );
}
