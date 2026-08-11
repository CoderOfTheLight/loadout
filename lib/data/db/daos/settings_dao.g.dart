// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_dao.dart';

// ignore_for_file: type=lint
mixin _$SettingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $WorkspaceMetaTable get workspaceMeta => attachedDatabase.workspaceMeta;
  $SettingsTable get settings => attachedDatabase.settings;
  SettingsDaoManager get managers => SettingsDaoManager(this);
}

class SettingsDaoManager {
  final _$SettingsDaoMixin _db;
  SettingsDaoManager(this._db);
  $$WorkspaceMetaTableTableManager get workspaceMeta =>
      $$WorkspaceMetaTableTableManager(_db.attachedDatabase, _db.workspaceMeta);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db.attachedDatabase, _db.settings);
}
