// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'command_dao.dart';

// ignore_for_file: type=lint
mixin _$CommandDaoMixin on DatabaseAccessor<AppDatabase> {
  $CommandsTable get commands => attachedDatabase.commands;
  CommandDaoManager get managers => CommandDaoManager(this);
}

class CommandDaoManager {
  final _$CommandDaoMixin _db;
  CommandDaoManager(this._db);
  $$CommandsTableTableManager get commands =>
      $$CommandsTableTableManager(_db.attachedDatabase, _db.commands);
}
