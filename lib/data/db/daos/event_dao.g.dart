// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_dao.dart';

// ignore_for_file: type=lint
mixin _$EventDaoMixin on DatabaseAccessor<AppDatabase> {
  $EventsTable get events => attachedDatabase.events;
  $ItemsTable get items => attachedDatabase.items;
  $EventItemsTable get eventItems => attachedDatabase.eventItems;
  EventDaoManager get managers => EventDaoManager(this);
}

class EventDaoManager {
  final _$EventDaoMixin _db;
  EventDaoManager(this._db);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db.attachedDatabase, _db.events);
  $$ItemsTableTableManager get items =>
      $$ItemsTableTableManager(_db.attachedDatabase, _db.items);
  $$EventItemsTableTableManager get eventItems =>
      $$EventItemsTableTableManager(_db.attachedDatabase, _db.eventItems);
}
