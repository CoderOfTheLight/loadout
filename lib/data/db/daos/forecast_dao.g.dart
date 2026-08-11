// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'forecast_dao.dart';

// ignore_for_file: type=lint
mixin _$ForecastDaoMixin on DatabaseAccessor<AppDatabase> {
  $EventsTable get events => attachedDatabase.events;
  $CommandsTable get commands => attachedDatabase.commands;
  $ForecastSnapshotsTable get forecastSnapshots =>
      attachedDatabase.forecastSnapshots;
  $ItemsTable get items => attachedDatabase.items;
  $ForecastLinesTable get forecastLines => attachedDatabase.forecastLines;
  $EventCloseoutsTable get eventCloseouts => attachedDatabase.eventCloseouts;
  $ForecastEvidenceTable get forecastEvidence =>
      attachedDatabase.forecastEvidence;
  $ForecastOverridesTable get forecastOverrides =>
      attachedDatabase.forecastOverrides;
  $InventoryMovementsTable get inventoryMovements =>
      attachedDatabase.inventoryMovements;
  $CloseoutLinesTable get closeoutLines => attachedDatabase.closeoutLines;
  ForecastDaoManager get managers => ForecastDaoManager(this);
}

class ForecastDaoManager {
  final _$ForecastDaoMixin _db;
  ForecastDaoManager(this._db);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db.attachedDatabase, _db.events);
  $$CommandsTableTableManager get commands =>
      $$CommandsTableTableManager(_db.attachedDatabase, _db.commands);
  $$ForecastSnapshotsTableTableManager get forecastSnapshots =>
      $$ForecastSnapshotsTableTableManager(
        _db.attachedDatabase,
        _db.forecastSnapshots,
      );
  $$ItemsTableTableManager get items =>
      $$ItemsTableTableManager(_db.attachedDatabase, _db.items);
  $$ForecastLinesTableTableManager get forecastLines =>
      $$ForecastLinesTableTableManager(_db.attachedDatabase, _db.forecastLines);
  $$EventCloseoutsTableTableManager get eventCloseouts =>
      $$EventCloseoutsTableTableManager(
        _db.attachedDatabase,
        _db.eventCloseouts,
      );
  $$ForecastEvidenceTableTableManager get forecastEvidence =>
      $$ForecastEvidenceTableTableManager(
        _db.attachedDatabase,
        _db.forecastEvidence,
      );
  $$ForecastOverridesTableTableManager get forecastOverrides =>
      $$ForecastOverridesTableTableManager(
        _db.attachedDatabase,
        _db.forecastOverrides,
      );
  $$InventoryMovementsTableTableManager get inventoryMovements =>
      $$InventoryMovementsTableTableManager(
        _db.attachedDatabase,
        _db.inventoryMovements,
      );
  $$CloseoutLinesTableTableManager get closeoutLines =>
      $$CloseoutLinesTableTableManager(_db.attachedDatabase, _db.closeoutLines);
}
