// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $WorkspaceMetaTable extends WorkspaceMeta
    with TableInfo<$WorkspaceMetaTable, WorkspaceMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkspaceMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    check: () => id.equals(1),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _workspaceUidMeta = const VerificationMeta(
    'workspaceUid',
  );
  @override
  late final GeneratedColumn<String> workspaceUid = GeneratedColumn<String>(
    'workspace_uid',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 26,
      maxTextLength: 26,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('My workspace'),
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdByAppVersionMeta =
      const VerificationMeta('createdByAppVersion');
  @override
  late final GeneratedColumn<String> createdByAppVersion =
      GeneratedColumn<String>(
        'created_by_app_version',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    workspaceUid,
    displayName,
    createdAtMicros,
    createdByAppVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workspace_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkspaceMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('workspace_uid')) {
      context.handle(
        _workspaceUidMeta,
        workspaceUid.isAcceptableOrUnknown(
          data['workspace_uid']!,
          _workspaceUidMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceUidMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    if (data.containsKey('created_by_app_version')) {
      context.handle(
        _createdByAppVersionMeta,
        createdByAppVersion.isAcceptableOrUnknown(
          data['created_by_app_version']!,
          _createdByAppVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdByAppVersionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WorkspaceMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkspaceMetaData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      workspaceUid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_uid'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
      createdByAppVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by_app_version'],
      )!,
    );
  }

  @override
  $WorkspaceMetaTable createAlias(String alias) {
    return $WorkspaceMetaTable(attachedDatabase, alias);
  }
}

class WorkspaceMetaData extends DataClass
    implements Insertable<WorkspaceMetaData> {
  final int id;
  final String workspaceUid;
  final String displayName;
  final int createdAtMicros;
  final String createdByAppVersion;
  const WorkspaceMetaData({
    required this.id,
    required this.workspaceUid,
    required this.displayName,
    required this.createdAtMicros,
    required this.createdByAppVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['workspace_uid'] = Variable<String>(workspaceUid);
    map['display_name'] = Variable<String>(displayName);
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    map['created_by_app_version'] = Variable<String>(createdByAppVersion);
    return map;
  }

  WorkspaceMetaCompanion toCompanion(bool nullToAbsent) {
    return WorkspaceMetaCompanion(
      id: Value(id),
      workspaceUid: Value(workspaceUid),
      displayName: Value(displayName),
      createdAtMicros: Value(createdAtMicros),
      createdByAppVersion: Value(createdByAppVersion),
    );
  }

  factory WorkspaceMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkspaceMetaData(
      id: serializer.fromJson<int>(json['id']),
      workspaceUid: serializer.fromJson<String>(json['workspaceUid']),
      displayName: serializer.fromJson<String>(json['displayName']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
      createdByAppVersion: serializer.fromJson<String>(
        json['createdByAppVersion'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'workspaceUid': serializer.toJson<String>(workspaceUid),
      'displayName': serializer.toJson<String>(displayName),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
      'createdByAppVersion': serializer.toJson<String>(createdByAppVersion),
    };
  }

  WorkspaceMetaData copyWith({
    int? id,
    String? workspaceUid,
    String? displayName,
    int? createdAtMicros,
    String? createdByAppVersion,
  }) => WorkspaceMetaData(
    id: id ?? this.id,
    workspaceUid: workspaceUid ?? this.workspaceUid,
    displayName: displayName ?? this.displayName,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
    createdByAppVersion: createdByAppVersion ?? this.createdByAppVersion,
  );
  WorkspaceMetaData copyWithCompanion(WorkspaceMetaCompanion data) {
    return WorkspaceMetaData(
      id: data.id.present ? data.id.value : this.id,
      workspaceUid: data.workspaceUid.present
          ? data.workspaceUid.value
          : this.workspaceUid,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
      createdByAppVersion: data.createdByAppVersion.present
          ? data.createdByAppVersion.value
          : this.createdByAppVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkspaceMetaData(')
          ..write('id: $id, ')
          ..write('workspaceUid: $workspaceUid, ')
          ..write('displayName: $displayName, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('createdByAppVersion: $createdByAppVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    workspaceUid,
    displayName,
    createdAtMicros,
    createdByAppVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspaceMetaData &&
          other.id == this.id &&
          other.workspaceUid == this.workspaceUid &&
          other.displayName == this.displayName &&
          other.createdAtMicros == this.createdAtMicros &&
          other.createdByAppVersion == this.createdByAppVersion);
}

class WorkspaceMetaCompanion extends UpdateCompanion<WorkspaceMetaData> {
  final Value<int> id;
  final Value<String> workspaceUid;
  final Value<String> displayName;
  final Value<int> createdAtMicros;
  final Value<String> createdByAppVersion;
  const WorkspaceMetaCompanion({
    this.id = const Value.absent(),
    this.workspaceUid = const Value.absent(),
    this.displayName = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.createdByAppVersion = const Value.absent(),
  });
  WorkspaceMetaCompanion.insert({
    this.id = const Value.absent(),
    required String workspaceUid,
    this.displayName = const Value.absent(),
    required int createdAtMicros,
    required String createdByAppVersion,
  }) : workspaceUid = Value(workspaceUid),
       createdAtMicros = Value(createdAtMicros),
       createdByAppVersion = Value(createdByAppVersion);
  static Insertable<WorkspaceMetaData> custom({
    Expression<int>? id,
    Expression<String>? workspaceUid,
    Expression<String>? displayName,
    Expression<int>? createdAtMicros,
    Expression<String>? createdByAppVersion,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (workspaceUid != null) 'workspace_uid': workspaceUid,
      if (displayName != null) 'display_name': displayName,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (createdByAppVersion != null)
        'created_by_app_version': createdByAppVersion,
    });
  }

  WorkspaceMetaCompanion copyWith({
    Value<int>? id,
    Value<String>? workspaceUid,
    Value<String>? displayName,
    Value<int>? createdAtMicros,
    Value<String>? createdByAppVersion,
  }) {
    return WorkspaceMetaCompanion(
      id: id ?? this.id,
      workspaceUid: workspaceUid ?? this.workspaceUid,
      displayName: displayName ?? this.displayName,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      createdByAppVersion: createdByAppVersion ?? this.createdByAppVersion,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (workspaceUid.present) {
      map['workspace_uid'] = Variable<String>(workspaceUid.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (createdByAppVersion.present) {
      map['created_by_app_version'] = Variable<String>(
        createdByAppVersion.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkspaceMetaCompanion(')
          ..write('id: $id, ')
          ..write('workspaceUid: $workspaceUid, ')
          ..write('displayName: $displayName, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('createdByAppVersion: $createdByAppVersion')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMicrosMeta = const VerificationMeta(
    'updatedAtMicros',
  );
  @override
  late final GeneratedColumn<int> updatedAtMicros = GeneratedColumn<int>(
    'updated_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAtMicros];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at_micros')) {
      context.handle(
        _updatedAtMicrosMeta,
        updatedAtMicros.isAcceptableOrUnknown(
          data['updated_at_micros']!,
          _updatedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_micros'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  final int updatedAtMicros;
  const Setting({
    required this.key,
    required this.value,
    required this.updatedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at_micros'] = Variable<int>(updatedAtMicros);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAtMicros: Value(updatedAtMicros),
    );
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAtMicros: serializer.fromJson<int>(json['updatedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAtMicros': serializer.toJson<int>(updatedAtMicros),
    };
  }

  Setting copyWith({String? key, String? value, int? updatedAtMicros}) =>
      Setting(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
      );
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAtMicros: data.updatedAtMicros.present
          ? data.updatedAtMicros.value
          : this.updatedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAtMicros: $updatedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAtMicros);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAtMicros == this.updatedAtMicros);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> updatedAtMicros;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    required int updatedAtMicros,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       updatedAtMicros = Value(updatedAtMicros);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? updatedAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAtMicros != null) 'updated_at_micros': updatedAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? updatedAtMicros,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAtMicros.present) {
      map['updated_at_micros'] = Variable<int>(updatedAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAtMicros: $updatedAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CommandsTable extends Commands with TableInfo<$CommandsTable, Command> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CommandsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 26,
      maxTextLength: 26,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    check: () => origin.isIn(['form', 'agent']),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    check: () => status.isIn(['staged', 'applied', 'rejected']),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _appliedAtMicrosMeta = const VerificationMeta(
    'appliedAtMicros',
  );
  @override
  late final GeneratedColumn<int> appliedAtMicros = GeneratedColumn<int>(
    'applied_at_micros',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rejectedReasonMeta = const VerificationMeta(
    'rejectedReason',
  );
  @override
  late final GeneratedColumn<String> rejectedReason = GeneratedColumn<String>(
    'rejected_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    origin,
    kind,
    payloadJson,
    status,
    createdAtMicros,
    appliedAtMicros,
    rejectedReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'commands';
  @override
  VerificationContext validateIntegrity(
    Insertable<Command> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    } else if (isInserting) {
      context.missing(_originMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    if (data.containsKey('applied_at_micros')) {
      context.handle(
        _appliedAtMicrosMeta,
        appliedAtMicros.isAcceptableOrUnknown(
          data['applied_at_micros']!,
          _appliedAtMicrosMeta,
        ),
      );
    }
    if (data.containsKey('rejected_reason')) {
      context.handle(
        _rejectedReasonMeta,
        rejectedReason.isAcceptableOrUnknown(
          data['rejected_reason']!,
          _rejectedReasonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Command map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Command(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
      appliedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}applied_at_micros'],
      ),
      rejectedReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rejected_reason'],
      ),
    );
  }

  @override
  $CommandsTable createAlias(String alias) {
    return $CommandsTable(attachedDatabase, alias);
  }
}

class Command extends DataClass implements Insertable<Command> {
  final String id;
  final String origin;
  final String kind;
  final String payloadJson;
  final String status;
  final int createdAtMicros;
  final int? appliedAtMicros;
  final String? rejectedReason;
  const Command({
    required this.id,
    required this.origin,
    required this.kind,
    required this.payloadJson,
    required this.status,
    required this.createdAtMicros,
    this.appliedAtMicros,
    this.rejectedReason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['origin'] = Variable<String>(origin);
    map['kind'] = Variable<String>(kind);
    map['payload_json'] = Variable<String>(payloadJson);
    map['status'] = Variable<String>(status);
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    if (!nullToAbsent || appliedAtMicros != null) {
      map['applied_at_micros'] = Variable<int>(appliedAtMicros);
    }
    if (!nullToAbsent || rejectedReason != null) {
      map['rejected_reason'] = Variable<String>(rejectedReason);
    }
    return map;
  }

  CommandsCompanion toCompanion(bool nullToAbsent) {
    return CommandsCompanion(
      id: Value(id),
      origin: Value(origin),
      kind: Value(kind),
      payloadJson: Value(payloadJson),
      status: Value(status),
      createdAtMicros: Value(createdAtMicros),
      appliedAtMicros: appliedAtMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(appliedAtMicros),
      rejectedReason: rejectedReason == null && nullToAbsent
          ? const Value.absent()
          : Value(rejectedReason),
    );
  }

  factory Command.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Command(
      id: serializer.fromJson<String>(json['id']),
      origin: serializer.fromJson<String>(json['origin']),
      kind: serializer.fromJson<String>(json['kind']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      status: serializer.fromJson<String>(json['status']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
      appliedAtMicros: serializer.fromJson<int?>(json['appliedAtMicros']),
      rejectedReason: serializer.fromJson<String?>(json['rejectedReason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'origin': serializer.toJson<String>(origin),
      'kind': serializer.toJson<String>(kind),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'status': serializer.toJson<String>(status),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
      'appliedAtMicros': serializer.toJson<int?>(appliedAtMicros),
      'rejectedReason': serializer.toJson<String?>(rejectedReason),
    };
  }

  Command copyWith({
    String? id,
    String? origin,
    String? kind,
    String? payloadJson,
    String? status,
    int? createdAtMicros,
    Value<int?> appliedAtMicros = const Value.absent(),
    Value<String?> rejectedReason = const Value.absent(),
  }) => Command(
    id: id ?? this.id,
    origin: origin ?? this.origin,
    kind: kind ?? this.kind,
    payloadJson: payloadJson ?? this.payloadJson,
    status: status ?? this.status,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
    appliedAtMicros: appliedAtMicros.present
        ? appliedAtMicros.value
        : this.appliedAtMicros,
    rejectedReason: rejectedReason.present
        ? rejectedReason.value
        : this.rejectedReason,
  );
  Command copyWithCompanion(CommandsCompanion data) {
    return Command(
      id: data.id.present ? data.id.value : this.id,
      origin: data.origin.present ? data.origin.value : this.origin,
      kind: data.kind.present ? data.kind.value : this.kind,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      status: data.status.present ? data.status.value : this.status,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
      appliedAtMicros: data.appliedAtMicros.present
          ? data.appliedAtMicros.value
          : this.appliedAtMicros,
      rejectedReason: data.rejectedReason.present
          ? data.rejectedReason.value
          : this.rejectedReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Command(')
          ..write('id: $id, ')
          ..write('origin: $origin, ')
          ..write('kind: $kind, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('appliedAtMicros: $appliedAtMicros, ')
          ..write('rejectedReason: $rejectedReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    origin,
    kind,
    payloadJson,
    status,
    createdAtMicros,
    appliedAtMicros,
    rejectedReason,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Command &&
          other.id == this.id &&
          other.origin == this.origin &&
          other.kind == this.kind &&
          other.payloadJson == this.payloadJson &&
          other.status == this.status &&
          other.createdAtMicros == this.createdAtMicros &&
          other.appliedAtMicros == this.appliedAtMicros &&
          other.rejectedReason == this.rejectedReason);
}

class CommandsCompanion extends UpdateCompanion<Command> {
  final Value<String> id;
  final Value<String> origin;
  final Value<String> kind;
  final Value<String> payloadJson;
  final Value<String> status;
  final Value<int> createdAtMicros;
  final Value<int?> appliedAtMicros;
  final Value<String?> rejectedReason;
  final Value<int> rowid;
  const CommandsCompanion({
    this.id = const Value.absent(),
    this.origin = const Value.absent(),
    this.kind = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.appliedAtMicros = const Value.absent(),
    this.rejectedReason = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CommandsCompanion.insert({
    required String id,
    required String origin,
    required String kind,
    required String payloadJson,
    required String status,
    required int createdAtMicros,
    this.appliedAtMicros = const Value.absent(),
    this.rejectedReason = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       origin = Value(origin),
       kind = Value(kind),
       payloadJson = Value(payloadJson),
       status = Value(status),
       createdAtMicros = Value(createdAtMicros);
  static Insertable<Command> custom({
    Expression<String>? id,
    Expression<String>? origin,
    Expression<String>? kind,
    Expression<String>? payloadJson,
    Expression<String>? status,
    Expression<int>? createdAtMicros,
    Expression<int>? appliedAtMicros,
    Expression<String>? rejectedReason,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (origin != null) 'origin': origin,
      if (kind != null) 'kind': kind,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (status != null) 'status': status,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (appliedAtMicros != null) 'applied_at_micros': appliedAtMicros,
      if (rejectedReason != null) 'rejected_reason': rejectedReason,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CommandsCompanion copyWith({
    Value<String>? id,
    Value<String>? origin,
    Value<String>? kind,
    Value<String>? payloadJson,
    Value<String>? status,
    Value<int>? createdAtMicros,
    Value<int?>? appliedAtMicros,
    Value<String?>? rejectedReason,
    Value<int>? rowid,
  }) {
    return CommandsCompanion(
      id: id ?? this.id,
      origin: origin ?? this.origin,
      kind: kind ?? this.kind,
      payloadJson: payloadJson ?? this.payloadJson,
      status: status ?? this.status,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      appliedAtMicros: appliedAtMicros ?? this.appliedAtMicros,
      rejectedReason: rejectedReason ?? this.rejectedReason,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (appliedAtMicros.present) {
      map['applied_at_micros'] = Variable<int>(appliedAtMicros.value);
    }
    if (rejectedReason.present) {
      map['rejected_reason'] = Variable<String>(rejectedReason.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CommandsCompanion(')
          ..write('id: $id, ')
          ..write('origin: $origin, ')
          ..write('kind: $kind, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('appliedAtMicros: $appliedAtMicros, ')
          ..write('rejectedReason: $rejectedReason, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ItemsTable extends Items with TableInfo<$ItemsTable, Item> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 26,
      maxTextLength: 26,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 120,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    false,
    check: () => unit.isIn(['each', 'g', 'kg', 'ml', 'L']),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _packSizeMicrosMeta = const VerificationMeta(
    'packSizeMicros',
  );
  @override
  late final GeneratedColumn<int> packSizeMicros = GeneratedColumn<int>(
    'pack_size_micros',
    aliasedName,
    false,
    check: () => ComparableExpr(packSizeMicros).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 60,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _archivedAtMicrosMeta = const VerificationMeta(
    'archivedAtMicros',
  );
  @override
  late final GeneratedColumn<int> archivedAtMicros = GeneratedColumn<int>(
    'archived_at_micros',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMicrosMeta = const VerificationMeta(
    'updatedAtMicros',
  );
  @override
  late final GeneratedColumn<int> updatedAtMicros = GeneratedColumn<int>(
    'updated_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    unit,
    packSizeMicros,
    category,
    notes,
    archivedAtMicros,
    createdAtMicros,
    updatedAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'items';
  @override
  VerificationContext validateIntegrity(
    Insertable<Item> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    } else if (isInserting) {
      context.missing(_unitMeta);
    }
    if (data.containsKey('pack_size_micros')) {
      context.handle(
        _packSizeMicrosMeta,
        packSizeMicros.isAcceptableOrUnknown(
          data['pack_size_micros']!,
          _packSizeMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_packSizeMicrosMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('archived_at_micros')) {
      context.handle(
        _archivedAtMicrosMeta,
        archivedAtMicros.isAcceptableOrUnknown(
          data['archived_at_micros']!,
          _archivedAtMicrosMeta,
        ),
      );
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    if (data.containsKey('updated_at_micros')) {
      context.handle(
        _updatedAtMicrosMeta,
        updatedAtMicros.isAcceptableOrUnknown(
          data['updated_at_micros']!,
          _updatedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Item map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Item(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      )!,
      packSizeMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pack_size_micros'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      archivedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}archived_at_micros'],
      ),
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
      updatedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_micros'],
      )!,
    );
  }

  @override
  $ItemsTable createAlias(String alias) {
    return $ItemsTable(attachedDatabase, alias);
  }
}

class Item extends DataClass implements Insertable<Item> {
  final String id;
  final String name;
  final String unit;

  /// Purchase/load rounding increment in micros of [unit]. Engine packSize.
  final int packSizeMicros;
  final String? category;
  final String notes;
  final int? archivedAtMicros;
  final int createdAtMicros;
  final int updatedAtMicros;
  const Item({
    required this.id,
    required this.name,
    required this.unit,
    required this.packSizeMicros,
    this.category,
    required this.notes,
    this.archivedAtMicros,
    required this.createdAtMicros,
    required this.updatedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['unit'] = Variable<String>(unit);
    map['pack_size_micros'] = Variable<int>(packSizeMicros);
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    map['notes'] = Variable<String>(notes);
    if (!nullToAbsent || archivedAtMicros != null) {
      map['archived_at_micros'] = Variable<int>(archivedAtMicros);
    }
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    map['updated_at_micros'] = Variable<int>(updatedAtMicros);
    return map;
  }

  ItemsCompanion toCompanion(bool nullToAbsent) {
    return ItemsCompanion(
      id: Value(id),
      name: Value(name),
      unit: Value(unit),
      packSizeMicros: Value(packSizeMicros),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      notes: Value(notes),
      archivedAtMicros: archivedAtMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAtMicros),
      createdAtMicros: Value(createdAtMicros),
      updatedAtMicros: Value(updatedAtMicros),
    );
  }

  factory Item.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Item(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      unit: serializer.fromJson<String>(json['unit']),
      packSizeMicros: serializer.fromJson<int>(json['packSizeMicros']),
      category: serializer.fromJson<String?>(json['category']),
      notes: serializer.fromJson<String>(json['notes']),
      archivedAtMicros: serializer.fromJson<int?>(json['archivedAtMicros']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
      updatedAtMicros: serializer.fromJson<int>(json['updatedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'unit': serializer.toJson<String>(unit),
      'packSizeMicros': serializer.toJson<int>(packSizeMicros),
      'category': serializer.toJson<String?>(category),
      'notes': serializer.toJson<String>(notes),
      'archivedAtMicros': serializer.toJson<int?>(archivedAtMicros),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
      'updatedAtMicros': serializer.toJson<int>(updatedAtMicros),
    };
  }

  Item copyWith({
    String? id,
    String? name,
    String? unit,
    int? packSizeMicros,
    Value<String?> category = const Value.absent(),
    String? notes,
    Value<int?> archivedAtMicros = const Value.absent(),
    int? createdAtMicros,
    int? updatedAtMicros,
  }) => Item(
    id: id ?? this.id,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    packSizeMicros: packSizeMicros ?? this.packSizeMicros,
    category: category.present ? category.value : this.category,
    notes: notes ?? this.notes,
    archivedAtMicros: archivedAtMicros.present
        ? archivedAtMicros.value
        : this.archivedAtMicros,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
    updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
  );
  Item copyWithCompanion(ItemsCompanion data) {
    return Item(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      unit: data.unit.present ? data.unit.value : this.unit,
      packSizeMicros: data.packSizeMicros.present
          ? data.packSizeMicros.value
          : this.packSizeMicros,
      category: data.category.present ? data.category.value : this.category,
      notes: data.notes.present ? data.notes.value : this.notes,
      archivedAtMicros: data.archivedAtMicros.present
          ? data.archivedAtMicros.value
          : this.archivedAtMicros,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
      updatedAtMicros: data.updatedAtMicros.present
          ? data.updatedAtMicros.value
          : this.updatedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Item(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('unit: $unit, ')
          ..write('packSizeMicros: $packSizeMicros, ')
          ..write('category: $category, ')
          ..write('notes: $notes, ')
          ..write('archivedAtMicros: $archivedAtMicros, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    unit,
    packSizeMicros,
    category,
    notes,
    archivedAtMicros,
    createdAtMicros,
    updatedAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Item &&
          other.id == this.id &&
          other.name == this.name &&
          other.unit == this.unit &&
          other.packSizeMicros == this.packSizeMicros &&
          other.category == this.category &&
          other.notes == this.notes &&
          other.archivedAtMicros == this.archivedAtMicros &&
          other.createdAtMicros == this.createdAtMicros &&
          other.updatedAtMicros == this.updatedAtMicros);
}

class ItemsCompanion extends UpdateCompanion<Item> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> unit;
  final Value<int> packSizeMicros;
  final Value<String?> category;
  final Value<String> notes;
  final Value<int?> archivedAtMicros;
  final Value<int> createdAtMicros;
  final Value<int> updatedAtMicros;
  final Value<int> rowid;
  const ItemsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.unit = const Value.absent(),
    this.packSizeMicros = const Value.absent(),
    this.category = const Value.absent(),
    this.notes = const Value.absent(),
    this.archivedAtMicros = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.updatedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ItemsCompanion.insert({
    required String id,
    required String name,
    required String unit,
    required int packSizeMicros,
    this.category = const Value.absent(),
    this.notes = const Value.absent(),
    this.archivedAtMicros = const Value.absent(),
    required int createdAtMicros,
    required int updatedAtMicros,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       unit = Value(unit),
       packSizeMicros = Value(packSizeMicros),
       createdAtMicros = Value(createdAtMicros),
       updatedAtMicros = Value(updatedAtMicros);
  static Insertable<Item> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? unit,
    Expression<int>? packSizeMicros,
    Expression<String>? category,
    Expression<String>? notes,
    Expression<int>? archivedAtMicros,
    Expression<int>? createdAtMicros,
    Expression<int>? updatedAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (unit != null) 'unit': unit,
      if (packSizeMicros != null) 'pack_size_micros': packSizeMicros,
      if (category != null) 'category': category,
      if (notes != null) 'notes': notes,
      if (archivedAtMicros != null) 'archived_at_micros': archivedAtMicros,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (updatedAtMicros != null) 'updated_at_micros': updatedAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? unit,
    Value<int>? packSizeMicros,
    Value<String?>? category,
    Value<String>? notes,
    Value<int?>? archivedAtMicros,
    Value<int>? createdAtMicros,
    Value<int>? updatedAtMicros,
    Value<int>? rowid,
  }) {
    return ItemsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      packSizeMicros: packSizeMicros ?? this.packSizeMicros,
      category: category ?? this.category,
      notes: notes ?? this.notes,
      archivedAtMicros: archivedAtMicros ?? this.archivedAtMicros,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (packSizeMicros.present) {
      map['pack_size_micros'] = Variable<int>(packSizeMicros.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (archivedAtMicros.present) {
      map['archived_at_micros'] = Variable<int>(archivedAtMicros.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (updatedAtMicros.present) {
      map['updated_at_micros'] = Variable<int>(updatedAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ItemsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('unit: $unit, ')
          ..write('packSizeMicros: $packSizeMicros, ')
          ..write('category: $category, ')
          ..write('notes: $notes, ')
          ..write('archivedAtMicros: $archivedAtMicros, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EventsTable extends Events with TableInfo<$EventsTable, Event> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 26,
      maxTextLength: 26,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 120,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _venueMeta = const VerificationMeta('venue');
  @override
  late final GeneratedColumn<String> venue = GeneratedColumn<String>(
    'venue',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scheduledDateMeta = const VerificationMeta(
    'scheduledDate',
  );
  @override
  late final GeneratedColumn<String> scheduledDate = GeneratedColumn<String>(
    'scheduled_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startsAtMicrosMeta = const VerificationMeta(
    'startsAtMicros',
  );
  @override
  late final GeneratedColumn<int> startsAtMicros = GeneratedColumn<int>(
    'starts_at_micros',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endsAtMicrosMeta = const VerificationMeta(
    'endsAtMicros',
  );
  @override
  late final GeneratedColumn<int> endsAtMicros = GeneratedColumn<int>(
    'ends_at_micros',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    check: () => status.isIn(['planned', 'active', 'closed', 'cancelled']),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('planned'),
  );
  static const VerificationMeta _plannedExposureMeta = const VerificationMeta(
    'plannedExposure',
  );
  @override
  late final GeneratedColumn<int> plannedExposure = GeneratedColumn<int>(
    'planned_exposure',
    aliasedName,
    true,
    check: () => ComparableExpr(plannedExposure).isBetweenValues(1, 1000000),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _closedAtMicrosMeta = const VerificationMeta(
    'closedAtMicros',
  );
  @override
  late final GeneratedColumn<int> closedAtMicros = GeneratedColumn<int>(
    'closed_at_micros',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMicrosMeta = const VerificationMeta(
    'updatedAtMicros',
  );
  @override
  late final GeneratedColumn<int> updatedAtMicros = GeneratedColumn<int>(
    'updated_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    venue,
    scheduledDate,
    startsAtMicros,
    endsAtMicros,
    status,
    plannedExposure,
    closedAtMicros,
    notes,
    createdAtMicros,
    updatedAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'events';
  @override
  VerificationContext validateIntegrity(
    Insertable<Event> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('venue')) {
      context.handle(
        _venueMeta,
        venue.isAcceptableOrUnknown(data['venue']!, _venueMeta),
      );
    }
    if (data.containsKey('scheduled_date')) {
      context.handle(
        _scheduledDateMeta,
        scheduledDate.isAcceptableOrUnknown(
          data['scheduled_date']!,
          _scheduledDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledDateMeta);
    }
    if (data.containsKey('starts_at_micros')) {
      context.handle(
        _startsAtMicrosMeta,
        startsAtMicros.isAcceptableOrUnknown(
          data['starts_at_micros']!,
          _startsAtMicrosMeta,
        ),
      );
    }
    if (data.containsKey('ends_at_micros')) {
      context.handle(
        _endsAtMicrosMeta,
        endsAtMicros.isAcceptableOrUnknown(
          data['ends_at_micros']!,
          _endsAtMicrosMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('planned_exposure')) {
      context.handle(
        _plannedExposureMeta,
        plannedExposure.isAcceptableOrUnknown(
          data['planned_exposure']!,
          _plannedExposureMeta,
        ),
      );
    }
    if (data.containsKey('closed_at_micros')) {
      context.handle(
        _closedAtMicrosMeta,
        closedAtMicros.isAcceptableOrUnknown(
          data['closed_at_micros']!,
          _closedAtMicrosMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    if (data.containsKey('updated_at_micros')) {
      context.handle(
        _updatedAtMicrosMeta,
        updatedAtMicros.isAcceptableOrUnknown(
          data['updated_at_micros']!,
          _updatedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Event map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Event(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      venue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}venue'],
      ),
      scheduledDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scheduled_date'],
      )!,
      startsAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}starts_at_micros'],
      ),
      endsAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ends_at_micros'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      plannedExposure: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}planned_exposure'],
      ),
      closedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}closed_at_micros'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
      updatedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_micros'],
      )!,
    );
  }

  @override
  $EventsTable createAlias(String alias) {
    return $EventsTable(attachedDatabase, alias);
  }
}

class Event extends DataClass implements Insertable<Event> {
  final String id;
  final String name;
  final String? venue;
  final String scheduledDate;
  final int? startsAtMicros;
  final int? endsAtMicros;
  final String status;
  final int? plannedExposure;
  final int? closedAtMicros;
  final String? notes;
  final int createdAtMicros;
  final int updatedAtMicros;
  const Event({
    required this.id,
    required this.name,
    this.venue,
    required this.scheduledDate,
    this.startsAtMicros,
    this.endsAtMicros,
    required this.status,
    this.plannedExposure,
    this.closedAtMicros,
    this.notes,
    required this.createdAtMicros,
    required this.updatedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || venue != null) {
      map['venue'] = Variable<String>(venue);
    }
    map['scheduled_date'] = Variable<String>(scheduledDate);
    if (!nullToAbsent || startsAtMicros != null) {
      map['starts_at_micros'] = Variable<int>(startsAtMicros);
    }
    if (!nullToAbsent || endsAtMicros != null) {
      map['ends_at_micros'] = Variable<int>(endsAtMicros);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || plannedExposure != null) {
      map['planned_exposure'] = Variable<int>(plannedExposure);
    }
    if (!nullToAbsent || closedAtMicros != null) {
      map['closed_at_micros'] = Variable<int>(closedAtMicros);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    map['updated_at_micros'] = Variable<int>(updatedAtMicros);
    return map;
  }

  EventsCompanion toCompanion(bool nullToAbsent) {
    return EventsCompanion(
      id: Value(id),
      name: Value(name),
      venue: venue == null && nullToAbsent
          ? const Value.absent()
          : Value(venue),
      scheduledDate: Value(scheduledDate),
      startsAtMicros: startsAtMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(startsAtMicros),
      endsAtMicros: endsAtMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(endsAtMicros),
      status: Value(status),
      plannedExposure: plannedExposure == null && nullToAbsent
          ? const Value.absent()
          : Value(plannedExposure),
      closedAtMicros: closedAtMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(closedAtMicros),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      createdAtMicros: Value(createdAtMicros),
      updatedAtMicros: Value(updatedAtMicros),
    );
  }

  factory Event.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Event(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      venue: serializer.fromJson<String?>(json['venue']),
      scheduledDate: serializer.fromJson<String>(json['scheduledDate']),
      startsAtMicros: serializer.fromJson<int?>(json['startsAtMicros']),
      endsAtMicros: serializer.fromJson<int?>(json['endsAtMicros']),
      status: serializer.fromJson<String>(json['status']),
      plannedExposure: serializer.fromJson<int?>(json['plannedExposure']),
      closedAtMicros: serializer.fromJson<int?>(json['closedAtMicros']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
      updatedAtMicros: serializer.fromJson<int>(json['updatedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'venue': serializer.toJson<String?>(venue),
      'scheduledDate': serializer.toJson<String>(scheduledDate),
      'startsAtMicros': serializer.toJson<int?>(startsAtMicros),
      'endsAtMicros': serializer.toJson<int?>(endsAtMicros),
      'status': serializer.toJson<String>(status),
      'plannedExposure': serializer.toJson<int?>(plannedExposure),
      'closedAtMicros': serializer.toJson<int?>(closedAtMicros),
      'notes': serializer.toJson<String?>(notes),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
      'updatedAtMicros': serializer.toJson<int>(updatedAtMicros),
    };
  }

  Event copyWith({
    String? id,
    String? name,
    Value<String?> venue = const Value.absent(),
    String? scheduledDate,
    Value<int?> startsAtMicros = const Value.absent(),
    Value<int?> endsAtMicros = const Value.absent(),
    String? status,
    Value<int?> plannedExposure = const Value.absent(),
    Value<int?> closedAtMicros = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    int? createdAtMicros,
    int? updatedAtMicros,
  }) => Event(
    id: id ?? this.id,
    name: name ?? this.name,
    venue: venue.present ? venue.value : this.venue,
    scheduledDate: scheduledDate ?? this.scheduledDate,
    startsAtMicros: startsAtMicros.present
        ? startsAtMicros.value
        : this.startsAtMicros,
    endsAtMicros: endsAtMicros.present ? endsAtMicros.value : this.endsAtMicros,
    status: status ?? this.status,
    plannedExposure: plannedExposure.present
        ? plannedExposure.value
        : this.plannedExposure,
    closedAtMicros: closedAtMicros.present
        ? closedAtMicros.value
        : this.closedAtMicros,
    notes: notes.present ? notes.value : this.notes,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
    updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
  );
  Event copyWithCompanion(EventsCompanion data) {
    return Event(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      venue: data.venue.present ? data.venue.value : this.venue,
      scheduledDate: data.scheduledDate.present
          ? data.scheduledDate.value
          : this.scheduledDate,
      startsAtMicros: data.startsAtMicros.present
          ? data.startsAtMicros.value
          : this.startsAtMicros,
      endsAtMicros: data.endsAtMicros.present
          ? data.endsAtMicros.value
          : this.endsAtMicros,
      status: data.status.present ? data.status.value : this.status,
      plannedExposure: data.plannedExposure.present
          ? data.plannedExposure.value
          : this.plannedExposure,
      closedAtMicros: data.closedAtMicros.present
          ? data.closedAtMicros.value
          : this.closedAtMicros,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
      updatedAtMicros: data.updatedAtMicros.present
          ? data.updatedAtMicros.value
          : this.updatedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Event(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('venue: $venue, ')
          ..write('scheduledDate: $scheduledDate, ')
          ..write('startsAtMicros: $startsAtMicros, ')
          ..write('endsAtMicros: $endsAtMicros, ')
          ..write('status: $status, ')
          ..write('plannedExposure: $plannedExposure, ')
          ..write('closedAtMicros: $closedAtMicros, ')
          ..write('notes: $notes, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    venue,
    scheduledDate,
    startsAtMicros,
    endsAtMicros,
    status,
    plannedExposure,
    closedAtMicros,
    notes,
    createdAtMicros,
    updatedAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Event &&
          other.id == this.id &&
          other.name == this.name &&
          other.venue == this.venue &&
          other.scheduledDate == this.scheduledDate &&
          other.startsAtMicros == this.startsAtMicros &&
          other.endsAtMicros == this.endsAtMicros &&
          other.status == this.status &&
          other.plannedExposure == this.plannedExposure &&
          other.closedAtMicros == this.closedAtMicros &&
          other.notes == this.notes &&
          other.createdAtMicros == this.createdAtMicros &&
          other.updatedAtMicros == this.updatedAtMicros);
}

class EventsCompanion extends UpdateCompanion<Event> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> venue;
  final Value<String> scheduledDate;
  final Value<int?> startsAtMicros;
  final Value<int?> endsAtMicros;
  final Value<String> status;
  final Value<int?> plannedExposure;
  final Value<int?> closedAtMicros;
  final Value<String?> notes;
  final Value<int> createdAtMicros;
  final Value<int> updatedAtMicros;
  final Value<int> rowid;
  const EventsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.venue = const Value.absent(),
    this.scheduledDate = const Value.absent(),
    this.startsAtMicros = const Value.absent(),
    this.endsAtMicros = const Value.absent(),
    this.status = const Value.absent(),
    this.plannedExposure = const Value.absent(),
    this.closedAtMicros = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.updatedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventsCompanion.insert({
    required String id,
    required String name,
    this.venue = const Value.absent(),
    required String scheduledDate,
    this.startsAtMicros = const Value.absent(),
    this.endsAtMicros = const Value.absent(),
    this.status = const Value.absent(),
    this.plannedExposure = const Value.absent(),
    this.closedAtMicros = const Value.absent(),
    this.notes = const Value.absent(),
    required int createdAtMicros,
    required int updatedAtMicros,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       scheduledDate = Value(scheduledDate),
       createdAtMicros = Value(createdAtMicros),
       updatedAtMicros = Value(updatedAtMicros);
  static Insertable<Event> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? venue,
    Expression<String>? scheduledDate,
    Expression<int>? startsAtMicros,
    Expression<int>? endsAtMicros,
    Expression<String>? status,
    Expression<int>? plannedExposure,
    Expression<int>? closedAtMicros,
    Expression<String>? notes,
    Expression<int>? createdAtMicros,
    Expression<int>? updatedAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (venue != null) 'venue': venue,
      if (scheduledDate != null) 'scheduled_date': scheduledDate,
      if (startsAtMicros != null) 'starts_at_micros': startsAtMicros,
      if (endsAtMicros != null) 'ends_at_micros': endsAtMicros,
      if (status != null) 'status': status,
      if (plannedExposure != null) 'planned_exposure': plannedExposure,
      if (closedAtMicros != null) 'closed_at_micros': closedAtMicros,
      if (notes != null) 'notes': notes,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (updatedAtMicros != null) 'updated_at_micros': updatedAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? venue,
    Value<String>? scheduledDate,
    Value<int?>? startsAtMicros,
    Value<int?>? endsAtMicros,
    Value<String>? status,
    Value<int?>? plannedExposure,
    Value<int?>? closedAtMicros,
    Value<String?>? notes,
    Value<int>? createdAtMicros,
    Value<int>? updatedAtMicros,
    Value<int>? rowid,
  }) {
    return EventsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      venue: venue ?? this.venue,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      startsAtMicros: startsAtMicros ?? this.startsAtMicros,
      endsAtMicros: endsAtMicros ?? this.endsAtMicros,
      status: status ?? this.status,
      plannedExposure: plannedExposure ?? this.plannedExposure,
      closedAtMicros: closedAtMicros ?? this.closedAtMicros,
      notes: notes ?? this.notes,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (venue.present) {
      map['venue'] = Variable<String>(venue.value);
    }
    if (scheduledDate.present) {
      map['scheduled_date'] = Variable<String>(scheduledDate.value);
    }
    if (startsAtMicros.present) {
      map['starts_at_micros'] = Variable<int>(startsAtMicros.value);
    }
    if (endsAtMicros.present) {
      map['ends_at_micros'] = Variable<int>(endsAtMicros.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (plannedExposure.present) {
      map['planned_exposure'] = Variable<int>(plannedExposure.value);
    }
    if (closedAtMicros.present) {
      map['closed_at_micros'] = Variable<int>(closedAtMicros.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (updatedAtMicros.present) {
      map['updated_at_micros'] = Variable<int>(updatedAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('venue: $venue, ')
          ..write('scheduledDate: $scheduledDate, ')
          ..write('startsAtMicros: $startsAtMicros, ')
          ..write('endsAtMicros: $endsAtMicros, ')
          ..write('status: $status, ')
          ..write('plannedExposure: $plannedExposure, ')
          ..write('closedAtMicros: $closedAtMicros, ')
          ..write('notes: $notes, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EventItemsTable extends EventItems
    with TableInfo<$EventItemsTable, EventItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES events (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    check: () => ComparableExpr(position).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [eventId, itemId, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'event_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<EventItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {eventId, itemId};
  @override
  EventItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventItem(
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $EventItemsTable createAlias(String alias) {
    return $EventItemsTable(attachedDatabase, alias);
  }
}

class EventItem extends DataClass implements Insertable<EventItem> {
  final String eventId;
  final String itemId;
  final int position;
  const EventItem({
    required this.eventId,
    required this.itemId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    map['item_id'] = Variable<String>(itemId);
    map['position'] = Variable<int>(position);
    return map;
  }

  EventItemsCompanion toCompanion(bool nullToAbsent) {
    return EventItemsCompanion(
      eventId: Value(eventId),
      itemId: Value(itemId),
      position: Value(position),
    );
  }

  factory EventItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventItem(
      eventId: serializer.fromJson<String>(json['eventId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventId': serializer.toJson<String>(eventId),
      'itemId': serializer.toJson<String>(itemId),
      'position': serializer.toJson<int>(position),
    };
  }

  EventItem copyWith({String? eventId, String? itemId, int? position}) =>
      EventItem(
        eventId: eventId ?? this.eventId,
        itemId: itemId ?? this.itemId,
        position: position ?? this.position,
      );
  EventItem copyWithCompanion(EventItemsCompanion data) {
    return EventItem(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventItem(')
          ..write('eventId: $eventId, ')
          ..write('itemId: $itemId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(eventId, itemId, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventItem &&
          other.eventId == this.eventId &&
          other.itemId == this.itemId &&
          other.position == this.position);
}

class EventItemsCompanion extends UpdateCompanion<EventItem> {
  final Value<String> eventId;
  final Value<String> itemId;
  final Value<int> position;
  final Value<int> rowid;
  const EventItemsCompanion({
    this.eventId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventItemsCompanion.insert({
    required String eventId,
    required String itemId,
    required int position,
    this.rowid = const Value.absent(),
  }) : eventId = Value(eventId),
       itemId = Value(itemId),
       position = Value(position);
  static Insertable<EventItem> custom({
    Expression<String>? eventId,
    Expression<String>? itemId,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (itemId != null) 'item_id': itemId,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventItemsCompanion copyWith({
    Value<String>? eventId,
    Value<String>? itemId,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return EventItemsCompanion(
      eventId: eventId ?? this.eventId,
      itemId: itemId ?? this.itemId,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventItemsCompanion(')
          ..write('eventId: $eventId, ')
          ..write('itemId: $itemId, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InventoryMovementsTable extends InventoryMovements
    with TableInfo<$InventoryMovementsTable, InventoryMovement> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InventoryMovementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 26,
      maxTextLength: 26,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    check: () =>
        kind.isIn(['receive', 'consume', 'waste', 'adjust', 'reversal']),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deltaMicrosMeta = const VerificationMeta(
    'deltaMicros',
  );
  @override
  late final GeneratedColumn<int> deltaMicros = GeneratedColumn<int>(
    'delta_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES events (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _reversesMovementIdMeta =
      const VerificationMeta('reversesMovementId');
  @override
  late final GeneratedColumn<String> reversesMovementId =
      GeneratedColumn<String>(
        'reverses_movement_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES inventory_movements (id) ON DELETE RESTRICT',
        ),
      );
  static const VerificationMeta _sourceCommandIdMeta = const VerificationMeta(
    'sourceCommandId',
  );
  @override
  late final GeneratedColumn<String> sourceCommandId = GeneratedColumn<String>(
    'source_command_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES commands (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _occurredAtMicrosMeta = const VerificationMeta(
    'occurredAtMicros',
  );
  @override
  late final GeneratedColumn<int> occurredAtMicros = GeneratedColumn<int>(
    'occurred_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordedAtMicrosMeta = const VerificationMeta(
    'recordedAtMicros',
  );
  @override
  late final GeneratedColumn<int> recordedAtMicros = GeneratedColumn<int>(
    'recorded_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    itemId,
    kind,
    deltaMicros,
    eventId,
    reversesMovementId,
    sourceCommandId,
    occurredAtMicros,
    recordedAtMicros,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inventory_movements';
  @override
  VerificationContext validateIntegrity(
    Insertable<InventoryMovement> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('delta_micros')) {
      context.handle(
        _deltaMicrosMeta,
        deltaMicros.isAcceptableOrUnknown(
          data['delta_micros']!,
          _deltaMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deltaMicrosMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    }
    if (data.containsKey('reverses_movement_id')) {
      context.handle(
        _reversesMovementIdMeta,
        reversesMovementId.isAcceptableOrUnknown(
          data['reverses_movement_id']!,
          _reversesMovementIdMeta,
        ),
      );
    }
    if (data.containsKey('source_command_id')) {
      context.handle(
        _sourceCommandIdMeta,
        sourceCommandId.isAcceptableOrUnknown(
          data['source_command_id']!,
          _sourceCommandIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceCommandIdMeta);
    }
    if (data.containsKey('occurred_at_micros')) {
      context.handle(
        _occurredAtMicrosMeta,
        occurredAtMicros.isAcceptableOrUnknown(
          data['occurred_at_micros']!,
          _occurredAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMicrosMeta);
    }
    if (data.containsKey('recorded_at_micros')) {
      context.handle(
        _recordedAtMicrosMeta,
        recordedAtMicros.isAcceptableOrUnknown(
          data['recorded_at_micros']!,
          _recordedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMicrosMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InventoryMovement map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InventoryMovement(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      deltaMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}delta_micros'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      ),
      reversesMovementId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reverses_movement_id'],
      ),
      sourceCommandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_command_id'],
      )!,
      occurredAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}occurred_at_micros'],
      )!,
      recordedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recorded_at_micros'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
    );
  }

  @override
  $InventoryMovementsTable createAlias(String alias) {
    return $InventoryMovementsTable(attachedDatabase, alias);
  }
}

class InventoryMovement extends DataClass
    implements Insertable<InventoryMovement> {
  final String id;
  final String itemId;
  final String kind;
  final int deltaMicros;
  final String? eventId;
  final String? reversesMovementId;
  final String sourceCommandId;
  final int occurredAtMicros;
  final int recordedAtMicros;
  final String note;
  const InventoryMovement({
    required this.id,
    required this.itemId,
    required this.kind,
    required this.deltaMicros,
    this.eventId,
    this.reversesMovementId,
    required this.sourceCommandId,
    required this.occurredAtMicros,
    required this.recordedAtMicros,
    required this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['item_id'] = Variable<String>(itemId);
    map['kind'] = Variable<String>(kind);
    map['delta_micros'] = Variable<int>(deltaMicros);
    if (!nullToAbsent || eventId != null) {
      map['event_id'] = Variable<String>(eventId);
    }
    if (!nullToAbsent || reversesMovementId != null) {
      map['reverses_movement_id'] = Variable<String>(reversesMovementId);
    }
    map['source_command_id'] = Variable<String>(sourceCommandId);
    map['occurred_at_micros'] = Variable<int>(occurredAtMicros);
    map['recorded_at_micros'] = Variable<int>(recordedAtMicros);
    map['note'] = Variable<String>(note);
    return map;
  }

  InventoryMovementsCompanion toCompanion(bool nullToAbsent) {
    return InventoryMovementsCompanion(
      id: Value(id),
      itemId: Value(itemId),
      kind: Value(kind),
      deltaMicros: Value(deltaMicros),
      eventId: eventId == null && nullToAbsent
          ? const Value.absent()
          : Value(eventId),
      reversesMovementId: reversesMovementId == null && nullToAbsent
          ? const Value.absent()
          : Value(reversesMovementId),
      sourceCommandId: Value(sourceCommandId),
      occurredAtMicros: Value(occurredAtMicros),
      recordedAtMicros: Value(recordedAtMicros),
      note: Value(note),
    );
  }

  factory InventoryMovement.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InventoryMovement(
      id: serializer.fromJson<String>(json['id']),
      itemId: serializer.fromJson<String>(json['itemId']),
      kind: serializer.fromJson<String>(json['kind']),
      deltaMicros: serializer.fromJson<int>(json['deltaMicros']),
      eventId: serializer.fromJson<String?>(json['eventId']),
      reversesMovementId: serializer.fromJson<String?>(
        json['reversesMovementId'],
      ),
      sourceCommandId: serializer.fromJson<String>(json['sourceCommandId']),
      occurredAtMicros: serializer.fromJson<int>(json['occurredAtMicros']),
      recordedAtMicros: serializer.fromJson<int>(json['recordedAtMicros']),
      note: serializer.fromJson<String>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'itemId': serializer.toJson<String>(itemId),
      'kind': serializer.toJson<String>(kind),
      'deltaMicros': serializer.toJson<int>(deltaMicros),
      'eventId': serializer.toJson<String?>(eventId),
      'reversesMovementId': serializer.toJson<String?>(reversesMovementId),
      'sourceCommandId': serializer.toJson<String>(sourceCommandId),
      'occurredAtMicros': serializer.toJson<int>(occurredAtMicros),
      'recordedAtMicros': serializer.toJson<int>(recordedAtMicros),
      'note': serializer.toJson<String>(note),
    };
  }

  InventoryMovement copyWith({
    String? id,
    String? itemId,
    String? kind,
    int? deltaMicros,
    Value<String?> eventId = const Value.absent(),
    Value<String?> reversesMovementId = const Value.absent(),
    String? sourceCommandId,
    int? occurredAtMicros,
    int? recordedAtMicros,
    String? note,
  }) => InventoryMovement(
    id: id ?? this.id,
    itemId: itemId ?? this.itemId,
    kind: kind ?? this.kind,
    deltaMicros: deltaMicros ?? this.deltaMicros,
    eventId: eventId.present ? eventId.value : this.eventId,
    reversesMovementId: reversesMovementId.present
        ? reversesMovementId.value
        : this.reversesMovementId,
    sourceCommandId: sourceCommandId ?? this.sourceCommandId,
    occurredAtMicros: occurredAtMicros ?? this.occurredAtMicros,
    recordedAtMicros: recordedAtMicros ?? this.recordedAtMicros,
    note: note ?? this.note,
  );
  InventoryMovement copyWithCompanion(InventoryMovementsCompanion data) {
    return InventoryMovement(
      id: data.id.present ? data.id.value : this.id,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      kind: data.kind.present ? data.kind.value : this.kind,
      deltaMicros: data.deltaMicros.present
          ? data.deltaMicros.value
          : this.deltaMicros,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      reversesMovementId: data.reversesMovementId.present
          ? data.reversesMovementId.value
          : this.reversesMovementId,
      sourceCommandId: data.sourceCommandId.present
          ? data.sourceCommandId.value
          : this.sourceCommandId,
      occurredAtMicros: data.occurredAtMicros.present
          ? data.occurredAtMicros.value
          : this.occurredAtMicros,
      recordedAtMicros: data.recordedAtMicros.present
          ? data.recordedAtMicros.value
          : this.recordedAtMicros,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InventoryMovement(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('kind: $kind, ')
          ..write('deltaMicros: $deltaMicros, ')
          ..write('eventId: $eventId, ')
          ..write('reversesMovementId: $reversesMovementId, ')
          ..write('sourceCommandId: $sourceCommandId, ')
          ..write('occurredAtMicros: $occurredAtMicros, ')
          ..write('recordedAtMicros: $recordedAtMicros, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    itemId,
    kind,
    deltaMicros,
    eventId,
    reversesMovementId,
    sourceCommandId,
    occurredAtMicros,
    recordedAtMicros,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InventoryMovement &&
          other.id == this.id &&
          other.itemId == this.itemId &&
          other.kind == this.kind &&
          other.deltaMicros == this.deltaMicros &&
          other.eventId == this.eventId &&
          other.reversesMovementId == this.reversesMovementId &&
          other.sourceCommandId == this.sourceCommandId &&
          other.occurredAtMicros == this.occurredAtMicros &&
          other.recordedAtMicros == this.recordedAtMicros &&
          other.note == this.note);
}

class InventoryMovementsCompanion extends UpdateCompanion<InventoryMovement> {
  final Value<String> id;
  final Value<String> itemId;
  final Value<String> kind;
  final Value<int> deltaMicros;
  final Value<String?> eventId;
  final Value<String?> reversesMovementId;
  final Value<String> sourceCommandId;
  final Value<int> occurredAtMicros;
  final Value<int> recordedAtMicros;
  final Value<String> note;
  final Value<int> rowid;
  const InventoryMovementsCompanion({
    this.id = const Value.absent(),
    this.itemId = const Value.absent(),
    this.kind = const Value.absent(),
    this.deltaMicros = const Value.absent(),
    this.eventId = const Value.absent(),
    this.reversesMovementId = const Value.absent(),
    this.sourceCommandId = const Value.absent(),
    this.occurredAtMicros = const Value.absent(),
    this.recordedAtMicros = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InventoryMovementsCompanion.insert({
    required String id,
    required String itemId,
    required String kind,
    required int deltaMicros,
    this.eventId = const Value.absent(),
    this.reversesMovementId = const Value.absent(),
    required String sourceCommandId,
    required int occurredAtMicros,
    required int recordedAtMicros,
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       itemId = Value(itemId),
       kind = Value(kind),
       deltaMicros = Value(deltaMicros),
       sourceCommandId = Value(sourceCommandId),
       occurredAtMicros = Value(occurredAtMicros),
       recordedAtMicros = Value(recordedAtMicros);
  static Insertable<InventoryMovement> custom({
    Expression<String>? id,
    Expression<String>? itemId,
    Expression<String>? kind,
    Expression<int>? deltaMicros,
    Expression<String>? eventId,
    Expression<String>? reversesMovementId,
    Expression<String>? sourceCommandId,
    Expression<int>? occurredAtMicros,
    Expression<int>? recordedAtMicros,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      if (kind != null) 'kind': kind,
      if (deltaMicros != null) 'delta_micros': deltaMicros,
      if (eventId != null) 'event_id': eventId,
      if (reversesMovementId != null)
        'reverses_movement_id': reversesMovementId,
      if (sourceCommandId != null) 'source_command_id': sourceCommandId,
      if (occurredAtMicros != null) 'occurred_at_micros': occurredAtMicros,
      if (recordedAtMicros != null) 'recorded_at_micros': recordedAtMicros,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InventoryMovementsCompanion copyWith({
    Value<String>? id,
    Value<String>? itemId,
    Value<String>? kind,
    Value<int>? deltaMicros,
    Value<String?>? eventId,
    Value<String?>? reversesMovementId,
    Value<String>? sourceCommandId,
    Value<int>? occurredAtMicros,
    Value<int>? recordedAtMicros,
    Value<String>? note,
    Value<int>? rowid,
  }) {
    return InventoryMovementsCompanion(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      kind: kind ?? this.kind,
      deltaMicros: deltaMicros ?? this.deltaMicros,
      eventId: eventId ?? this.eventId,
      reversesMovementId: reversesMovementId ?? this.reversesMovementId,
      sourceCommandId: sourceCommandId ?? this.sourceCommandId,
      occurredAtMicros: occurredAtMicros ?? this.occurredAtMicros,
      recordedAtMicros: recordedAtMicros ?? this.recordedAtMicros,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (deltaMicros.present) {
      map['delta_micros'] = Variable<int>(deltaMicros.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (reversesMovementId.present) {
      map['reverses_movement_id'] = Variable<String>(reversesMovementId.value);
    }
    if (sourceCommandId.present) {
      map['source_command_id'] = Variable<String>(sourceCommandId.value);
    }
    if (occurredAtMicros.present) {
      map['occurred_at_micros'] = Variable<int>(occurredAtMicros.value);
    }
    if (recordedAtMicros.present) {
      map['recorded_at_micros'] = Variable<int>(recordedAtMicros.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InventoryMovementsCompanion(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('kind: $kind, ')
          ..write('deltaMicros: $deltaMicros, ')
          ..write('eventId: $eventId, ')
          ..write('reversesMovementId: $reversesMovementId, ')
          ..write('sourceCommandId: $sourceCommandId, ')
          ..write('occurredAtMicros: $occurredAtMicros, ')
          ..write('recordedAtMicros: $recordedAtMicros, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EventCloseoutsTable extends EventCloseouts
    with TableInfo<$EventCloseoutsTable, EventCloseout> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventCloseoutsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 26,
      maxTextLength: 26,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES events (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    check: () => ComparableExpr(revision).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _supersedesCloseoutIdMeta =
      const VerificationMeta('supersedesCloseoutId');
  @override
  late final GeneratedColumn<String> supersedesCloseoutId =
      GeneratedColumn<String>(
        'supersedes_closeout_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES event_closeouts (id) ON DELETE RESTRICT',
        ),
      );
  static const VerificationMeta _confirmedExposureMeta = const VerificationMeta(
    'confirmedExposure',
  );
  @override
  late final GeneratedColumn<int> confirmedExposure = GeneratedColumn<int>(
    'confirmed_exposure',
    aliasedName,
    false,
    check: () => ComparableExpr(confirmedExposure).isBetweenValues(1, 1000000),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sourceCommandIdMeta = const VerificationMeta(
    'sourceCommandId',
  );
  @override
  late final GeneratedColumn<String> sourceCommandId = GeneratedColumn<String>(
    'source_command_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES commands (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _confirmedAtMicrosMeta = const VerificationMeta(
    'confirmedAtMicros',
  );
  @override
  late final GeneratedColumn<int> confirmedAtMicros = GeneratedColumn<int>(
    'confirmed_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    eventId,
    revision,
    supersedesCloseoutId,
    confirmedExposure,
    note,
    sourceCommandId,
    confirmedAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'event_closeouts';
  @override
  VerificationContext validateIntegrity(
    Insertable<EventCloseout> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('supersedes_closeout_id')) {
      context.handle(
        _supersedesCloseoutIdMeta,
        supersedesCloseoutId.isAcceptableOrUnknown(
          data['supersedes_closeout_id']!,
          _supersedesCloseoutIdMeta,
        ),
      );
    }
    if (data.containsKey('confirmed_exposure')) {
      context.handle(
        _confirmedExposureMeta,
        confirmedExposure.isAcceptableOrUnknown(
          data['confirmed_exposure']!,
          _confirmedExposureMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_confirmedExposureMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('source_command_id')) {
      context.handle(
        _sourceCommandIdMeta,
        sourceCommandId.isAcceptableOrUnknown(
          data['source_command_id']!,
          _sourceCommandIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceCommandIdMeta);
    }
    if (data.containsKey('confirmed_at_micros')) {
      context.handle(
        _confirmedAtMicrosMeta,
        confirmedAtMicros.isAcceptableOrUnknown(
          data['confirmed_at_micros']!,
          _confirmedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_confirmedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EventCloseout map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventCloseout(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      supersedesCloseoutId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}supersedes_closeout_id'],
      ),
      confirmedExposure: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}confirmed_exposure'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      sourceCommandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_command_id'],
      )!,
      confirmedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}confirmed_at_micros'],
      )!,
    );
  }

  @override
  $EventCloseoutsTable createAlias(String alias) {
    return $EventCloseoutsTable(attachedDatabase, alias);
  }
}

class EventCloseout extends DataClass implements Insertable<EventCloseout> {
  final String id;
  final String eventId;
  final int revision;
  final String? supersedesCloseoutId;
  final int confirmedExposure;
  final String note;
  final String sourceCommandId;
  final int confirmedAtMicros;
  const EventCloseout({
    required this.id,
    required this.eventId,
    required this.revision,
    this.supersedesCloseoutId,
    required this.confirmedExposure,
    required this.note,
    required this.sourceCommandId,
    required this.confirmedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['event_id'] = Variable<String>(eventId);
    map['revision'] = Variable<int>(revision);
    if (!nullToAbsent || supersedesCloseoutId != null) {
      map['supersedes_closeout_id'] = Variable<String>(supersedesCloseoutId);
    }
    map['confirmed_exposure'] = Variable<int>(confirmedExposure);
    map['note'] = Variable<String>(note);
    map['source_command_id'] = Variable<String>(sourceCommandId);
    map['confirmed_at_micros'] = Variable<int>(confirmedAtMicros);
    return map;
  }

  EventCloseoutsCompanion toCompanion(bool nullToAbsent) {
    return EventCloseoutsCompanion(
      id: Value(id),
      eventId: Value(eventId),
      revision: Value(revision),
      supersedesCloseoutId: supersedesCloseoutId == null && nullToAbsent
          ? const Value.absent()
          : Value(supersedesCloseoutId),
      confirmedExposure: Value(confirmedExposure),
      note: Value(note),
      sourceCommandId: Value(sourceCommandId),
      confirmedAtMicros: Value(confirmedAtMicros),
    );
  }

  factory EventCloseout.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventCloseout(
      id: serializer.fromJson<String>(json['id']),
      eventId: serializer.fromJson<String>(json['eventId']),
      revision: serializer.fromJson<int>(json['revision']),
      supersedesCloseoutId: serializer.fromJson<String?>(
        json['supersedesCloseoutId'],
      ),
      confirmedExposure: serializer.fromJson<int>(json['confirmedExposure']),
      note: serializer.fromJson<String>(json['note']),
      sourceCommandId: serializer.fromJson<String>(json['sourceCommandId']),
      confirmedAtMicros: serializer.fromJson<int>(json['confirmedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'eventId': serializer.toJson<String>(eventId),
      'revision': serializer.toJson<int>(revision),
      'supersedesCloseoutId': serializer.toJson<String?>(supersedesCloseoutId),
      'confirmedExposure': serializer.toJson<int>(confirmedExposure),
      'note': serializer.toJson<String>(note),
      'sourceCommandId': serializer.toJson<String>(sourceCommandId),
      'confirmedAtMicros': serializer.toJson<int>(confirmedAtMicros),
    };
  }

  EventCloseout copyWith({
    String? id,
    String? eventId,
    int? revision,
    Value<String?> supersedesCloseoutId = const Value.absent(),
    int? confirmedExposure,
    String? note,
    String? sourceCommandId,
    int? confirmedAtMicros,
  }) => EventCloseout(
    id: id ?? this.id,
    eventId: eventId ?? this.eventId,
    revision: revision ?? this.revision,
    supersedesCloseoutId: supersedesCloseoutId.present
        ? supersedesCloseoutId.value
        : this.supersedesCloseoutId,
    confirmedExposure: confirmedExposure ?? this.confirmedExposure,
    note: note ?? this.note,
    sourceCommandId: sourceCommandId ?? this.sourceCommandId,
    confirmedAtMicros: confirmedAtMicros ?? this.confirmedAtMicros,
  );
  EventCloseout copyWithCompanion(EventCloseoutsCompanion data) {
    return EventCloseout(
      id: data.id.present ? data.id.value : this.id,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      revision: data.revision.present ? data.revision.value : this.revision,
      supersedesCloseoutId: data.supersedesCloseoutId.present
          ? data.supersedesCloseoutId.value
          : this.supersedesCloseoutId,
      confirmedExposure: data.confirmedExposure.present
          ? data.confirmedExposure.value
          : this.confirmedExposure,
      note: data.note.present ? data.note.value : this.note,
      sourceCommandId: data.sourceCommandId.present
          ? data.sourceCommandId.value
          : this.sourceCommandId,
      confirmedAtMicros: data.confirmedAtMicros.present
          ? data.confirmedAtMicros.value
          : this.confirmedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventCloseout(')
          ..write('id: $id, ')
          ..write('eventId: $eventId, ')
          ..write('revision: $revision, ')
          ..write('supersedesCloseoutId: $supersedesCloseoutId, ')
          ..write('confirmedExposure: $confirmedExposure, ')
          ..write('note: $note, ')
          ..write('sourceCommandId: $sourceCommandId, ')
          ..write('confirmedAtMicros: $confirmedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    eventId,
    revision,
    supersedesCloseoutId,
    confirmedExposure,
    note,
    sourceCommandId,
    confirmedAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventCloseout &&
          other.id == this.id &&
          other.eventId == this.eventId &&
          other.revision == this.revision &&
          other.supersedesCloseoutId == this.supersedesCloseoutId &&
          other.confirmedExposure == this.confirmedExposure &&
          other.note == this.note &&
          other.sourceCommandId == this.sourceCommandId &&
          other.confirmedAtMicros == this.confirmedAtMicros);
}

class EventCloseoutsCompanion extends UpdateCompanion<EventCloseout> {
  final Value<String> id;
  final Value<String> eventId;
  final Value<int> revision;
  final Value<String?> supersedesCloseoutId;
  final Value<int> confirmedExposure;
  final Value<String> note;
  final Value<String> sourceCommandId;
  final Value<int> confirmedAtMicros;
  final Value<int> rowid;
  const EventCloseoutsCompanion({
    this.id = const Value.absent(),
    this.eventId = const Value.absent(),
    this.revision = const Value.absent(),
    this.supersedesCloseoutId = const Value.absent(),
    this.confirmedExposure = const Value.absent(),
    this.note = const Value.absent(),
    this.sourceCommandId = const Value.absent(),
    this.confirmedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventCloseoutsCompanion.insert({
    required String id,
    required String eventId,
    required int revision,
    this.supersedesCloseoutId = const Value.absent(),
    required int confirmedExposure,
    this.note = const Value.absent(),
    required String sourceCommandId,
    required int confirmedAtMicros,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       eventId = Value(eventId),
       revision = Value(revision),
       confirmedExposure = Value(confirmedExposure),
       sourceCommandId = Value(sourceCommandId),
       confirmedAtMicros = Value(confirmedAtMicros);
  static Insertable<EventCloseout> custom({
    Expression<String>? id,
    Expression<String>? eventId,
    Expression<int>? revision,
    Expression<String>? supersedesCloseoutId,
    Expression<int>? confirmedExposure,
    Expression<String>? note,
    Expression<String>? sourceCommandId,
    Expression<int>? confirmedAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (eventId != null) 'event_id': eventId,
      if (revision != null) 'revision': revision,
      if (supersedesCloseoutId != null)
        'supersedes_closeout_id': supersedesCloseoutId,
      if (confirmedExposure != null) 'confirmed_exposure': confirmedExposure,
      if (note != null) 'note': note,
      if (sourceCommandId != null) 'source_command_id': sourceCommandId,
      if (confirmedAtMicros != null) 'confirmed_at_micros': confirmedAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventCloseoutsCompanion copyWith({
    Value<String>? id,
    Value<String>? eventId,
    Value<int>? revision,
    Value<String?>? supersedesCloseoutId,
    Value<int>? confirmedExposure,
    Value<String>? note,
    Value<String>? sourceCommandId,
    Value<int>? confirmedAtMicros,
    Value<int>? rowid,
  }) {
    return EventCloseoutsCompanion(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      revision: revision ?? this.revision,
      supersedesCloseoutId: supersedesCloseoutId ?? this.supersedesCloseoutId,
      confirmedExposure: confirmedExposure ?? this.confirmedExposure,
      note: note ?? this.note,
      sourceCommandId: sourceCommandId ?? this.sourceCommandId,
      confirmedAtMicros: confirmedAtMicros ?? this.confirmedAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (supersedesCloseoutId.present) {
      map['supersedes_closeout_id'] = Variable<String>(
        supersedesCloseoutId.value,
      );
    }
    if (confirmedExposure.present) {
      map['confirmed_exposure'] = Variable<int>(confirmedExposure.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (sourceCommandId.present) {
      map['source_command_id'] = Variable<String>(sourceCommandId.value);
    }
    if (confirmedAtMicros.present) {
      map['confirmed_at_micros'] = Variable<int>(confirmedAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventCloseoutsCompanion(')
          ..write('id: $id, ')
          ..write('eventId: $eventId, ')
          ..write('revision: $revision, ')
          ..write('supersedesCloseoutId: $supersedesCloseoutId, ')
          ..write('confirmedExposure: $confirmedExposure, ')
          ..write('note: $note, ')
          ..write('sourceCommandId: $sourceCommandId, ')
          ..write('confirmedAtMicros: $confirmedAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CloseoutLinesTable extends CloseoutLines
    with TableInfo<$CloseoutLinesTable, CloseoutLine> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CloseoutLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _closeoutIdMeta = const VerificationMeta(
    'closeoutId',
  );
  @override
  late final GeneratedColumn<String> closeoutId = GeneratedColumn<String>(
    'closeout_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES event_closeouts (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _loadedMicrosMeta = const VerificationMeta(
    'loadedMicros',
  );
  @override
  late final GeneratedColumn<int> loadedMicros = GeneratedColumn<int>(
    'loaded_micros',
    aliasedName,
    true,
    check: () => ComparableExpr(loadedMicros).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _returnedMicrosMeta = const VerificationMeta(
    'returnedMicros',
  );
  @override
  late final GeneratedColumn<int> returnedMicros = GeneratedColumn<int>(
    'returned_micros',
    aliasedName,
    true,
    check: () => ComparableExpr(returnedMicros).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _wasteMicrosMeta = const VerificationMeta(
    'wasteMicros',
  );
  @override
  late final GeneratedColumn<int> wasteMicros = GeneratedColumn<int>(
    'waste_micros',
    aliasedName,
    true,
    check: () => ComparableExpr(wasteMicros).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _depletionMicrosMeta = const VerificationMeta(
    'depletionMicros',
  );
  @override
  late final GeneratedColumn<int> depletionMicros = GeneratedColumn<int>(
    'depletion_micros',
    aliasedName,
    false,
    check: () =>
        ComparableExpr(depletionMicros).isBetweenValues(0, 1000000000000),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stockoutMeta = const VerificationMeta(
    'stockout',
  );
  @override
  late final GeneratedColumn<bool> stockout = GeneratedColumn<bool>(
    'stockout',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("stockout" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _approximateMeta = const VerificationMeta(
    'approximate',
  );
  @override
  late final GeneratedColumn<bool> approximate = GeneratedColumn<bool>(
    'approximate',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("approximate" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _consumptionMovementIdMeta =
      const VerificationMeta('consumptionMovementId');
  @override
  late final GeneratedColumn<String> consumptionMovementId =
      GeneratedColumn<String>(
        'consumption_movement_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES inventory_movements (id) ON DELETE RESTRICT',
        ),
      );
  static const VerificationMeta _wasteMovementIdMeta = const VerificationMeta(
    'wasteMovementId',
  );
  @override
  late final GeneratedColumn<String> wasteMovementId = GeneratedColumn<String>(
    'waste_movement_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES inventory_movements (id) ON DELETE RESTRICT',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    closeoutId,
    itemId,
    loadedMicros,
    returnedMicros,
    wasteMicros,
    depletionMicros,
    stockout,
    approximate,
    consumptionMovementId,
    wasteMovementId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'closeout_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<CloseoutLine> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('closeout_id')) {
      context.handle(
        _closeoutIdMeta,
        closeoutId.isAcceptableOrUnknown(data['closeout_id']!, _closeoutIdMeta),
      );
    } else if (isInserting) {
      context.missing(_closeoutIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('loaded_micros')) {
      context.handle(
        _loadedMicrosMeta,
        loadedMicros.isAcceptableOrUnknown(
          data['loaded_micros']!,
          _loadedMicrosMeta,
        ),
      );
    }
    if (data.containsKey('returned_micros')) {
      context.handle(
        _returnedMicrosMeta,
        returnedMicros.isAcceptableOrUnknown(
          data['returned_micros']!,
          _returnedMicrosMeta,
        ),
      );
    }
    if (data.containsKey('waste_micros')) {
      context.handle(
        _wasteMicrosMeta,
        wasteMicros.isAcceptableOrUnknown(
          data['waste_micros']!,
          _wasteMicrosMeta,
        ),
      );
    }
    if (data.containsKey('depletion_micros')) {
      context.handle(
        _depletionMicrosMeta,
        depletionMicros.isAcceptableOrUnknown(
          data['depletion_micros']!,
          _depletionMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_depletionMicrosMeta);
    }
    if (data.containsKey('stockout')) {
      context.handle(
        _stockoutMeta,
        stockout.isAcceptableOrUnknown(data['stockout']!, _stockoutMeta),
      );
    }
    if (data.containsKey('approximate')) {
      context.handle(
        _approximateMeta,
        approximate.isAcceptableOrUnknown(
          data['approximate']!,
          _approximateMeta,
        ),
      );
    }
    if (data.containsKey('consumption_movement_id')) {
      context.handle(
        _consumptionMovementIdMeta,
        consumptionMovementId.isAcceptableOrUnknown(
          data['consumption_movement_id']!,
          _consumptionMovementIdMeta,
        ),
      );
    }
    if (data.containsKey('waste_movement_id')) {
      context.handle(
        _wasteMovementIdMeta,
        wasteMovementId.isAcceptableOrUnknown(
          data['waste_movement_id']!,
          _wasteMovementIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {closeoutId, itemId};
  @override
  CloseoutLine map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CloseoutLine(
      closeoutId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}closeout_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      loadedMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}loaded_micros'],
      ),
      returnedMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}returned_micros'],
      ),
      wasteMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}waste_micros'],
      ),
      depletionMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}depletion_micros'],
      )!,
      stockout: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}stockout'],
      )!,
      approximate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}approximate'],
      )!,
      consumptionMovementId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}consumption_movement_id'],
      ),
      wasteMovementId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}waste_movement_id'],
      ),
    );
  }

  @override
  $CloseoutLinesTable createAlias(String alias) {
    return $CloseoutLinesTable(attachedDatabase, alias);
  }
}

class CloseoutLine extends DataClass implements Insertable<CloseoutLine> {
  final String closeoutId;
  final String itemId;
  final int? loadedMicros;
  final int? returnedMicros;
  final int? wasteMicros;

  /// The confirmed demand label. Envelope cap 1e12 micros (frozen engine).
  final int depletionMicros;
  final bool stockout;
  final bool approximate;

  /// Ledger rows written when this revision was applied (evidence links).
  final String? consumptionMovementId;
  final String? wasteMovementId;
  const CloseoutLine({
    required this.closeoutId,
    required this.itemId,
    this.loadedMicros,
    this.returnedMicros,
    this.wasteMicros,
    required this.depletionMicros,
    required this.stockout,
    required this.approximate,
    this.consumptionMovementId,
    this.wasteMovementId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['closeout_id'] = Variable<String>(closeoutId);
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || loadedMicros != null) {
      map['loaded_micros'] = Variable<int>(loadedMicros);
    }
    if (!nullToAbsent || returnedMicros != null) {
      map['returned_micros'] = Variable<int>(returnedMicros);
    }
    if (!nullToAbsent || wasteMicros != null) {
      map['waste_micros'] = Variable<int>(wasteMicros);
    }
    map['depletion_micros'] = Variable<int>(depletionMicros);
    map['stockout'] = Variable<bool>(stockout);
    map['approximate'] = Variable<bool>(approximate);
    if (!nullToAbsent || consumptionMovementId != null) {
      map['consumption_movement_id'] = Variable<String>(consumptionMovementId);
    }
    if (!nullToAbsent || wasteMovementId != null) {
      map['waste_movement_id'] = Variable<String>(wasteMovementId);
    }
    return map;
  }

  CloseoutLinesCompanion toCompanion(bool nullToAbsent) {
    return CloseoutLinesCompanion(
      closeoutId: Value(closeoutId),
      itemId: Value(itemId),
      loadedMicros: loadedMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(loadedMicros),
      returnedMicros: returnedMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(returnedMicros),
      wasteMicros: wasteMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(wasteMicros),
      depletionMicros: Value(depletionMicros),
      stockout: Value(stockout),
      approximate: Value(approximate),
      consumptionMovementId: consumptionMovementId == null && nullToAbsent
          ? const Value.absent()
          : Value(consumptionMovementId),
      wasteMovementId: wasteMovementId == null && nullToAbsent
          ? const Value.absent()
          : Value(wasteMovementId),
    );
  }

  factory CloseoutLine.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CloseoutLine(
      closeoutId: serializer.fromJson<String>(json['closeoutId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      loadedMicros: serializer.fromJson<int?>(json['loadedMicros']),
      returnedMicros: serializer.fromJson<int?>(json['returnedMicros']),
      wasteMicros: serializer.fromJson<int?>(json['wasteMicros']),
      depletionMicros: serializer.fromJson<int>(json['depletionMicros']),
      stockout: serializer.fromJson<bool>(json['stockout']),
      approximate: serializer.fromJson<bool>(json['approximate']),
      consumptionMovementId: serializer.fromJson<String?>(
        json['consumptionMovementId'],
      ),
      wasteMovementId: serializer.fromJson<String?>(json['wasteMovementId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'closeoutId': serializer.toJson<String>(closeoutId),
      'itemId': serializer.toJson<String>(itemId),
      'loadedMicros': serializer.toJson<int?>(loadedMicros),
      'returnedMicros': serializer.toJson<int?>(returnedMicros),
      'wasteMicros': serializer.toJson<int?>(wasteMicros),
      'depletionMicros': serializer.toJson<int>(depletionMicros),
      'stockout': serializer.toJson<bool>(stockout),
      'approximate': serializer.toJson<bool>(approximate),
      'consumptionMovementId': serializer.toJson<String?>(
        consumptionMovementId,
      ),
      'wasteMovementId': serializer.toJson<String?>(wasteMovementId),
    };
  }

  CloseoutLine copyWith({
    String? closeoutId,
    String? itemId,
    Value<int?> loadedMicros = const Value.absent(),
    Value<int?> returnedMicros = const Value.absent(),
    Value<int?> wasteMicros = const Value.absent(),
    int? depletionMicros,
    bool? stockout,
    bool? approximate,
    Value<String?> consumptionMovementId = const Value.absent(),
    Value<String?> wasteMovementId = const Value.absent(),
  }) => CloseoutLine(
    closeoutId: closeoutId ?? this.closeoutId,
    itemId: itemId ?? this.itemId,
    loadedMicros: loadedMicros.present ? loadedMicros.value : this.loadedMicros,
    returnedMicros: returnedMicros.present
        ? returnedMicros.value
        : this.returnedMicros,
    wasteMicros: wasteMicros.present ? wasteMicros.value : this.wasteMicros,
    depletionMicros: depletionMicros ?? this.depletionMicros,
    stockout: stockout ?? this.stockout,
    approximate: approximate ?? this.approximate,
    consumptionMovementId: consumptionMovementId.present
        ? consumptionMovementId.value
        : this.consumptionMovementId,
    wasteMovementId: wasteMovementId.present
        ? wasteMovementId.value
        : this.wasteMovementId,
  );
  CloseoutLine copyWithCompanion(CloseoutLinesCompanion data) {
    return CloseoutLine(
      closeoutId: data.closeoutId.present
          ? data.closeoutId.value
          : this.closeoutId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      loadedMicros: data.loadedMicros.present
          ? data.loadedMicros.value
          : this.loadedMicros,
      returnedMicros: data.returnedMicros.present
          ? data.returnedMicros.value
          : this.returnedMicros,
      wasteMicros: data.wasteMicros.present
          ? data.wasteMicros.value
          : this.wasteMicros,
      depletionMicros: data.depletionMicros.present
          ? data.depletionMicros.value
          : this.depletionMicros,
      stockout: data.stockout.present ? data.stockout.value : this.stockout,
      approximate: data.approximate.present
          ? data.approximate.value
          : this.approximate,
      consumptionMovementId: data.consumptionMovementId.present
          ? data.consumptionMovementId.value
          : this.consumptionMovementId,
      wasteMovementId: data.wasteMovementId.present
          ? data.wasteMovementId.value
          : this.wasteMovementId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CloseoutLine(')
          ..write('closeoutId: $closeoutId, ')
          ..write('itemId: $itemId, ')
          ..write('loadedMicros: $loadedMicros, ')
          ..write('returnedMicros: $returnedMicros, ')
          ..write('wasteMicros: $wasteMicros, ')
          ..write('depletionMicros: $depletionMicros, ')
          ..write('stockout: $stockout, ')
          ..write('approximate: $approximate, ')
          ..write('consumptionMovementId: $consumptionMovementId, ')
          ..write('wasteMovementId: $wasteMovementId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    closeoutId,
    itemId,
    loadedMicros,
    returnedMicros,
    wasteMicros,
    depletionMicros,
    stockout,
    approximate,
    consumptionMovementId,
    wasteMovementId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CloseoutLine &&
          other.closeoutId == this.closeoutId &&
          other.itemId == this.itemId &&
          other.loadedMicros == this.loadedMicros &&
          other.returnedMicros == this.returnedMicros &&
          other.wasteMicros == this.wasteMicros &&
          other.depletionMicros == this.depletionMicros &&
          other.stockout == this.stockout &&
          other.approximate == this.approximate &&
          other.consumptionMovementId == this.consumptionMovementId &&
          other.wasteMovementId == this.wasteMovementId);
}

class CloseoutLinesCompanion extends UpdateCompanion<CloseoutLine> {
  final Value<String> closeoutId;
  final Value<String> itemId;
  final Value<int?> loadedMicros;
  final Value<int?> returnedMicros;
  final Value<int?> wasteMicros;
  final Value<int> depletionMicros;
  final Value<bool> stockout;
  final Value<bool> approximate;
  final Value<String?> consumptionMovementId;
  final Value<String?> wasteMovementId;
  final Value<int> rowid;
  const CloseoutLinesCompanion({
    this.closeoutId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.loadedMicros = const Value.absent(),
    this.returnedMicros = const Value.absent(),
    this.wasteMicros = const Value.absent(),
    this.depletionMicros = const Value.absent(),
    this.stockout = const Value.absent(),
    this.approximate = const Value.absent(),
    this.consumptionMovementId = const Value.absent(),
    this.wasteMovementId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CloseoutLinesCompanion.insert({
    required String closeoutId,
    required String itemId,
    this.loadedMicros = const Value.absent(),
    this.returnedMicros = const Value.absent(),
    this.wasteMicros = const Value.absent(),
    required int depletionMicros,
    this.stockout = const Value.absent(),
    this.approximate = const Value.absent(),
    this.consumptionMovementId = const Value.absent(),
    this.wasteMovementId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : closeoutId = Value(closeoutId),
       itemId = Value(itemId),
       depletionMicros = Value(depletionMicros);
  static Insertable<CloseoutLine> custom({
    Expression<String>? closeoutId,
    Expression<String>? itemId,
    Expression<int>? loadedMicros,
    Expression<int>? returnedMicros,
    Expression<int>? wasteMicros,
    Expression<int>? depletionMicros,
    Expression<bool>? stockout,
    Expression<bool>? approximate,
    Expression<String>? consumptionMovementId,
    Expression<String>? wasteMovementId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (closeoutId != null) 'closeout_id': closeoutId,
      if (itemId != null) 'item_id': itemId,
      if (loadedMicros != null) 'loaded_micros': loadedMicros,
      if (returnedMicros != null) 'returned_micros': returnedMicros,
      if (wasteMicros != null) 'waste_micros': wasteMicros,
      if (depletionMicros != null) 'depletion_micros': depletionMicros,
      if (stockout != null) 'stockout': stockout,
      if (approximate != null) 'approximate': approximate,
      if (consumptionMovementId != null)
        'consumption_movement_id': consumptionMovementId,
      if (wasteMovementId != null) 'waste_movement_id': wasteMovementId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CloseoutLinesCompanion copyWith({
    Value<String>? closeoutId,
    Value<String>? itemId,
    Value<int?>? loadedMicros,
    Value<int?>? returnedMicros,
    Value<int?>? wasteMicros,
    Value<int>? depletionMicros,
    Value<bool>? stockout,
    Value<bool>? approximate,
    Value<String?>? consumptionMovementId,
    Value<String?>? wasteMovementId,
    Value<int>? rowid,
  }) {
    return CloseoutLinesCompanion(
      closeoutId: closeoutId ?? this.closeoutId,
      itemId: itemId ?? this.itemId,
      loadedMicros: loadedMicros ?? this.loadedMicros,
      returnedMicros: returnedMicros ?? this.returnedMicros,
      wasteMicros: wasteMicros ?? this.wasteMicros,
      depletionMicros: depletionMicros ?? this.depletionMicros,
      stockout: stockout ?? this.stockout,
      approximate: approximate ?? this.approximate,
      consumptionMovementId:
          consumptionMovementId ?? this.consumptionMovementId,
      wasteMovementId: wasteMovementId ?? this.wasteMovementId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (closeoutId.present) {
      map['closeout_id'] = Variable<String>(closeoutId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (loadedMicros.present) {
      map['loaded_micros'] = Variable<int>(loadedMicros.value);
    }
    if (returnedMicros.present) {
      map['returned_micros'] = Variable<int>(returnedMicros.value);
    }
    if (wasteMicros.present) {
      map['waste_micros'] = Variable<int>(wasteMicros.value);
    }
    if (depletionMicros.present) {
      map['depletion_micros'] = Variable<int>(depletionMicros.value);
    }
    if (stockout.present) {
      map['stockout'] = Variable<bool>(stockout.value);
    }
    if (approximate.present) {
      map['approximate'] = Variable<bool>(approximate.value);
    }
    if (consumptionMovementId.present) {
      map['consumption_movement_id'] = Variable<String>(
        consumptionMovementId.value,
      );
    }
    if (wasteMovementId.present) {
      map['waste_movement_id'] = Variable<String>(wasteMovementId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CloseoutLinesCompanion(')
          ..write('closeoutId: $closeoutId, ')
          ..write('itemId: $itemId, ')
          ..write('loadedMicros: $loadedMicros, ')
          ..write('returnedMicros: $returnedMicros, ')
          ..write('wasteMicros: $wasteMicros, ')
          ..write('depletionMicros: $depletionMicros, ')
          ..write('stockout: $stockout, ')
          ..write('approximate: $approximate, ')
          ..write('consumptionMovementId: $consumptionMovementId, ')
          ..write('wasteMovementId: $wasteMovementId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CloseoutDraftsTable extends CloseoutDrafts
    with TableInfo<$CloseoutDraftsTable, CloseoutDraft> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CloseoutDraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES events (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMicrosMeta = const VerificationMeta(
    'updatedAtMicros',
  );
  @override
  late final GeneratedColumn<int> updatedAtMicros = GeneratedColumn<int>(
    'updated_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [eventId, payloadJson, updatedAtMicros];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'closeout_drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<CloseoutDraft> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('updated_at_micros')) {
      context.handle(
        _updatedAtMicrosMeta,
        updatedAtMicros.isAcceptableOrUnknown(
          data['updated_at_micros']!,
          _updatedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {eventId};
  @override
  CloseoutDraft map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CloseoutDraft(
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      updatedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_micros'],
      )!,
    );
  }

  @override
  $CloseoutDraftsTable createAlias(String alias) {
    return $CloseoutDraftsTable(attachedDatabase, alias);
  }
}

class CloseoutDraft extends DataClass implements Insertable<CloseoutDraft> {
  final String eventId;
  final String payloadJson;
  final int updatedAtMicros;
  const CloseoutDraft({
    required this.eventId,
    required this.payloadJson,
    required this.updatedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    map['payload_json'] = Variable<String>(payloadJson);
    map['updated_at_micros'] = Variable<int>(updatedAtMicros);
    return map;
  }

  CloseoutDraftsCompanion toCompanion(bool nullToAbsent) {
    return CloseoutDraftsCompanion(
      eventId: Value(eventId),
      payloadJson: Value(payloadJson),
      updatedAtMicros: Value(updatedAtMicros),
    );
  }

  factory CloseoutDraft.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CloseoutDraft(
      eventId: serializer.fromJson<String>(json['eventId']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      updatedAtMicros: serializer.fromJson<int>(json['updatedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventId': serializer.toJson<String>(eventId),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'updatedAtMicros': serializer.toJson<int>(updatedAtMicros),
    };
  }

  CloseoutDraft copyWith({
    String? eventId,
    String? payloadJson,
    int? updatedAtMicros,
  }) => CloseoutDraft(
    eventId: eventId ?? this.eventId,
    payloadJson: payloadJson ?? this.payloadJson,
    updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
  );
  CloseoutDraft copyWithCompanion(CloseoutDraftsCompanion data) {
    return CloseoutDraft(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      updatedAtMicros: data.updatedAtMicros.present
          ? data.updatedAtMicros.value
          : this.updatedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CloseoutDraft(')
          ..write('eventId: $eventId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('updatedAtMicros: $updatedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(eventId, payloadJson, updatedAtMicros);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CloseoutDraft &&
          other.eventId == this.eventId &&
          other.payloadJson == this.payloadJson &&
          other.updatedAtMicros == this.updatedAtMicros);
}

class CloseoutDraftsCompanion extends UpdateCompanion<CloseoutDraft> {
  final Value<String> eventId;
  final Value<String> payloadJson;
  final Value<int> updatedAtMicros;
  final Value<int> rowid;
  const CloseoutDraftsCompanion({
    this.eventId = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.updatedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CloseoutDraftsCompanion.insert({
    required String eventId,
    required String payloadJson,
    required int updatedAtMicros,
    this.rowid = const Value.absent(),
  }) : eventId = Value(eventId),
       payloadJson = Value(payloadJson),
       updatedAtMicros = Value(updatedAtMicros);
  static Insertable<CloseoutDraft> custom({
    Expression<String>? eventId,
    Expression<String>? payloadJson,
    Expression<int>? updatedAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (updatedAtMicros != null) 'updated_at_micros': updatedAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CloseoutDraftsCompanion copyWith({
    Value<String>? eventId,
    Value<String>? payloadJson,
    Value<int>? updatedAtMicros,
    Value<int>? rowid,
  }) {
    return CloseoutDraftsCompanion(
      eventId: eventId ?? this.eventId,
      payloadJson: payloadJson ?? this.payloadJson,
      updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (updatedAtMicros.present) {
      map['updated_at_micros'] = Variable<int>(updatedAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CloseoutDraftsCompanion(')
          ..write('eventId: $eventId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('updatedAtMicros: $updatedAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecipesTable extends Recipes with TableInfo<$RecipesTable, Recipe> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecipesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 26,
      maxTextLength: 26,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outputItemIdMeta = const VerificationMeta(
    'outputItemId',
  );
  @override
  late final GeneratedColumn<String> outputItemId = GeneratedColumn<String>(
    'output_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 120,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _archivedAtMicrosMeta = const VerificationMeta(
    'archivedAtMicros',
  );
  @override
  late final GeneratedColumn<int> archivedAtMicros = GeneratedColumn<int>(
    'archived_at_micros',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    outputItemId,
    name,
    archivedAtMicros,
    createdAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recipes';
  @override
  VerificationContext validateIntegrity(
    Insertable<Recipe> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('output_item_id')) {
      context.handle(
        _outputItemIdMeta,
        outputItemId.isAcceptableOrUnknown(
          data['output_item_id']!,
          _outputItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_outputItemIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('archived_at_micros')) {
      context.handle(
        _archivedAtMicrosMeta,
        archivedAtMicros.isAcceptableOrUnknown(
          data['archived_at_micros']!,
          _archivedAtMicrosMeta,
        ),
      );
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Recipe map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Recipe(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      outputItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}output_item_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      archivedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}archived_at_micros'],
      ),
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
    );
  }

  @override
  $RecipesTable createAlias(String alias) {
    return $RecipesTable(attachedDatabase, alias);
  }
}

class Recipe extends DataClass implements Insertable<Recipe> {
  final String id;
  final String outputItemId;
  final String name;
  final int? archivedAtMicros;
  final int createdAtMicros;
  const Recipe({
    required this.id,
    required this.outputItemId,
    required this.name,
    this.archivedAtMicros,
    required this.createdAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['output_item_id'] = Variable<String>(outputItemId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || archivedAtMicros != null) {
      map['archived_at_micros'] = Variable<int>(archivedAtMicros);
    }
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    return map;
  }

  RecipesCompanion toCompanion(bool nullToAbsent) {
    return RecipesCompanion(
      id: Value(id),
      outputItemId: Value(outputItemId),
      name: Value(name),
      archivedAtMicros: archivedAtMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAtMicros),
      createdAtMicros: Value(createdAtMicros),
    );
  }

  factory Recipe.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Recipe(
      id: serializer.fromJson<String>(json['id']),
      outputItemId: serializer.fromJson<String>(json['outputItemId']),
      name: serializer.fromJson<String>(json['name']),
      archivedAtMicros: serializer.fromJson<int?>(json['archivedAtMicros']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'outputItemId': serializer.toJson<String>(outputItemId),
      'name': serializer.toJson<String>(name),
      'archivedAtMicros': serializer.toJson<int?>(archivedAtMicros),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
    };
  }

  Recipe copyWith({
    String? id,
    String? outputItemId,
    String? name,
    Value<int?> archivedAtMicros = const Value.absent(),
    int? createdAtMicros,
  }) => Recipe(
    id: id ?? this.id,
    outputItemId: outputItemId ?? this.outputItemId,
    name: name ?? this.name,
    archivedAtMicros: archivedAtMicros.present
        ? archivedAtMicros.value
        : this.archivedAtMicros,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
  );
  Recipe copyWithCompanion(RecipesCompanion data) {
    return Recipe(
      id: data.id.present ? data.id.value : this.id,
      outputItemId: data.outputItemId.present
          ? data.outputItemId.value
          : this.outputItemId,
      name: data.name.present ? data.name.value : this.name,
      archivedAtMicros: data.archivedAtMicros.present
          ? data.archivedAtMicros.value
          : this.archivedAtMicros,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Recipe(')
          ..write('id: $id, ')
          ..write('outputItemId: $outputItemId, ')
          ..write('name: $name, ')
          ..write('archivedAtMicros: $archivedAtMicros, ')
          ..write('createdAtMicros: $createdAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, outputItemId, name, archivedAtMicros, createdAtMicros);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Recipe &&
          other.id == this.id &&
          other.outputItemId == this.outputItemId &&
          other.name == this.name &&
          other.archivedAtMicros == this.archivedAtMicros &&
          other.createdAtMicros == this.createdAtMicros);
}

class RecipesCompanion extends UpdateCompanion<Recipe> {
  final Value<String> id;
  final Value<String> outputItemId;
  final Value<String> name;
  final Value<int?> archivedAtMicros;
  final Value<int> createdAtMicros;
  final Value<int> rowid;
  const RecipesCompanion({
    this.id = const Value.absent(),
    this.outputItemId = const Value.absent(),
    this.name = const Value.absent(),
    this.archivedAtMicros = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecipesCompanion.insert({
    required String id,
    required String outputItemId,
    required String name,
    this.archivedAtMicros = const Value.absent(),
    required int createdAtMicros,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       outputItemId = Value(outputItemId),
       name = Value(name),
       createdAtMicros = Value(createdAtMicros);
  static Insertable<Recipe> custom({
    Expression<String>? id,
    Expression<String>? outputItemId,
    Expression<String>? name,
    Expression<int>? archivedAtMicros,
    Expression<int>? createdAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (outputItemId != null) 'output_item_id': outputItemId,
      if (name != null) 'name': name,
      if (archivedAtMicros != null) 'archived_at_micros': archivedAtMicros,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecipesCompanion copyWith({
    Value<String>? id,
    Value<String>? outputItemId,
    Value<String>? name,
    Value<int?>? archivedAtMicros,
    Value<int>? createdAtMicros,
    Value<int>? rowid,
  }) {
    return RecipesCompanion(
      id: id ?? this.id,
      outputItemId: outputItemId ?? this.outputItemId,
      name: name ?? this.name,
      archivedAtMicros: archivedAtMicros ?? this.archivedAtMicros,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (outputItemId.present) {
      map['output_item_id'] = Variable<String>(outputItemId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (archivedAtMicros.present) {
      map['archived_at_micros'] = Variable<int>(archivedAtMicros.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecipesCompanion(')
          ..write('id: $id, ')
          ..write('outputItemId: $outputItemId, ')
          ..write('name: $name, ')
          ..write('archivedAtMicros: $archivedAtMicros, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecipeRevisionsTable extends RecipeRevisions
    with TableInfo<$RecipeRevisionsTable, RecipeRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecipeRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 26,
      maxTextLength: 26,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recipeIdMeta = const VerificationMeta(
    'recipeId',
  );
  @override
  late final GeneratedColumn<String> recipeId = GeneratedColumn<String>(
    'recipe_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES recipes (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    check: () => ComparableExpr(revision).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yieldMicrosMeta = const VerificationMeta(
    'yieldMicros',
  );
  @override
  late final GeneratedColumn<int> yieldMicros = GeneratedColumn<int>(
    'yield_micros',
    aliasedName,
    false,
    check: () => ComparableExpr(yieldMicros).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yieldLabelMeta = const VerificationMeta(
    'yieldLabel',
  );
  @override
  late final GeneratedColumn<String> yieldLabel = GeneratedColumn<String>(
    'yield_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceKindMeta = const VerificationMeta(
    'sourceKind',
  );
  @override
  late final GeneratedColumn<String> sourceKind = GeneratedColumn<String>(
    'source_kind',
    aliasedName,
    false,
    check: () => sourceKind.isIn(['form', 'ocr']),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    recipeId,
    revision,
    yieldMicros,
    yieldLabel,
    sourceKind,
    note,
    createdAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recipe_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecipeRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('recipe_id')) {
      context.handle(
        _recipeIdMeta,
        recipeId.isAcceptableOrUnknown(data['recipe_id']!, _recipeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recipeIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('yield_micros')) {
      context.handle(
        _yieldMicrosMeta,
        yieldMicros.isAcceptableOrUnknown(
          data['yield_micros']!,
          _yieldMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_yieldMicrosMeta);
    }
    if (data.containsKey('yield_label')) {
      context.handle(
        _yieldLabelMeta,
        yieldLabel.isAcceptableOrUnknown(data['yield_label']!, _yieldLabelMeta),
      );
    }
    if (data.containsKey('source_kind')) {
      context.handle(
        _sourceKindMeta,
        sourceKind.isAcceptableOrUnknown(data['source_kind']!, _sourceKindMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceKindMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecipeRevision map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecipeRevision(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      recipeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipe_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      yieldMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}yield_micros'],
      )!,
      yieldLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}yield_label'],
      ),
      sourceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_kind'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
    );
  }

  @override
  $RecipeRevisionsTable createAlias(String alias) {
    return $RecipeRevisionsTable(attachedDatabase, alias);
  }
}

class RecipeRevision extends DataClass implements Insertable<RecipeRevision> {
  final String id;
  final String recipeId;
  final int revision;
  final int yieldMicros;
  final String? yieldLabel;
  final String sourceKind;
  final String note;
  final int createdAtMicros;
  const RecipeRevision({
    required this.id,
    required this.recipeId,
    required this.revision,
    required this.yieldMicros,
    this.yieldLabel,
    required this.sourceKind,
    required this.note,
    required this.createdAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['recipe_id'] = Variable<String>(recipeId);
    map['revision'] = Variable<int>(revision);
    map['yield_micros'] = Variable<int>(yieldMicros);
    if (!nullToAbsent || yieldLabel != null) {
      map['yield_label'] = Variable<String>(yieldLabel);
    }
    map['source_kind'] = Variable<String>(sourceKind);
    map['note'] = Variable<String>(note);
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    return map;
  }

  RecipeRevisionsCompanion toCompanion(bool nullToAbsent) {
    return RecipeRevisionsCompanion(
      id: Value(id),
      recipeId: Value(recipeId),
      revision: Value(revision),
      yieldMicros: Value(yieldMicros),
      yieldLabel: yieldLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(yieldLabel),
      sourceKind: Value(sourceKind),
      note: Value(note),
      createdAtMicros: Value(createdAtMicros),
    );
  }

  factory RecipeRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecipeRevision(
      id: serializer.fromJson<String>(json['id']),
      recipeId: serializer.fromJson<String>(json['recipeId']),
      revision: serializer.fromJson<int>(json['revision']),
      yieldMicros: serializer.fromJson<int>(json['yieldMicros']),
      yieldLabel: serializer.fromJson<String?>(json['yieldLabel']),
      sourceKind: serializer.fromJson<String>(json['sourceKind']),
      note: serializer.fromJson<String>(json['note']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'recipeId': serializer.toJson<String>(recipeId),
      'revision': serializer.toJson<int>(revision),
      'yieldMicros': serializer.toJson<int>(yieldMicros),
      'yieldLabel': serializer.toJson<String?>(yieldLabel),
      'sourceKind': serializer.toJson<String>(sourceKind),
      'note': serializer.toJson<String>(note),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
    };
  }

  RecipeRevision copyWith({
    String? id,
    String? recipeId,
    int? revision,
    int? yieldMicros,
    Value<String?> yieldLabel = const Value.absent(),
    String? sourceKind,
    String? note,
    int? createdAtMicros,
  }) => RecipeRevision(
    id: id ?? this.id,
    recipeId: recipeId ?? this.recipeId,
    revision: revision ?? this.revision,
    yieldMicros: yieldMicros ?? this.yieldMicros,
    yieldLabel: yieldLabel.present ? yieldLabel.value : this.yieldLabel,
    sourceKind: sourceKind ?? this.sourceKind,
    note: note ?? this.note,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
  );
  RecipeRevision copyWithCompanion(RecipeRevisionsCompanion data) {
    return RecipeRevision(
      id: data.id.present ? data.id.value : this.id,
      recipeId: data.recipeId.present ? data.recipeId.value : this.recipeId,
      revision: data.revision.present ? data.revision.value : this.revision,
      yieldMicros: data.yieldMicros.present
          ? data.yieldMicros.value
          : this.yieldMicros,
      yieldLabel: data.yieldLabel.present
          ? data.yieldLabel.value
          : this.yieldLabel,
      sourceKind: data.sourceKind.present
          ? data.sourceKind.value
          : this.sourceKind,
      note: data.note.present ? data.note.value : this.note,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecipeRevision(')
          ..write('id: $id, ')
          ..write('recipeId: $recipeId, ')
          ..write('revision: $revision, ')
          ..write('yieldMicros: $yieldMicros, ')
          ..write('yieldLabel: $yieldLabel, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('note: $note, ')
          ..write('createdAtMicros: $createdAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    recipeId,
    revision,
    yieldMicros,
    yieldLabel,
    sourceKind,
    note,
    createdAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecipeRevision &&
          other.id == this.id &&
          other.recipeId == this.recipeId &&
          other.revision == this.revision &&
          other.yieldMicros == this.yieldMicros &&
          other.yieldLabel == this.yieldLabel &&
          other.sourceKind == this.sourceKind &&
          other.note == this.note &&
          other.createdAtMicros == this.createdAtMicros);
}

class RecipeRevisionsCompanion extends UpdateCompanion<RecipeRevision> {
  final Value<String> id;
  final Value<String> recipeId;
  final Value<int> revision;
  final Value<int> yieldMicros;
  final Value<String?> yieldLabel;
  final Value<String> sourceKind;
  final Value<String> note;
  final Value<int> createdAtMicros;
  final Value<int> rowid;
  const RecipeRevisionsCompanion({
    this.id = const Value.absent(),
    this.recipeId = const Value.absent(),
    this.revision = const Value.absent(),
    this.yieldMicros = const Value.absent(),
    this.yieldLabel = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecipeRevisionsCompanion.insert({
    required String id,
    required String recipeId,
    required int revision,
    required int yieldMicros,
    this.yieldLabel = const Value.absent(),
    required String sourceKind,
    this.note = const Value.absent(),
    required int createdAtMicros,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       recipeId = Value(recipeId),
       revision = Value(revision),
       yieldMicros = Value(yieldMicros),
       sourceKind = Value(sourceKind),
       createdAtMicros = Value(createdAtMicros);
  static Insertable<RecipeRevision> custom({
    Expression<String>? id,
    Expression<String>? recipeId,
    Expression<int>? revision,
    Expression<int>? yieldMicros,
    Expression<String>? yieldLabel,
    Expression<String>? sourceKind,
    Expression<String>? note,
    Expression<int>? createdAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recipeId != null) 'recipe_id': recipeId,
      if (revision != null) 'revision': revision,
      if (yieldMicros != null) 'yield_micros': yieldMicros,
      if (yieldLabel != null) 'yield_label': yieldLabel,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (note != null) 'note': note,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecipeRevisionsCompanion copyWith({
    Value<String>? id,
    Value<String>? recipeId,
    Value<int>? revision,
    Value<int>? yieldMicros,
    Value<String?>? yieldLabel,
    Value<String>? sourceKind,
    Value<String>? note,
    Value<int>? createdAtMicros,
    Value<int>? rowid,
  }) {
    return RecipeRevisionsCompanion(
      id: id ?? this.id,
      recipeId: recipeId ?? this.recipeId,
      revision: revision ?? this.revision,
      yieldMicros: yieldMicros ?? this.yieldMicros,
      yieldLabel: yieldLabel ?? this.yieldLabel,
      sourceKind: sourceKind ?? this.sourceKind,
      note: note ?? this.note,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (recipeId.present) {
      map['recipe_id'] = Variable<String>(recipeId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (yieldMicros.present) {
      map['yield_micros'] = Variable<int>(yieldMicros.value);
    }
    if (yieldLabel.present) {
      map['yield_label'] = Variable<String>(yieldLabel.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(sourceKind.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecipeRevisionsCompanion(')
          ..write('id: $id, ')
          ..write('recipeId: $recipeId, ')
          ..write('revision: $revision, ')
          ..write('yieldMicros: $yieldMicros, ')
          ..write('yieldLabel: $yieldLabel, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('note: $note, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecipeLinesTable extends RecipeLines
    with TableInfo<$RecipeLinesTable, RecipeLine> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecipeLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _revisionIdMeta = const VerificationMeta(
    'revisionId',
  );
  @override
  late final GeneratedColumn<String> revisionId = GeneratedColumn<String>(
    'revision_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES recipe_revisions (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _lineIndexMeta = const VerificationMeta(
    'lineIndex',
  );
  @override
  late final GeneratedColumn<int> lineIndex = GeneratedColumn<int>(
    'line_index',
    aliasedName,
    false,
    check: () => ComparableExpr(lineIndex).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ingredientItemIdMeta = const VerificationMeta(
    'ingredientItemId',
  );
  @override
  late final GeneratedColumn<String> ingredientItemId = GeneratedColumn<String>(
    'ingredient_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _quantityPerBatchMicrosMeta =
      const VerificationMeta('quantityPerBatchMicros');
  @override
  late final GeneratedColumn<int> quantityPerBatchMicros = GeneratedColumn<int>(
    'quantity_per_batch_micros',
    aliasedName,
    false,
    check: () => ComparableExpr(quantityPerBatchMicros).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    revisionId,
    lineIndex,
    ingredientItemId,
    quantityPerBatchMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recipe_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecipeLine> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('revision_id')) {
      context.handle(
        _revisionIdMeta,
        revisionId.isAcceptableOrUnknown(data['revision_id']!, _revisionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionIdMeta);
    }
    if (data.containsKey('line_index')) {
      context.handle(
        _lineIndexMeta,
        lineIndex.isAcceptableOrUnknown(data['line_index']!, _lineIndexMeta),
      );
    } else if (isInserting) {
      context.missing(_lineIndexMeta);
    }
    if (data.containsKey('ingredient_item_id')) {
      context.handle(
        _ingredientItemIdMeta,
        ingredientItemId.isAcceptableOrUnknown(
          data['ingredient_item_id']!,
          _ingredientItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ingredientItemIdMeta);
    }
    if (data.containsKey('quantity_per_batch_micros')) {
      context.handle(
        _quantityPerBatchMicrosMeta,
        quantityPerBatchMicros.isAcceptableOrUnknown(
          data['quantity_per_batch_micros']!,
          _quantityPerBatchMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_quantityPerBatchMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {revisionId, lineIndex};
  @override
  RecipeLine map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecipeLine(
      revisionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}revision_id'],
      )!,
      lineIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line_index'],
      )!,
      ingredientItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ingredient_item_id'],
      )!,
      quantityPerBatchMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity_per_batch_micros'],
      )!,
    );
  }

  @override
  $RecipeLinesTable createAlias(String alias) {
    return $RecipeLinesTable(attachedDatabase, alias);
  }
}

class RecipeLine extends DataClass implements Insertable<RecipeLine> {
  final String revisionId;
  final int lineIndex;
  final String ingredientItemId;
  final int quantityPerBatchMicros;
  const RecipeLine({
    required this.revisionId,
    required this.lineIndex,
    required this.ingredientItemId,
    required this.quantityPerBatchMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['revision_id'] = Variable<String>(revisionId);
    map['line_index'] = Variable<int>(lineIndex);
    map['ingredient_item_id'] = Variable<String>(ingredientItemId);
    map['quantity_per_batch_micros'] = Variable<int>(quantityPerBatchMicros);
    return map;
  }

  RecipeLinesCompanion toCompanion(bool nullToAbsent) {
    return RecipeLinesCompanion(
      revisionId: Value(revisionId),
      lineIndex: Value(lineIndex),
      ingredientItemId: Value(ingredientItemId),
      quantityPerBatchMicros: Value(quantityPerBatchMicros),
    );
  }

  factory RecipeLine.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecipeLine(
      revisionId: serializer.fromJson<String>(json['revisionId']),
      lineIndex: serializer.fromJson<int>(json['lineIndex']),
      ingredientItemId: serializer.fromJson<String>(json['ingredientItemId']),
      quantityPerBatchMicros: serializer.fromJson<int>(
        json['quantityPerBatchMicros'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'revisionId': serializer.toJson<String>(revisionId),
      'lineIndex': serializer.toJson<int>(lineIndex),
      'ingredientItemId': serializer.toJson<String>(ingredientItemId),
      'quantityPerBatchMicros': serializer.toJson<int>(quantityPerBatchMicros),
    };
  }

  RecipeLine copyWith({
    String? revisionId,
    int? lineIndex,
    String? ingredientItemId,
    int? quantityPerBatchMicros,
  }) => RecipeLine(
    revisionId: revisionId ?? this.revisionId,
    lineIndex: lineIndex ?? this.lineIndex,
    ingredientItemId: ingredientItemId ?? this.ingredientItemId,
    quantityPerBatchMicros:
        quantityPerBatchMicros ?? this.quantityPerBatchMicros,
  );
  RecipeLine copyWithCompanion(RecipeLinesCompanion data) {
    return RecipeLine(
      revisionId: data.revisionId.present
          ? data.revisionId.value
          : this.revisionId,
      lineIndex: data.lineIndex.present ? data.lineIndex.value : this.lineIndex,
      ingredientItemId: data.ingredientItemId.present
          ? data.ingredientItemId.value
          : this.ingredientItemId,
      quantityPerBatchMicros: data.quantityPerBatchMicros.present
          ? data.quantityPerBatchMicros.value
          : this.quantityPerBatchMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecipeLine(')
          ..write('revisionId: $revisionId, ')
          ..write('lineIndex: $lineIndex, ')
          ..write('ingredientItemId: $ingredientItemId, ')
          ..write('quantityPerBatchMicros: $quantityPerBatchMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    revisionId,
    lineIndex,
    ingredientItemId,
    quantityPerBatchMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecipeLine &&
          other.revisionId == this.revisionId &&
          other.lineIndex == this.lineIndex &&
          other.ingredientItemId == this.ingredientItemId &&
          other.quantityPerBatchMicros == this.quantityPerBatchMicros);
}

class RecipeLinesCompanion extends UpdateCompanion<RecipeLine> {
  final Value<String> revisionId;
  final Value<int> lineIndex;
  final Value<String> ingredientItemId;
  final Value<int> quantityPerBatchMicros;
  final Value<int> rowid;
  const RecipeLinesCompanion({
    this.revisionId = const Value.absent(),
    this.lineIndex = const Value.absent(),
    this.ingredientItemId = const Value.absent(),
    this.quantityPerBatchMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecipeLinesCompanion.insert({
    required String revisionId,
    required int lineIndex,
    required String ingredientItemId,
    required int quantityPerBatchMicros,
    this.rowid = const Value.absent(),
  }) : revisionId = Value(revisionId),
       lineIndex = Value(lineIndex),
       ingredientItemId = Value(ingredientItemId),
       quantityPerBatchMicros = Value(quantityPerBatchMicros);
  static Insertable<RecipeLine> custom({
    Expression<String>? revisionId,
    Expression<int>? lineIndex,
    Expression<String>? ingredientItemId,
    Expression<int>? quantityPerBatchMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (revisionId != null) 'revision_id': revisionId,
      if (lineIndex != null) 'line_index': lineIndex,
      if (ingredientItemId != null) 'ingredient_item_id': ingredientItemId,
      if (quantityPerBatchMicros != null)
        'quantity_per_batch_micros': quantityPerBatchMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecipeLinesCompanion copyWith({
    Value<String>? revisionId,
    Value<int>? lineIndex,
    Value<String>? ingredientItemId,
    Value<int>? quantityPerBatchMicros,
    Value<int>? rowid,
  }) {
    return RecipeLinesCompanion(
      revisionId: revisionId ?? this.revisionId,
      lineIndex: lineIndex ?? this.lineIndex,
      ingredientItemId: ingredientItemId ?? this.ingredientItemId,
      quantityPerBatchMicros:
          quantityPerBatchMicros ?? this.quantityPerBatchMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (revisionId.present) {
      map['revision_id'] = Variable<String>(revisionId.value);
    }
    if (lineIndex.present) {
      map['line_index'] = Variable<int>(lineIndex.value);
    }
    if (ingredientItemId.present) {
      map['ingredient_item_id'] = Variable<String>(ingredientItemId.value);
    }
    if (quantityPerBatchMicros.present) {
      map['quantity_per_batch_micros'] = Variable<int>(
        quantityPerBatchMicros.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecipeLinesCompanion(')
          ..write('revisionId: $revisionId, ')
          ..write('lineIndex: $lineIndex, ')
          ..write('ingredientItemId: $ingredientItemId, ')
          ..write('quantityPerBatchMicros: $quantityPerBatchMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ForecastSnapshotsTable extends ForecastSnapshots
    with TableInfo<$ForecastSnapshotsTable, ForecastSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ForecastSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 26,
      maxTextLength: 26,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES events (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _methodMeta = const VerificationMeta('method');
  @override
  late final GeneratedColumn<String> method = GeneratedColumn<String>(
    'method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _methodVersionMeta = const VerificationMeta(
    'methodVersion',
  );
  @override
  late final GeneratedColumn<int> methodVersion = GeneratedColumn<int>(
    'method_version',
    aliasedName,
    false,
    check: () => ComparableExpr(methodVersion).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _policyMeta = const VerificationMeta('policy');
  @override
  late final GeneratedColumn<String> policy = GeneratedColumn<String>(
    'policy',
    aliasedName,
    false,
    check: () => policy.isIn(['lean', 'balanced', 'cautious']),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _upcomingExposureMeta = const VerificationMeta(
    'upcomingExposure',
  );
  @override
  late final GeneratedColumn<int> upcomingExposure = GeneratedColumn<int>(
    'upcoming_exposure',
    aliasedName,
    false,
    check: () => ComparableExpr(upcomingExposure).isBetweenValues(1, 1000000),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _historyWindowMeta = const VerificationMeta(
    'historyWindow',
  );
  @override
  late final GeneratedColumn<int> historyWindow = GeneratedColumn<int>(
    'history_window',
    aliasedName,
    false,
    check: () => ComparableExpr(historyWindow).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inputsHashMeta = const VerificationMeta(
    'inputsHash',
  );
  @override
  late final GeneratedColumn<String> inputsHash = GeneratedColumn<String>(
    'inputs_hash',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 64,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _assumptionsJsonMeta = const VerificationMeta(
    'assumptionsJson',
  );
  @override
  late final GeneratedColumn<String> assumptionsJson = GeneratedColumn<String>(
    'assumptions_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _sourceCommandIdMeta = const VerificationMeta(
    'sourceCommandId',
  );
  @override
  late final GeneratedColumn<String> sourceCommandId = GeneratedColumn<String>(
    'source_command_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES commands (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    eventId,
    method,
    methodVersion,
    policy,
    upcomingExposure,
    historyWindow,
    inputsHash,
    assumptionsJson,
    sourceCommandId,
    createdAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'forecast_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<ForecastSnapshot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('method')) {
      context.handle(
        _methodMeta,
        method.isAcceptableOrUnknown(data['method']!, _methodMeta),
      );
    } else if (isInserting) {
      context.missing(_methodMeta);
    }
    if (data.containsKey('method_version')) {
      context.handle(
        _methodVersionMeta,
        methodVersion.isAcceptableOrUnknown(
          data['method_version']!,
          _methodVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_methodVersionMeta);
    }
    if (data.containsKey('policy')) {
      context.handle(
        _policyMeta,
        policy.isAcceptableOrUnknown(data['policy']!, _policyMeta),
      );
    } else if (isInserting) {
      context.missing(_policyMeta);
    }
    if (data.containsKey('upcoming_exposure')) {
      context.handle(
        _upcomingExposureMeta,
        upcomingExposure.isAcceptableOrUnknown(
          data['upcoming_exposure']!,
          _upcomingExposureMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_upcomingExposureMeta);
    }
    if (data.containsKey('history_window')) {
      context.handle(
        _historyWindowMeta,
        historyWindow.isAcceptableOrUnknown(
          data['history_window']!,
          _historyWindowMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_historyWindowMeta);
    }
    if (data.containsKey('inputs_hash')) {
      context.handle(
        _inputsHashMeta,
        inputsHash.isAcceptableOrUnknown(data['inputs_hash']!, _inputsHashMeta),
      );
    } else if (isInserting) {
      context.missing(_inputsHashMeta);
    }
    if (data.containsKey('assumptions_json')) {
      context.handle(
        _assumptionsJsonMeta,
        assumptionsJson.isAcceptableOrUnknown(
          data['assumptions_json']!,
          _assumptionsJsonMeta,
        ),
      );
    }
    if (data.containsKey('source_command_id')) {
      context.handle(
        _sourceCommandIdMeta,
        sourceCommandId.isAcceptableOrUnknown(
          data['source_command_id']!,
          _sourceCommandIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceCommandIdMeta);
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ForecastSnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ForecastSnapshot(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      method: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}method'],
      )!,
      methodVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}method_version'],
      )!,
      policy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}policy'],
      )!,
      upcomingExposure: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}upcoming_exposure'],
      )!,
      historyWindow: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}history_window'],
      )!,
      inputsHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inputs_hash'],
      )!,
      assumptionsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assumptions_json'],
      )!,
      sourceCommandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_command_id'],
      )!,
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
    );
  }

  @override
  $ForecastSnapshotsTable createAlias(String alias) {
    return $ForecastSnapshotsTable(attachedDatabase, alias);
  }
}

class ForecastSnapshot extends DataClass
    implements Insertable<ForecastSnapshot> {
  final String id;
  final String eventId;
  final String method;
  final int methodVersion;
  final String policy;
  final int upcomingExposure;

  /// The last-N history window in force when this snapshot was generated.
  final int historyWindow;

  /// SHA-256 lowercase hex over the canonical input encoding (§6.6).
  final String inputsHash;

  /// JSON, e.g. {"reserve_percent":10,"history_window":12,
  /// "rate_normalization":"per_exposure_median","exposure_label":"attendance"}.
  final String assumptionsJson;
  final String sourceCommandId;
  final int createdAtMicros;
  const ForecastSnapshot({
    required this.id,
    required this.eventId,
    required this.method,
    required this.methodVersion,
    required this.policy,
    required this.upcomingExposure,
    required this.historyWindow,
    required this.inputsHash,
    required this.assumptionsJson,
    required this.sourceCommandId,
    required this.createdAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['event_id'] = Variable<String>(eventId);
    map['method'] = Variable<String>(method);
    map['method_version'] = Variable<int>(methodVersion);
    map['policy'] = Variable<String>(policy);
    map['upcoming_exposure'] = Variable<int>(upcomingExposure);
    map['history_window'] = Variable<int>(historyWindow);
    map['inputs_hash'] = Variable<String>(inputsHash);
    map['assumptions_json'] = Variable<String>(assumptionsJson);
    map['source_command_id'] = Variable<String>(sourceCommandId);
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    return map;
  }

  ForecastSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return ForecastSnapshotsCompanion(
      id: Value(id),
      eventId: Value(eventId),
      method: Value(method),
      methodVersion: Value(methodVersion),
      policy: Value(policy),
      upcomingExposure: Value(upcomingExposure),
      historyWindow: Value(historyWindow),
      inputsHash: Value(inputsHash),
      assumptionsJson: Value(assumptionsJson),
      sourceCommandId: Value(sourceCommandId),
      createdAtMicros: Value(createdAtMicros),
    );
  }

  factory ForecastSnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ForecastSnapshot(
      id: serializer.fromJson<String>(json['id']),
      eventId: serializer.fromJson<String>(json['eventId']),
      method: serializer.fromJson<String>(json['method']),
      methodVersion: serializer.fromJson<int>(json['methodVersion']),
      policy: serializer.fromJson<String>(json['policy']),
      upcomingExposure: serializer.fromJson<int>(json['upcomingExposure']),
      historyWindow: serializer.fromJson<int>(json['historyWindow']),
      inputsHash: serializer.fromJson<String>(json['inputsHash']),
      assumptionsJson: serializer.fromJson<String>(json['assumptionsJson']),
      sourceCommandId: serializer.fromJson<String>(json['sourceCommandId']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'eventId': serializer.toJson<String>(eventId),
      'method': serializer.toJson<String>(method),
      'methodVersion': serializer.toJson<int>(methodVersion),
      'policy': serializer.toJson<String>(policy),
      'upcomingExposure': serializer.toJson<int>(upcomingExposure),
      'historyWindow': serializer.toJson<int>(historyWindow),
      'inputsHash': serializer.toJson<String>(inputsHash),
      'assumptionsJson': serializer.toJson<String>(assumptionsJson),
      'sourceCommandId': serializer.toJson<String>(sourceCommandId),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
    };
  }

  ForecastSnapshot copyWith({
    String? id,
    String? eventId,
    String? method,
    int? methodVersion,
    String? policy,
    int? upcomingExposure,
    int? historyWindow,
    String? inputsHash,
    String? assumptionsJson,
    String? sourceCommandId,
    int? createdAtMicros,
  }) => ForecastSnapshot(
    id: id ?? this.id,
    eventId: eventId ?? this.eventId,
    method: method ?? this.method,
    methodVersion: methodVersion ?? this.methodVersion,
    policy: policy ?? this.policy,
    upcomingExposure: upcomingExposure ?? this.upcomingExposure,
    historyWindow: historyWindow ?? this.historyWindow,
    inputsHash: inputsHash ?? this.inputsHash,
    assumptionsJson: assumptionsJson ?? this.assumptionsJson,
    sourceCommandId: sourceCommandId ?? this.sourceCommandId,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
  );
  ForecastSnapshot copyWithCompanion(ForecastSnapshotsCompanion data) {
    return ForecastSnapshot(
      id: data.id.present ? data.id.value : this.id,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      method: data.method.present ? data.method.value : this.method,
      methodVersion: data.methodVersion.present
          ? data.methodVersion.value
          : this.methodVersion,
      policy: data.policy.present ? data.policy.value : this.policy,
      upcomingExposure: data.upcomingExposure.present
          ? data.upcomingExposure.value
          : this.upcomingExposure,
      historyWindow: data.historyWindow.present
          ? data.historyWindow.value
          : this.historyWindow,
      inputsHash: data.inputsHash.present
          ? data.inputsHash.value
          : this.inputsHash,
      assumptionsJson: data.assumptionsJson.present
          ? data.assumptionsJson.value
          : this.assumptionsJson,
      sourceCommandId: data.sourceCommandId.present
          ? data.sourceCommandId.value
          : this.sourceCommandId,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ForecastSnapshot(')
          ..write('id: $id, ')
          ..write('eventId: $eventId, ')
          ..write('method: $method, ')
          ..write('methodVersion: $methodVersion, ')
          ..write('policy: $policy, ')
          ..write('upcomingExposure: $upcomingExposure, ')
          ..write('historyWindow: $historyWindow, ')
          ..write('inputsHash: $inputsHash, ')
          ..write('assumptionsJson: $assumptionsJson, ')
          ..write('sourceCommandId: $sourceCommandId, ')
          ..write('createdAtMicros: $createdAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    eventId,
    method,
    methodVersion,
    policy,
    upcomingExposure,
    historyWindow,
    inputsHash,
    assumptionsJson,
    sourceCommandId,
    createdAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ForecastSnapshot &&
          other.id == this.id &&
          other.eventId == this.eventId &&
          other.method == this.method &&
          other.methodVersion == this.methodVersion &&
          other.policy == this.policy &&
          other.upcomingExposure == this.upcomingExposure &&
          other.historyWindow == this.historyWindow &&
          other.inputsHash == this.inputsHash &&
          other.assumptionsJson == this.assumptionsJson &&
          other.sourceCommandId == this.sourceCommandId &&
          other.createdAtMicros == this.createdAtMicros);
}

class ForecastSnapshotsCompanion extends UpdateCompanion<ForecastSnapshot> {
  final Value<String> id;
  final Value<String> eventId;
  final Value<String> method;
  final Value<int> methodVersion;
  final Value<String> policy;
  final Value<int> upcomingExposure;
  final Value<int> historyWindow;
  final Value<String> inputsHash;
  final Value<String> assumptionsJson;
  final Value<String> sourceCommandId;
  final Value<int> createdAtMicros;
  final Value<int> rowid;
  const ForecastSnapshotsCompanion({
    this.id = const Value.absent(),
    this.eventId = const Value.absent(),
    this.method = const Value.absent(),
    this.methodVersion = const Value.absent(),
    this.policy = const Value.absent(),
    this.upcomingExposure = const Value.absent(),
    this.historyWindow = const Value.absent(),
    this.inputsHash = const Value.absent(),
    this.assumptionsJson = const Value.absent(),
    this.sourceCommandId = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ForecastSnapshotsCompanion.insert({
    required String id,
    required String eventId,
    required String method,
    required int methodVersion,
    required String policy,
    required int upcomingExposure,
    required int historyWindow,
    required String inputsHash,
    this.assumptionsJson = const Value.absent(),
    required String sourceCommandId,
    required int createdAtMicros,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       eventId = Value(eventId),
       method = Value(method),
       methodVersion = Value(methodVersion),
       policy = Value(policy),
       upcomingExposure = Value(upcomingExposure),
       historyWindow = Value(historyWindow),
       inputsHash = Value(inputsHash),
       sourceCommandId = Value(sourceCommandId),
       createdAtMicros = Value(createdAtMicros);
  static Insertable<ForecastSnapshot> custom({
    Expression<String>? id,
    Expression<String>? eventId,
    Expression<String>? method,
    Expression<int>? methodVersion,
    Expression<String>? policy,
    Expression<int>? upcomingExposure,
    Expression<int>? historyWindow,
    Expression<String>? inputsHash,
    Expression<String>? assumptionsJson,
    Expression<String>? sourceCommandId,
    Expression<int>? createdAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (eventId != null) 'event_id': eventId,
      if (method != null) 'method': method,
      if (methodVersion != null) 'method_version': methodVersion,
      if (policy != null) 'policy': policy,
      if (upcomingExposure != null) 'upcoming_exposure': upcomingExposure,
      if (historyWindow != null) 'history_window': historyWindow,
      if (inputsHash != null) 'inputs_hash': inputsHash,
      if (assumptionsJson != null) 'assumptions_json': assumptionsJson,
      if (sourceCommandId != null) 'source_command_id': sourceCommandId,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ForecastSnapshotsCompanion copyWith({
    Value<String>? id,
    Value<String>? eventId,
    Value<String>? method,
    Value<int>? methodVersion,
    Value<String>? policy,
    Value<int>? upcomingExposure,
    Value<int>? historyWindow,
    Value<String>? inputsHash,
    Value<String>? assumptionsJson,
    Value<String>? sourceCommandId,
    Value<int>? createdAtMicros,
    Value<int>? rowid,
  }) {
    return ForecastSnapshotsCompanion(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      method: method ?? this.method,
      methodVersion: methodVersion ?? this.methodVersion,
      policy: policy ?? this.policy,
      upcomingExposure: upcomingExposure ?? this.upcomingExposure,
      historyWindow: historyWindow ?? this.historyWindow,
      inputsHash: inputsHash ?? this.inputsHash,
      assumptionsJson: assumptionsJson ?? this.assumptionsJson,
      sourceCommandId: sourceCommandId ?? this.sourceCommandId,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(method.value);
    }
    if (methodVersion.present) {
      map['method_version'] = Variable<int>(methodVersion.value);
    }
    if (policy.present) {
      map['policy'] = Variable<String>(policy.value);
    }
    if (upcomingExposure.present) {
      map['upcoming_exposure'] = Variable<int>(upcomingExposure.value);
    }
    if (historyWindow.present) {
      map['history_window'] = Variable<int>(historyWindow.value);
    }
    if (inputsHash.present) {
      map['inputs_hash'] = Variable<String>(inputsHash.value);
    }
    if (assumptionsJson.present) {
      map['assumptions_json'] = Variable<String>(assumptionsJson.value);
    }
    if (sourceCommandId.present) {
      map['source_command_id'] = Variable<String>(sourceCommandId.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ForecastSnapshotsCompanion(')
          ..write('id: $id, ')
          ..write('eventId: $eventId, ')
          ..write('method: $method, ')
          ..write('methodVersion: $methodVersion, ')
          ..write('policy: $policy, ')
          ..write('upcomingExposure: $upcomingExposure, ')
          ..write('historyWindow: $historyWindow, ')
          ..write('inputsHash: $inputsHash, ')
          ..write('assumptionsJson: $assumptionsJson, ')
          ..write('sourceCommandId: $sourceCommandId, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ForecastLinesTable extends ForecastLines
    with TableInfo<$ForecastLinesTable, ForecastLine> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ForecastLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _snapshotIdMeta = const VerificationMeta(
    'snapshotId',
  );
  @override
  late final GeneratedColumn<String> snapshotId = GeneratedColumn<String>(
    'snapshot_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES forecast_snapshots (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _packSizeMicrosMeta = const VerificationMeta(
    'packSizeMicros',
  );
  @override
  late final GeneratedColumn<int> packSizeMicros = GeneratedColumn<int>(
    'pack_size_micros',
    aliasedName,
    false,
    check: () => ComparableExpr(packSizeMicros).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _onHandMicrosMeta = const VerificationMeta(
    'onHandMicros',
  );
  @override
  late final GeneratedColumn<int> onHandMicros = GeneratedColumn<int>(
    'on_hand_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _confirmedInboundMicrosMeta =
      const VerificationMeta('confirmedInboundMicros');
  @override
  late final GeneratedColumn<int> confirmedInboundMicros = GeneratedColumn<int>(
    'confirmed_inbound_micros',
    aliasedName,
    false,
    check: () => ComparableExpr(confirmedInboundMicros).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _expectedUseMicrosMeta = const VerificationMeta(
    'expectedUseMicros',
  );
  @override
  late final GeneratedColumn<int> expectedUseMicros = GeneratedColumn<int>(
    'expected_use_micros',
    aliasedName,
    true,
    check: () => ComparableExpr(expectedUseMicros).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _plannedMicrosMeta = const VerificationMeta(
    'plannedMicros',
  );
  @override
  late final GeneratedColumn<int> plannedMicros = GeneratedColumn<int>(
    'planned_micros',
    aliasedName,
    true,
    check: () => ComparableExpr(plannedMicros).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _loadMicrosMeta = const VerificationMeta(
    'loadMicros',
  );
  @override
  late final GeneratedColumn<int> loadMicros = GeneratedColumn<int>(
    'load_micros',
    aliasedName,
    true,
    check: () => ComparableExpr(loadMicros).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _acquireMicrosMeta = const VerificationMeta(
    'acquireMicros',
  );
  @override
  late final GeneratedColumn<int> acquireMicros = GeneratedColumn<int>(
    'acquire_micros',
    aliasedName,
    true,
    check: () => ComparableExpr(acquireMicros).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _evidenceGradeMeta = const VerificationMeta(
    'evidenceGrade',
  );
  @override
  late final GeneratedColumn<String> evidenceGrade = GeneratedColumn<String>(
    'evidence_grade',
    aliasedName,
    false,
    check: () => evidenceGrade.isIn([
      'insufficient_data',
      'single_event',
      'observed_range',
    ]),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _warningsJsonMeta = const VerificationMeta(
    'warningsJson',
  );
  @override
  late final GeneratedColumn<String> warningsJson = GeneratedColumn<String>(
    'warnings_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    snapshotId,
    itemId,
    packSizeMicros,
    onHandMicros,
    confirmedInboundMicros,
    expectedUseMicros,
    plannedMicros,
    loadMicros,
    acquireMicros,
    evidenceGrade,
    warningsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'forecast_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<ForecastLine> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('snapshot_id')) {
      context.handle(
        _snapshotIdMeta,
        snapshotId.isAcceptableOrUnknown(data['snapshot_id']!, _snapshotIdMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('pack_size_micros')) {
      context.handle(
        _packSizeMicrosMeta,
        packSizeMicros.isAcceptableOrUnknown(
          data['pack_size_micros']!,
          _packSizeMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_packSizeMicrosMeta);
    }
    if (data.containsKey('on_hand_micros')) {
      context.handle(
        _onHandMicrosMeta,
        onHandMicros.isAcceptableOrUnknown(
          data['on_hand_micros']!,
          _onHandMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_onHandMicrosMeta);
    }
    if (data.containsKey('confirmed_inbound_micros')) {
      context.handle(
        _confirmedInboundMicrosMeta,
        confirmedInboundMicros.isAcceptableOrUnknown(
          data['confirmed_inbound_micros']!,
          _confirmedInboundMicrosMeta,
        ),
      );
    }
    if (data.containsKey('expected_use_micros')) {
      context.handle(
        _expectedUseMicrosMeta,
        expectedUseMicros.isAcceptableOrUnknown(
          data['expected_use_micros']!,
          _expectedUseMicrosMeta,
        ),
      );
    }
    if (data.containsKey('planned_micros')) {
      context.handle(
        _plannedMicrosMeta,
        plannedMicros.isAcceptableOrUnknown(
          data['planned_micros']!,
          _plannedMicrosMeta,
        ),
      );
    }
    if (data.containsKey('load_micros')) {
      context.handle(
        _loadMicrosMeta,
        loadMicros.isAcceptableOrUnknown(data['load_micros']!, _loadMicrosMeta),
      );
    }
    if (data.containsKey('acquire_micros')) {
      context.handle(
        _acquireMicrosMeta,
        acquireMicros.isAcceptableOrUnknown(
          data['acquire_micros']!,
          _acquireMicrosMeta,
        ),
      );
    }
    if (data.containsKey('evidence_grade')) {
      context.handle(
        _evidenceGradeMeta,
        evidenceGrade.isAcceptableOrUnknown(
          data['evidence_grade']!,
          _evidenceGradeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_evidenceGradeMeta);
    }
    if (data.containsKey('warnings_json')) {
      context.handle(
        _warningsJsonMeta,
        warningsJson.isAcceptableOrUnknown(
          data['warnings_json']!,
          _warningsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {snapshotId, itemId};
  @override
  ForecastLine map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ForecastLine(
      snapshotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      packSizeMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pack_size_micros'],
      )!,
      onHandMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}on_hand_micros'],
      )!,
      confirmedInboundMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}confirmed_inbound_micros'],
      )!,
      expectedUseMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expected_use_micros'],
      ),
      plannedMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}planned_micros'],
      ),
      loadMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}load_micros'],
      ),
      acquireMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}acquire_micros'],
      ),
      evidenceGrade: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evidence_grade'],
      )!,
      warningsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}warnings_json'],
      )!,
    );
  }

  @override
  $ForecastLinesTable createAlias(String alias) {
    return $ForecastLinesTable(attachedDatabase, alias);
  }
}

class ForecastLine extends DataClass implements Insertable<ForecastLine> {
  final String snapshotId;
  final String itemId;
  final int packSizeMicros;
  final int onHandMicros;
  final int confirmedInboundMicros;
  final int? expectedUseMicros;
  final int? plannedMicros;
  final int? loadMicros;
  final int? acquireMicros;
  final String evidenceGrade;
  final String warningsJson;
  const ForecastLine({
    required this.snapshotId,
    required this.itemId,
    required this.packSizeMicros,
    required this.onHandMicros,
    required this.confirmedInboundMicros,
    this.expectedUseMicros,
    this.plannedMicros,
    this.loadMicros,
    this.acquireMicros,
    required this.evidenceGrade,
    required this.warningsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['snapshot_id'] = Variable<String>(snapshotId);
    map['item_id'] = Variable<String>(itemId);
    map['pack_size_micros'] = Variable<int>(packSizeMicros);
    map['on_hand_micros'] = Variable<int>(onHandMicros);
    map['confirmed_inbound_micros'] = Variable<int>(confirmedInboundMicros);
    if (!nullToAbsent || expectedUseMicros != null) {
      map['expected_use_micros'] = Variable<int>(expectedUseMicros);
    }
    if (!nullToAbsent || plannedMicros != null) {
      map['planned_micros'] = Variable<int>(plannedMicros);
    }
    if (!nullToAbsent || loadMicros != null) {
      map['load_micros'] = Variable<int>(loadMicros);
    }
    if (!nullToAbsent || acquireMicros != null) {
      map['acquire_micros'] = Variable<int>(acquireMicros);
    }
    map['evidence_grade'] = Variable<String>(evidenceGrade);
    map['warnings_json'] = Variable<String>(warningsJson);
    return map;
  }

  ForecastLinesCompanion toCompanion(bool nullToAbsent) {
    return ForecastLinesCompanion(
      snapshotId: Value(snapshotId),
      itemId: Value(itemId),
      packSizeMicros: Value(packSizeMicros),
      onHandMicros: Value(onHandMicros),
      confirmedInboundMicros: Value(confirmedInboundMicros),
      expectedUseMicros: expectedUseMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(expectedUseMicros),
      plannedMicros: plannedMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(plannedMicros),
      loadMicros: loadMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(loadMicros),
      acquireMicros: acquireMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(acquireMicros),
      evidenceGrade: Value(evidenceGrade),
      warningsJson: Value(warningsJson),
    );
  }

  factory ForecastLine.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ForecastLine(
      snapshotId: serializer.fromJson<String>(json['snapshotId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      packSizeMicros: serializer.fromJson<int>(json['packSizeMicros']),
      onHandMicros: serializer.fromJson<int>(json['onHandMicros']),
      confirmedInboundMicros: serializer.fromJson<int>(
        json['confirmedInboundMicros'],
      ),
      expectedUseMicros: serializer.fromJson<int?>(json['expectedUseMicros']),
      plannedMicros: serializer.fromJson<int?>(json['plannedMicros']),
      loadMicros: serializer.fromJson<int?>(json['loadMicros']),
      acquireMicros: serializer.fromJson<int?>(json['acquireMicros']),
      evidenceGrade: serializer.fromJson<String>(json['evidenceGrade']),
      warningsJson: serializer.fromJson<String>(json['warningsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'snapshotId': serializer.toJson<String>(snapshotId),
      'itemId': serializer.toJson<String>(itemId),
      'packSizeMicros': serializer.toJson<int>(packSizeMicros),
      'onHandMicros': serializer.toJson<int>(onHandMicros),
      'confirmedInboundMicros': serializer.toJson<int>(confirmedInboundMicros),
      'expectedUseMicros': serializer.toJson<int?>(expectedUseMicros),
      'plannedMicros': serializer.toJson<int?>(plannedMicros),
      'loadMicros': serializer.toJson<int?>(loadMicros),
      'acquireMicros': serializer.toJson<int?>(acquireMicros),
      'evidenceGrade': serializer.toJson<String>(evidenceGrade),
      'warningsJson': serializer.toJson<String>(warningsJson),
    };
  }

  ForecastLine copyWith({
    String? snapshotId,
    String? itemId,
    int? packSizeMicros,
    int? onHandMicros,
    int? confirmedInboundMicros,
    Value<int?> expectedUseMicros = const Value.absent(),
    Value<int?> plannedMicros = const Value.absent(),
    Value<int?> loadMicros = const Value.absent(),
    Value<int?> acquireMicros = const Value.absent(),
    String? evidenceGrade,
    String? warningsJson,
  }) => ForecastLine(
    snapshotId: snapshotId ?? this.snapshotId,
    itemId: itemId ?? this.itemId,
    packSizeMicros: packSizeMicros ?? this.packSizeMicros,
    onHandMicros: onHandMicros ?? this.onHandMicros,
    confirmedInboundMicros:
        confirmedInboundMicros ?? this.confirmedInboundMicros,
    expectedUseMicros: expectedUseMicros.present
        ? expectedUseMicros.value
        : this.expectedUseMicros,
    plannedMicros: plannedMicros.present
        ? plannedMicros.value
        : this.plannedMicros,
    loadMicros: loadMicros.present ? loadMicros.value : this.loadMicros,
    acquireMicros: acquireMicros.present
        ? acquireMicros.value
        : this.acquireMicros,
    evidenceGrade: evidenceGrade ?? this.evidenceGrade,
    warningsJson: warningsJson ?? this.warningsJson,
  );
  ForecastLine copyWithCompanion(ForecastLinesCompanion data) {
    return ForecastLine(
      snapshotId: data.snapshotId.present
          ? data.snapshotId.value
          : this.snapshotId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      packSizeMicros: data.packSizeMicros.present
          ? data.packSizeMicros.value
          : this.packSizeMicros,
      onHandMicros: data.onHandMicros.present
          ? data.onHandMicros.value
          : this.onHandMicros,
      confirmedInboundMicros: data.confirmedInboundMicros.present
          ? data.confirmedInboundMicros.value
          : this.confirmedInboundMicros,
      expectedUseMicros: data.expectedUseMicros.present
          ? data.expectedUseMicros.value
          : this.expectedUseMicros,
      plannedMicros: data.plannedMicros.present
          ? data.plannedMicros.value
          : this.plannedMicros,
      loadMicros: data.loadMicros.present
          ? data.loadMicros.value
          : this.loadMicros,
      acquireMicros: data.acquireMicros.present
          ? data.acquireMicros.value
          : this.acquireMicros,
      evidenceGrade: data.evidenceGrade.present
          ? data.evidenceGrade.value
          : this.evidenceGrade,
      warningsJson: data.warningsJson.present
          ? data.warningsJson.value
          : this.warningsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ForecastLine(')
          ..write('snapshotId: $snapshotId, ')
          ..write('itemId: $itemId, ')
          ..write('packSizeMicros: $packSizeMicros, ')
          ..write('onHandMicros: $onHandMicros, ')
          ..write('confirmedInboundMicros: $confirmedInboundMicros, ')
          ..write('expectedUseMicros: $expectedUseMicros, ')
          ..write('plannedMicros: $plannedMicros, ')
          ..write('loadMicros: $loadMicros, ')
          ..write('acquireMicros: $acquireMicros, ')
          ..write('evidenceGrade: $evidenceGrade, ')
          ..write('warningsJson: $warningsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    snapshotId,
    itemId,
    packSizeMicros,
    onHandMicros,
    confirmedInboundMicros,
    expectedUseMicros,
    plannedMicros,
    loadMicros,
    acquireMicros,
    evidenceGrade,
    warningsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ForecastLine &&
          other.snapshotId == this.snapshotId &&
          other.itemId == this.itemId &&
          other.packSizeMicros == this.packSizeMicros &&
          other.onHandMicros == this.onHandMicros &&
          other.confirmedInboundMicros == this.confirmedInboundMicros &&
          other.expectedUseMicros == this.expectedUseMicros &&
          other.plannedMicros == this.plannedMicros &&
          other.loadMicros == this.loadMicros &&
          other.acquireMicros == this.acquireMicros &&
          other.evidenceGrade == this.evidenceGrade &&
          other.warningsJson == this.warningsJson);
}

class ForecastLinesCompanion extends UpdateCompanion<ForecastLine> {
  final Value<String> snapshotId;
  final Value<String> itemId;
  final Value<int> packSizeMicros;
  final Value<int> onHandMicros;
  final Value<int> confirmedInboundMicros;
  final Value<int?> expectedUseMicros;
  final Value<int?> plannedMicros;
  final Value<int?> loadMicros;
  final Value<int?> acquireMicros;
  final Value<String> evidenceGrade;
  final Value<String> warningsJson;
  final Value<int> rowid;
  const ForecastLinesCompanion({
    this.snapshotId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.packSizeMicros = const Value.absent(),
    this.onHandMicros = const Value.absent(),
    this.confirmedInboundMicros = const Value.absent(),
    this.expectedUseMicros = const Value.absent(),
    this.plannedMicros = const Value.absent(),
    this.loadMicros = const Value.absent(),
    this.acquireMicros = const Value.absent(),
    this.evidenceGrade = const Value.absent(),
    this.warningsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ForecastLinesCompanion.insert({
    required String snapshotId,
    required String itemId,
    required int packSizeMicros,
    required int onHandMicros,
    this.confirmedInboundMicros = const Value.absent(),
    this.expectedUseMicros = const Value.absent(),
    this.plannedMicros = const Value.absent(),
    this.loadMicros = const Value.absent(),
    this.acquireMicros = const Value.absent(),
    required String evidenceGrade,
    this.warningsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : snapshotId = Value(snapshotId),
       itemId = Value(itemId),
       packSizeMicros = Value(packSizeMicros),
       onHandMicros = Value(onHandMicros),
       evidenceGrade = Value(evidenceGrade);
  static Insertable<ForecastLine> custom({
    Expression<String>? snapshotId,
    Expression<String>? itemId,
    Expression<int>? packSizeMicros,
    Expression<int>? onHandMicros,
    Expression<int>? confirmedInboundMicros,
    Expression<int>? expectedUseMicros,
    Expression<int>? plannedMicros,
    Expression<int>? loadMicros,
    Expression<int>? acquireMicros,
    Expression<String>? evidenceGrade,
    Expression<String>? warningsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (snapshotId != null) 'snapshot_id': snapshotId,
      if (itemId != null) 'item_id': itemId,
      if (packSizeMicros != null) 'pack_size_micros': packSizeMicros,
      if (onHandMicros != null) 'on_hand_micros': onHandMicros,
      if (confirmedInboundMicros != null)
        'confirmed_inbound_micros': confirmedInboundMicros,
      if (expectedUseMicros != null) 'expected_use_micros': expectedUseMicros,
      if (plannedMicros != null) 'planned_micros': plannedMicros,
      if (loadMicros != null) 'load_micros': loadMicros,
      if (acquireMicros != null) 'acquire_micros': acquireMicros,
      if (evidenceGrade != null) 'evidence_grade': evidenceGrade,
      if (warningsJson != null) 'warnings_json': warningsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ForecastLinesCompanion copyWith({
    Value<String>? snapshotId,
    Value<String>? itemId,
    Value<int>? packSizeMicros,
    Value<int>? onHandMicros,
    Value<int>? confirmedInboundMicros,
    Value<int?>? expectedUseMicros,
    Value<int?>? plannedMicros,
    Value<int?>? loadMicros,
    Value<int?>? acquireMicros,
    Value<String>? evidenceGrade,
    Value<String>? warningsJson,
    Value<int>? rowid,
  }) {
    return ForecastLinesCompanion(
      snapshotId: snapshotId ?? this.snapshotId,
      itemId: itemId ?? this.itemId,
      packSizeMicros: packSizeMicros ?? this.packSizeMicros,
      onHandMicros: onHandMicros ?? this.onHandMicros,
      confirmedInboundMicros:
          confirmedInboundMicros ?? this.confirmedInboundMicros,
      expectedUseMicros: expectedUseMicros ?? this.expectedUseMicros,
      plannedMicros: plannedMicros ?? this.plannedMicros,
      loadMicros: loadMicros ?? this.loadMicros,
      acquireMicros: acquireMicros ?? this.acquireMicros,
      evidenceGrade: evidenceGrade ?? this.evidenceGrade,
      warningsJson: warningsJson ?? this.warningsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (snapshotId.present) {
      map['snapshot_id'] = Variable<String>(snapshotId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (packSizeMicros.present) {
      map['pack_size_micros'] = Variable<int>(packSizeMicros.value);
    }
    if (onHandMicros.present) {
      map['on_hand_micros'] = Variable<int>(onHandMicros.value);
    }
    if (confirmedInboundMicros.present) {
      map['confirmed_inbound_micros'] = Variable<int>(
        confirmedInboundMicros.value,
      );
    }
    if (expectedUseMicros.present) {
      map['expected_use_micros'] = Variable<int>(expectedUseMicros.value);
    }
    if (plannedMicros.present) {
      map['planned_micros'] = Variable<int>(plannedMicros.value);
    }
    if (loadMicros.present) {
      map['load_micros'] = Variable<int>(loadMicros.value);
    }
    if (acquireMicros.present) {
      map['acquire_micros'] = Variable<int>(acquireMicros.value);
    }
    if (evidenceGrade.present) {
      map['evidence_grade'] = Variable<String>(evidenceGrade.value);
    }
    if (warningsJson.present) {
      map['warnings_json'] = Variable<String>(warningsJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ForecastLinesCompanion(')
          ..write('snapshotId: $snapshotId, ')
          ..write('itemId: $itemId, ')
          ..write('packSizeMicros: $packSizeMicros, ')
          ..write('onHandMicros: $onHandMicros, ')
          ..write('confirmedInboundMicros: $confirmedInboundMicros, ')
          ..write('expectedUseMicros: $expectedUseMicros, ')
          ..write('plannedMicros: $plannedMicros, ')
          ..write('loadMicros: $loadMicros, ')
          ..write('acquireMicros: $acquireMicros, ')
          ..write('evidenceGrade: $evidenceGrade, ')
          ..write('warningsJson: $warningsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ForecastEvidenceTable extends ForecastEvidence
    with TableInfo<$ForecastEvidenceTable, ForecastEvidenceData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ForecastEvidenceTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _snapshotIdMeta = const VerificationMeta(
    'snapshotId',
  );
  @override
  late final GeneratedColumn<String> snapshotId = GeneratedColumn<String>(
    'snapshot_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES forecast_snapshots (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    check: () => ComparableExpr(position).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _closeoutIdMeta = const VerificationMeta(
    'closeoutId',
  );
  @override
  late final GeneratedColumn<String> closeoutId = GeneratedColumn<String>(
    'closeout_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES event_closeouts (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _sourceEventIdMeta = const VerificationMeta(
    'sourceEventId',
  );
  @override
  late final GeneratedColumn<String> sourceEventId = GeneratedColumn<String>(
    'source_event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES events (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _exposureMeta = const VerificationMeta(
    'exposure',
  );
  @override
  late final GeneratedColumn<int> exposure = GeneratedColumn<int>(
    'exposure',
    aliasedName,
    false,
    check: () => ComparableExpr(exposure).isBetweenValues(1, 1000000),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _depletionMicrosMeta = const VerificationMeta(
    'depletionMicros',
  );
  @override
  late final GeneratedColumn<int> depletionMicros = GeneratedColumn<int>(
    'depletion_micros',
    aliasedName,
    false,
    check: () =>
        ComparableExpr(depletionMicros).isBetweenValues(0, 1000000000000),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stockoutMeta = const VerificationMeta(
    'stockout',
  );
  @override
  late final GeneratedColumn<bool> stockout = GeneratedColumn<bool>(
    'stockout',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("stockout" IN (0, 1))',
    ),
  );
  static const VerificationMeta _approximateMeta = const VerificationMeta(
    'approximate',
  );
  @override
  late final GeneratedColumn<bool> approximate = GeneratedColumn<bool>(
    'approximate',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("approximate" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    snapshotId,
    itemId,
    position,
    closeoutId,
    sourceEventId,
    exposure,
    depletionMicros,
    stockout,
    approximate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'forecast_evidence';
  @override
  VerificationContext validateIntegrity(
    Insertable<ForecastEvidenceData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('snapshot_id')) {
      context.handle(
        _snapshotIdMeta,
        snapshotId.isAcceptableOrUnknown(data['snapshot_id']!, _snapshotIdMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('closeout_id')) {
      context.handle(
        _closeoutIdMeta,
        closeoutId.isAcceptableOrUnknown(data['closeout_id']!, _closeoutIdMeta),
      );
    } else if (isInserting) {
      context.missing(_closeoutIdMeta);
    }
    if (data.containsKey('source_event_id')) {
      context.handle(
        _sourceEventIdMeta,
        sourceEventId.isAcceptableOrUnknown(
          data['source_event_id']!,
          _sourceEventIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceEventIdMeta);
    }
    if (data.containsKey('exposure')) {
      context.handle(
        _exposureMeta,
        exposure.isAcceptableOrUnknown(data['exposure']!, _exposureMeta),
      );
    } else if (isInserting) {
      context.missing(_exposureMeta);
    }
    if (data.containsKey('depletion_micros')) {
      context.handle(
        _depletionMicrosMeta,
        depletionMicros.isAcceptableOrUnknown(
          data['depletion_micros']!,
          _depletionMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_depletionMicrosMeta);
    }
    if (data.containsKey('stockout')) {
      context.handle(
        _stockoutMeta,
        stockout.isAcceptableOrUnknown(data['stockout']!, _stockoutMeta),
      );
    } else if (isInserting) {
      context.missing(_stockoutMeta);
    }
    if (data.containsKey('approximate')) {
      context.handle(
        _approximateMeta,
        approximate.isAcceptableOrUnknown(
          data['approximate']!,
          _approximateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_approximateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {snapshotId, itemId, position};
  @override
  ForecastEvidenceData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ForecastEvidenceData(
      snapshotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      closeoutId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}closeout_id'],
      )!,
      sourceEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_event_id'],
      )!,
      exposure: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}exposure'],
      )!,
      depletionMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}depletion_micros'],
      )!,
      stockout: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}stockout'],
      )!,
      approximate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}approximate'],
      )!,
    );
  }

  @override
  $ForecastEvidenceTable createAlias(String alias) {
    return $ForecastEvidenceTable(attachedDatabase, alias);
  }
}

class ForecastEvidenceData extends DataClass
    implements Insertable<ForecastEvidenceData> {
  final String snapshotId;
  final String itemId;
  final int position;
  final String closeoutId;
  final String sourceEventId;
  final int exposure;
  final int depletionMicros;
  final bool stockout;
  final bool approximate;
  const ForecastEvidenceData({
    required this.snapshotId,
    required this.itemId,
    required this.position,
    required this.closeoutId,
    required this.sourceEventId,
    required this.exposure,
    required this.depletionMicros,
    required this.stockout,
    required this.approximate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['snapshot_id'] = Variable<String>(snapshotId);
    map['item_id'] = Variable<String>(itemId);
    map['position'] = Variable<int>(position);
    map['closeout_id'] = Variable<String>(closeoutId);
    map['source_event_id'] = Variable<String>(sourceEventId);
    map['exposure'] = Variable<int>(exposure);
    map['depletion_micros'] = Variable<int>(depletionMicros);
    map['stockout'] = Variable<bool>(stockout);
    map['approximate'] = Variable<bool>(approximate);
    return map;
  }

  ForecastEvidenceCompanion toCompanion(bool nullToAbsent) {
    return ForecastEvidenceCompanion(
      snapshotId: Value(snapshotId),
      itemId: Value(itemId),
      position: Value(position),
      closeoutId: Value(closeoutId),
      sourceEventId: Value(sourceEventId),
      exposure: Value(exposure),
      depletionMicros: Value(depletionMicros),
      stockout: Value(stockout),
      approximate: Value(approximate),
    );
  }

  factory ForecastEvidenceData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ForecastEvidenceData(
      snapshotId: serializer.fromJson<String>(json['snapshotId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      position: serializer.fromJson<int>(json['position']),
      closeoutId: serializer.fromJson<String>(json['closeoutId']),
      sourceEventId: serializer.fromJson<String>(json['sourceEventId']),
      exposure: serializer.fromJson<int>(json['exposure']),
      depletionMicros: serializer.fromJson<int>(json['depletionMicros']),
      stockout: serializer.fromJson<bool>(json['stockout']),
      approximate: serializer.fromJson<bool>(json['approximate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'snapshotId': serializer.toJson<String>(snapshotId),
      'itemId': serializer.toJson<String>(itemId),
      'position': serializer.toJson<int>(position),
      'closeoutId': serializer.toJson<String>(closeoutId),
      'sourceEventId': serializer.toJson<String>(sourceEventId),
      'exposure': serializer.toJson<int>(exposure),
      'depletionMicros': serializer.toJson<int>(depletionMicros),
      'stockout': serializer.toJson<bool>(stockout),
      'approximate': serializer.toJson<bool>(approximate),
    };
  }

  ForecastEvidenceData copyWith({
    String? snapshotId,
    String? itemId,
    int? position,
    String? closeoutId,
    String? sourceEventId,
    int? exposure,
    int? depletionMicros,
    bool? stockout,
    bool? approximate,
  }) => ForecastEvidenceData(
    snapshotId: snapshotId ?? this.snapshotId,
    itemId: itemId ?? this.itemId,
    position: position ?? this.position,
    closeoutId: closeoutId ?? this.closeoutId,
    sourceEventId: sourceEventId ?? this.sourceEventId,
    exposure: exposure ?? this.exposure,
    depletionMicros: depletionMicros ?? this.depletionMicros,
    stockout: stockout ?? this.stockout,
    approximate: approximate ?? this.approximate,
  );
  ForecastEvidenceData copyWithCompanion(ForecastEvidenceCompanion data) {
    return ForecastEvidenceData(
      snapshotId: data.snapshotId.present
          ? data.snapshotId.value
          : this.snapshotId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      position: data.position.present ? data.position.value : this.position,
      closeoutId: data.closeoutId.present
          ? data.closeoutId.value
          : this.closeoutId,
      sourceEventId: data.sourceEventId.present
          ? data.sourceEventId.value
          : this.sourceEventId,
      exposure: data.exposure.present ? data.exposure.value : this.exposure,
      depletionMicros: data.depletionMicros.present
          ? data.depletionMicros.value
          : this.depletionMicros,
      stockout: data.stockout.present ? data.stockout.value : this.stockout,
      approximate: data.approximate.present
          ? data.approximate.value
          : this.approximate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ForecastEvidenceData(')
          ..write('snapshotId: $snapshotId, ')
          ..write('itemId: $itemId, ')
          ..write('position: $position, ')
          ..write('closeoutId: $closeoutId, ')
          ..write('sourceEventId: $sourceEventId, ')
          ..write('exposure: $exposure, ')
          ..write('depletionMicros: $depletionMicros, ')
          ..write('stockout: $stockout, ')
          ..write('approximate: $approximate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    snapshotId,
    itemId,
    position,
    closeoutId,
    sourceEventId,
    exposure,
    depletionMicros,
    stockout,
    approximate,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ForecastEvidenceData &&
          other.snapshotId == this.snapshotId &&
          other.itemId == this.itemId &&
          other.position == this.position &&
          other.closeoutId == this.closeoutId &&
          other.sourceEventId == this.sourceEventId &&
          other.exposure == this.exposure &&
          other.depletionMicros == this.depletionMicros &&
          other.stockout == this.stockout &&
          other.approximate == this.approximate);
}

class ForecastEvidenceCompanion extends UpdateCompanion<ForecastEvidenceData> {
  final Value<String> snapshotId;
  final Value<String> itemId;
  final Value<int> position;
  final Value<String> closeoutId;
  final Value<String> sourceEventId;
  final Value<int> exposure;
  final Value<int> depletionMicros;
  final Value<bool> stockout;
  final Value<bool> approximate;
  final Value<int> rowid;
  const ForecastEvidenceCompanion({
    this.snapshotId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.position = const Value.absent(),
    this.closeoutId = const Value.absent(),
    this.sourceEventId = const Value.absent(),
    this.exposure = const Value.absent(),
    this.depletionMicros = const Value.absent(),
    this.stockout = const Value.absent(),
    this.approximate = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ForecastEvidenceCompanion.insert({
    required String snapshotId,
    required String itemId,
    required int position,
    required String closeoutId,
    required String sourceEventId,
    required int exposure,
    required int depletionMicros,
    required bool stockout,
    required bool approximate,
    this.rowid = const Value.absent(),
  }) : snapshotId = Value(snapshotId),
       itemId = Value(itemId),
       position = Value(position),
       closeoutId = Value(closeoutId),
       sourceEventId = Value(sourceEventId),
       exposure = Value(exposure),
       depletionMicros = Value(depletionMicros),
       stockout = Value(stockout),
       approximate = Value(approximate);
  static Insertable<ForecastEvidenceData> custom({
    Expression<String>? snapshotId,
    Expression<String>? itemId,
    Expression<int>? position,
    Expression<String>? closeoutId,
    Expression<String>? sourceEventId,
    Expression<int>? exposure,
    Expression<int>? depletionMicros,
    Expression<bool>? stockout,
    Expression<bool>? approximate,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (snapshotId != null) 'snapshot_id': snapshotId,
      if (itemId != null) 'item_id': itemId,
      if (position != null) 'position': position,
      if (closeoutId != null) 'closeout_id': closeoutId,
      if (sourceEventId != null) 'source_event_id': sourceEventId,
      if (exposure != null) 'exposure': exposure,
      if (depletionMicros != null) 'depletion_micros': depletionMicros,
      if (stockout != null) 'stockout': stockout,
      if (approximate != null) 'approximate': approximate,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ForecastEvidenceCompanion copyWith({
    Value<String>? snapshotId,
    Value<String>? itemId,
    Value<int>? position,
    Value<String>? closeoutId,
    Value<String>? sourceEventId,
    Value<int>? exposure,
    Value<int>? depletionMicros,
    Value<bool>? stockout,
    Value<bool>? approximate,
    Value<int>? rowid,
  }) {
    return ForecastEvidenceCompanion(
      snapshotId: snapshotId ?? this.snapshotId,
      itemId: itemId ?? this.itemId,
      position: position ?? this.position,
      closeoutId: closeoutId ?? this.closeoutId,
      sourceEventId: sourceEventId ?? this.sourceEventId,
      exposure: exposure ?? this.exposure,
      depletionMicros: depletionMicros ?? this.depletionMicros,
      stockout: stockout ?? this.stockout,
      approximate: approximate ?? this.approximate,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (snapshotId.present) {
      map['snapshot_id'] = Variable<String>(snapshotId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (closeoutId.present) {
      map['closeout_id'] = Variable<String>(closeoutId.value);
    }
    if (sourceEventId.present) {
      map['source_event_id'] = Variable<String>(sourceEventId.value);
    }
    if (exposure.present) {
      map['exposure'] = Variable<int>(exposure.value);
    }
    if (depletionMicros.present) {
      map['depletion_micros'] = Variable<int>(depletionMicros.value);
    }
    if (stockout.present) {
      map['stockout'] = Variable<bool>(stockout.value);
    }
    if (approximate.present) {
      map['approximate'] = Variable<bool>(approximate.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ForecastEvidenceCompanion(')
          ..write('snapshotId: $snapshotId, ')
          ..write('itemId: $itemId, ')
          ..write('position: $position, ')
          ..write('closeoutId: $closeoutId, ')
          ..write('sourceEventId: $sourceEventId, ')
          ..write('exposure: $exposure, ')
          ..write('depletionMicros: $depletionMicros, ')
          ..write('stockout: $stockout, ')
          ..write('approximate: $approximate, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ForecastOverridesTable extends ForecastOverrides
    with TableInfo<$ForecastOverridesTable, ForecastOverride> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ForecastOverridesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 26,
      maxTextLength: 26,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotIdMeta = const VerificationMeta(
    'snapshotId',
  );
  @override
  late final GeneratedColumn<String> snapshotId = GeneratedColumn<String>(
    'snapshot_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES forecast_snapshots (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES items (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _overrideLoadMicrosMeta =
      const VerificationMeta('overrideLoadMicros');
  @override
  late final GeneratedColumn<int> overrideLoadMicros = GeneratedColumn<int>(
    'override_load_micros',
    aliasedName,
    true,
    check: () => ComparableExpr(overrideLoadMicros).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 500,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    snapshotId,
    itemId,
    overrideLoadMicros,
    reason,
    createdAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'forecast_overrides';
  @override
  VerificationContext validateIntegrity(
    Insertable<ForecastOverride> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('snapshot_id')) {
      context.handle(
        _snapshotIdMeta,
        snapshotId.isAcceptableOrUnknown(data['snapshot_id']!, _snapshotIdMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotIdMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('override_load_micros')) {
      context.handle(
        _overrideLoadMicrosMeta,
        overrideLoadMicros.isAcceptableOrUnknown(
          data['override_load_micros']!,
          _overrideLoadMicrosMeta,
        ),
      );
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ForecastOverride map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ForecastOverride(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      snapshotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      overrideLoadMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}override_load_micros'],
      ),
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
    );
  }

  @override
  $ForecastOverridesTable createAlias(String alias) {
    return $ForecastOverridesTable(attachedDatabase, alias);
  }
}

class ForecastOverride extends DataClass
    implements Insertable<ForecastOverride> {
  final String id;
  final String snapshotId;
  final String itemId;
  final int? overrideLoadMicros;
  final String reason;
  final int createdAtMicros;
  const ForecastOverride({
    required this.id,
    required this.snapshotId,
    required this.itemId,
    this.overrideLoadMicros,
    required this.reason,
    required this.createdAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['snapshot_id'] = Variable<String>(snapshotId);
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || overrideLoadMicros != null) {
      map['override_load_micros'] = Variable<int>(overrideLoadMicros);
    }
    map['reason'] = Variable<String>(reason);
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    return map;
  }

  ForecastOverridesCompanion toCompanion(bool nullToAbsent) {
    return ForecastOverridesCompanion(
      id: Value(id),
      snapshotId: Value(snapshotId),
      itemId: Value(itemId),
      overrideLoadMicros: overrideLoadMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(overrideLoadMicros),
      reason: Value(reason),
      createdAtMicros: Value(createdAtMicros),
    );
  }

  factory ForecastOverride.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ForecastOverride(
      id: serializer.fromJson<String>(json['id']),
      snapshotId: serializer.fromJson<String>(json['snapshotId']),
      itemId: serializer.fromJson<String>(json['itemId']),
      overrideLoadMicros: serializer.fromJson<int?>(json['overrideLoadMicros']),
      reason: serializer.fromJson<String>(json['reason']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'snapshotId': serializer.toJson<String>(snapshotId),
      'itemId': serializer.toJson<String>(itemId),
      'overrideLoadMicros': serializer.toJson<int?>(overrideLoadMicros),
      'reason': serializer.toJson<String>(reason),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
    };
  }

  ForecastOverride copyWith({
    String? id,
    String? snapshotId,
    String? itemId,
    Value<int?> overrideLoadMicros = const Value.absent(),
    String? reason,
    int? createdAtMicros,
  }) => ForecastOverride(
    id: id ?? this.id,
    snapshotId: snapshotId ?? this.snapshotId,
    itemId: itemId ?? this.itemId,
    overrideLoadMicros: overrideLoadMicros.present
        ? overrideLoadMicros.value
        : this.overrideLoadMicros,
    reason: reason ?? this.reason,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
  );
  ForecastOverride copyWithCompanion(ForecastOverridesCompanion data) {
    return ForecastOverride(
      id: data.id.present ? data.id.value : this.id,
      snapshotId: data.snapshotId.present
          ? data.snapshotId.value
          : this.snapshotId,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      overrideLoadMicros: data.overrideLoadMicros.present
          ? data.overrideLoadMicros.value
          : this.overrideLoadMicros,
      reason: data.reason.present ? data.reason.value : this.reason,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ForecastOverride(')
          ..write('id: $id, ')
          ..write('snapshotId: $snapshotId, ')
          ..write('itemId: $itemId, ')
          ..write('overrideLoadMicros: $overrideLoadMicros, ')
          ..write('reason: $reason, ')
          ..write('createdAtMicros: $createdAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    snapshotId,
    itemId,
    overrideLoadMicros,
    reason,
    createdAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ForecastOverride &&
          other.id == this.id &&
          other.snapshotId == this.snapshotId &&
          other.itemId == this.itemId &&
          other.overrideLoadMicros == this.overrideLoadMicros &&
          other.reason == this.reason &&
          other.createdAtMicros == this.createdAtMicros);
}

class ForecastOverridesCompanion extends UpdateCompanion<ForecastOverride> {
  final Value<String> id;
  final Value<String> snapshotId;
  final Value<String> itemId;
  final Value<int?> overrideLoadMicros;
  final Value<String> reason;
  final Value<int> createdAtMicros;
  final Value<int> rowid;
  const ForecastOverridesCompanion({
    this.id = const Value.absent(),
    this.snapshotId = const Value.absent(),
    this.itemId = const Value.absent(),
    this.overrideLoadMicros = const Value.absent(),
    this.reason = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ForecastOverridesCompanion.insert({
    required String id,
    required String snapshotId,
    required String itemId,
    this.overrideLoadMicros = const Value.absent(),
    required String reason,
    required int createdAtMicros,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       snapshotId = Value(snapshotId),
       itemId = Value(itemId),
       reason = Value(reason),
       createdAtMicros = Value(createdAtMicros);
  static Insertable<ForecastOverride> custom({
    Expression<String>? id,
    Expression<String>? snapshotId,
    Expression<String>? itemId,
    Expression<int>? overrideLoadMicros,
    Expression<String>? reason,
    Expression<int>? createdAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (snapshotId != null) 'snapshot_id': snapshotId,
      if (itemId != null) 'item_id': itemId,
      if (overrideLoadMicros != null)
        'override_load_micros': overrideLoadMicros,
      if (reason != null) 'reason': reason,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ForecastOverridesCompanion copyWith({
    Value<String>? id,
    Value<String>? snapshotId,
    Value<String>? itemId,
    Value<int?>? overrideLoadMicros,
    Value<String>? reason,
    Value<int>? createdAtMicros,
    Value<int>? rowid,
  }) {
    return ForecastOverridesCompanion(
      id: id ?? this.id,
      snapshotId: snapshotId ?? this.snapshotId,
      itemId: itemId ?? this.itemId,
      overrideLoadMicros: overrideLoadMicros ?? this.overrideLoadMicros,
      reason: reason ?? this.reason,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (snapshotId.present) {
      map['snapshot_id'] = Variable<String>(snapshotId.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (overrideLoadMicros.present) {
      map['override_load_micros'] = Variable<int>(overrideLoadMicros.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ForecastOverridesCompanion(')
          ..write('id: $id, ')
          ..write('snapshotId: $snapshotId, ')
          ..write('itemId: $itemId, ')
          ..write('overrideLoadMicros: $overrideLoadMicros, ')
          ..write('reason: $reason, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $WorkspaceMetaTable workspaceMeta = $WorkspaceMetaTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $CommandsTable commands = $CommandsTable(this);
  late final $ItemsTable items = $ItemsTable(this);
  late final $EventsTable events = $EventsTable(this);
  late final $EventItemsTable eventItems = $EventItemsTable(this);
  late final $InventoryMovementsTable inventoryMovements =
      $InventoryMovementsTable(this);
  late final $EventCloseoutsTable eventCloseouts = $EventCloseoutsTable(this);
  late final $CloseoutLinesTable closeoutLines = $CloseoutLinesTable(this);
  late final $CloseoutDraftsTable closeoutDrafts = $CloseoutDraftsTable(this);
  late final $RecipesTable recipes = $RecipesTable(this);
  late final $RecipeRevisionsTable recipeRevisions = $RecipeRevisionsTable(
    this,
  );
  late final $RecipeLinesTable recipeLines = $RecipeLinesTable(this);
  late final $ForecastSnapshotsTable forecastSnapshots =
      $ForecastSnapshotsTable(this);
  late final $ForecastLinesTable forecastLines = $ForecastLinesTable(this);
  late final $ForecastEvidenceTable forecastEvidence = $ForecastEvidenceTable(
    this,
  );
  late final $ForecastOverridesTable forecastOverrides =
      $ForecastOverridesTable(this);
  late final LedgerDao ledgerDao = LedgerDao(this as AppDatabase);
  late final EventDao eventDao = EventDao(this as AppDatabase);
  late final CloseoutDao closeoutDao = CloseoutDao(this as AppDatabase);
  late final ItemDao itemDao = ItemDao(this as AppDatabase);
  late final RecipeDao recipeDao = RecipeDao(this as AppDatabase);
  late final ForecastDao forecastDao = ForecastDao(this as AppDatabase);
  late final CommandDao commandDao = CommandDao(this as AppDatabase);
  late final SettingsDao settingsDao = SettingsDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    workspaceMeta,
    settings,
    commands,
    items,
    events,
    eventItems,
    inventoryMovements,
    eventCloseouts,
    closeoutLines,
    closeoutDrafts,
    recipes,
    recipeRevisions,
    recipeLines,
    forecastSnapshots,
    forecastLines,
    forecastEvidence,
    forecastOverrides,
  ];
}

typedef $$WorkspaceMetaTableCreateCompanionBuilder =
    WorkspaceMetaCompanion Function({
      Value<int> id,
      required String workspaceUid,
      Value<String> displayName,
      required int createdAtMicros,
      required String createdByAppVersion,
    });
typedef $$WorkspaceMetaTableUpdateCompanionBuilder =
    WorkspaceMetaCompanion Function({
      Value<int> id,
      Value<String> workspaceUid,
      Value<String> displayName,
      Value<int> createdAtMicros,
      Value<String> createdByAppVersion,
    });

class $$WorkspaceMetaTableFilterComposer
    extends Composer<_$AppDatabase, $WorkspaceMetaTable> {
  $$WorkspaceMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceUid => $composableBuilder(
    column: $table.workspaceUid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdByAppVersion => $composableBuilder(
    column: $table.createdByAppVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkspaceMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $WorkspaceMetaTable> {
  $$WorkspaceMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceUid => $composableBuilder(
    column: $table.workspaceUid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdByAppVersion => $composableBuilder(
    column: $table.createdByAppVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkspaceMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorkspaceMetaTable> {
  $$WorkspaceMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get workspaceUid => $composableBuilder(
    column: $table.workspaceUid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdByAppVersion => $composableBuilder(
    column: $table.createdByAppVersion,
    builder: (column) => column,
  );
}

class $$WorkspaceMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WorkspaceMetaTable,
          WorkspaceMetaData,
          $$WorkspaceMetaTableFilterComposer,
          $$WorkspaceMetaTableOrderingComposer,
          $$WorkspaceMetaTableAnnotationComposer,
          $$WorkspaceMetaTableCreateCompanionBuilder,
          $$WorkspaceMetaTableUpdateCompanionBuilder,
          (
            WorkspaceMetaData,
            BaseReferences<
              _$AppDatabase,
              $WorkspaceMetaTable,
              WorkspaceMetaData
            >,
          ),
          WorkspaceMetaData,
          PrefetchHooks Function()
        > {
  $$WorkspaceMetaTableTableManager(_$AppDatabase db, $WorkspaceMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkspaceMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkspaceMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkspaceMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> workspaceUid = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<String> createdByAppVersion = const Value.absent(),
              }) => WorkspaceMetaCompanion(
                id: id,
                workspaceUid: workspaceUid,
                displayName: displayName,
                createdAtMicros: createdAtMicros,
                createdByAppVersion: createdByAppVersion,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String workspaceUid,
                Value<String> displayName = const Value.absent(),
                required int createdAtMicros,
                required String createdByAppVersion,
              }) => WorkspaceMetaCompanion.insert(
                id: id,
                workspaceUid: workspaceUid,
                displayName: displayName,
                createdAtMicros: createdAtMicros,
                createdByAppVersion: createdByAppVersion,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkspaceMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WorkspaceMetaTable,
      WorkspaceMetaData,
      $$WorkspaceMetaTableFilterComposer,
      $$WorkspaceMetaTableOrderingComposer,
      $$WorkspaceMetaTableAnnotationComposer,
      $$WorkspaceMetaTableCreateCompanionBuilder,
      $$WorkspaceMetaTableUpdateCompanionBuilder,
      (
        WorkspaceMetaData,
        BaseReferences<_$AppDatabase, $WorkspaceMetaTable, WorkspaceMetaData>,
      ),
      WorkspaceMetaData,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      required int updatedAtMicros,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> updatedAtMicros,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => column,
  );
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> updatedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(
                key: key,
                value: value,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required int updatedAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$CommandsTableCreateCompanionBuilder =
    CommandsCompanion Function({
      required String id,
      required String origin,
      required String kind,
      required String payloadJson,
      required String status,
      required int createdAtMicros,
      Value<int?> appliedAtMicros,
      Value<String?> rejectedReason,
      Value<int> rowid,
    });
typedef $$CommandsTableUpdateCompanionBuilder =
    CommandsCompanion Function({
      Value<String> id,
      Value<String> origin,
      Value<String> kind,
      Value<String> payloadJson,
      Value<String> status,
      Value<int> createdAtMicros,
      Value<int?> appliedAtMicros,
      Value<String?> rejectedReason,
      Value<int> rowid,
    });

final class $$CommandsTableReferences
    extends BaseReferences<_$AppDatabase, $CommandsTable, Command> {
  $$CommandsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$InventoryMovementsTable, List<InventoryMovement>>
  _inventoryMovementsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.inventoryMovements,
        aliasName: 'commands__id__inventory_movements__source_command_id',
      );

  $$InventoryMovementsTableProcessedTableManager get inventoryMovementsRefs {
    final manager =
        $$InventoryMovementsTableTableManager(
          $_db,
          $_db.inventoryMovements,
        ).filter(
          (f) => f.sourceCommandId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _inventoryMovementsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$EventCloseoutsTable, List<EventCloseout>>
  _eventCloseoutsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.eventCloseouts,
    aliasName: 'commands__id__event_closeouts__source_command_id',
  );

  $$EventCloseoutsTableProcessedTableManager get eventCloseoutsRefs {
    final manager = $$EventCloseoutsTableTableManager($_db, $_db.eventCloseouts)
        .filter(
          (f) => f.sourceCommandId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(_eventCloseoutsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ForecastSnapshotsTable, List<ForecastSnapshot>>
  _forecastSnapshotsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.forecastSnapshots,
        aliasName: 'commands__id__forecast_snapshots__source_command_id',
      );

  $$ForecastSnapshotsTableProcessedTableManager get forecastSnapshotsRefs {
    final manager =
        $$ForecastSnapshotsTableTableManager(
          $_db,
          $_db.forecastSnapshots,
        ).filter(
          (f) => f.sourceCommandId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _forecastSnapshotsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CommandsTableFilterComposer
    extends Composer<_$AppDatabase, $CommandsTable> {
  $$CommandsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get appliedAtMicros => $composableBuilder(
    column: $table.appliedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rejectedReason => $composableBuilder(
    column: $table.rejectedReason,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> inventoryMovementsRefs(
    Expression<bool> Function($$InventoryMovementsTableFilterComposer f) f,
  ) {
    final $$InventoryMovementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.inventoryMovements,
      getReferencedColumn: (t) => t.sourceCommandId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryMovementsTableFilterComposer(
            $db: $db,
            $table: $db.inventoryMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> eventCloseoutsRefs(
    Expression<bool> Function($$EventCloseoutsTableFilterComposer f) f,
  ) {
    final $$EventCloseoutsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.eventCloseouts,
      getReferencedColumn: (t) => t.sourceCommandId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventCloseoutsTableFilterComposer(
            $db: $db,
            $table: $db.eventCloseouts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> forecastSnapshotsRefs(
    Expression<bool> Function($$ForecastSnapshotsTableFilterComposer f) f,
  ) {
    final $$ForecastSnapshotsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastSnapshots,
      getReferencedColumn: (t) => t.sourceCommandId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastSnapshotsTableFilterComposer(
            $db: $db,
            $table: $db.forecastSnapshots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CommandsTableOrderingComposer
    extends Composer<_$AppDatabase, $CommandsTable> {
  $$CommandsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get appliedAtMicros => $composableBuilder(
    column: $table.appliedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rejectedReason => $composableBuilder(
    column: $table.rejectedReason,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CommandsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CommandsTable> {
  $$CommandsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get appliedAtMicros => $composableBuilder(
    column: $table.appliedAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rejectedReason => $composableBuilder(
    column: $table.rejectedReason,
    builder: (column) => column,
  );

  Expression<T> inventoryMovementsRefs<T extends Object>(
    Expression<T> Function($$InventoryMovementsTableAnnotationComposer a) f,
  ) {
    final $$InventoryMovementsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.inventoryMovements,
          getReferencedColumn: (t) => t.sourceCommandId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$InventoryMovementsTableAnnotationComposer(
                $db: $db,
                $table: $db.inventoryMovements,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> eventCloseoutsRefs<T extends Object>(
    Expression<T> Function($$EventCloseoutsTableAnnotationComposer a) f,
  ) {
    final $$EventCloseoutsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.eventCloseouts,
      getReferencedColumn: (t) => t.sourceCommandId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventCloseoutsTableAnnotationComposer(
            $db: $db,
            $table: $db.eventCloseouts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> forecastSnapshotsRefs<T extends Object>(
    Expression<T> Function($$ForecastSnapshotsTableAnnotationComposer a) f,
  ) {
    final $$ForecastSnapshotsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.forecastSnapshots,
          getReferencedColumn: (t) => t.sourceCommandId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ForecastSnapshotsTableAnnotationComposer(
                $db: $db,
                $table: $db.forecastSnapshots,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$CommandsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CommandsTable,
          Command,
          $$CommandsTableFilterComposer,
          $$CommandsTableOrderingComposer,
          $$CommandsTableAnnotationComposer,
          $$CommandsTableCreateCompanionBuilder,
          $$CommandsTableUpdateCompanionBuilder,
          (Command, $$CommandsTableReferences),
          Command,
          PrefetchHooks Function({
            bool inventoryMovementsRefs,
            bool eventCloseoutsRefs,
            bool forecastSnapshotsRefs,
          })
        > {
  $$CommandsTableTableManager(_$AppDatabase db, $CommandsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CommandsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CommandsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CommandsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int?> appliedAtMicros = const Value.absent(),
                Value<String?> rejectedReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CommandsCompanion(
                id: id,
                origin: origin,
                kind: kind,
                payloadJson: payloadJson,
                status: status,
                createdAtMicros: createdAtMicros,
                appliedAtMicros: appliedAtMicros,
                rejectedReason: rejectedReason,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String origin,
                required String kind,
                required String payloadJson,
                required String status,
                required int createdAtMicros,
                Value<int?> appliedAtMicros = const Value.absent(),
                Value<String?> rejectedReason = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CommandsCompanion.insert(
                id: id,
                origin: origin,
                kind: kind,
                payloadJson: payloadJson,
                status: status,
                createdAtMicros: createdAtMicros,
                appliedAtMicros: appliedAtMicros,
                rejectedReason: rejectedReason,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CommandsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                inventoryMovementsRefs = false,
                eventCloseoutsRefs = false,
                forecastSnapshotsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (inventoryMovementsRefs) db.inventoryMovements,
                    if (eventCloseoutsRefs) db.eventCloseouts,
                    if (forecastSnapshotsRefs) db.forecastSnapshots,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (inventoryMovementsRefs)
                        await $_getPrefetchedData<
                          Command,
                          $CommandsTable,
                          InventoryMovement
                        >(
                          currentTable: table,
                          referencedTable: $$CommandsTableReferences
                              ._inventoryMovementsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CommandsTableReferences(
                                db,
                                table,
                                p0,
                              ).inventoryMovementsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sourceCommandId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (eventCloseoutsRefs)
                        await $_getPrefetchedData<
                          Command,
                          $CommandsTable,
                          EventCloseout
                        >(
                          currentTable: table,
                          referencedTable: $$CommandsTableReferences
                              ._eventCloseoutsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CommandsTableReferences(
                                db,
                                table,
                                p0,
                              ).eventCloseoutsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sourceCommandId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (forecastSnapshotsRefs)
                        await $_getPrefetchedData<
                          Command,
                          $CommandsTable,
                          ForecastSnapshot
                        >(
                          currentTable: table,
                          referencedTable: $$CommandsTableReferences
                              ._forecastSnapshotsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CommandsTableReferences(
                                db,
                                table,
                                p0,
                              ).forecastSnapshotsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sourceCommandId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$CommandsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CommandsTable,
      Command,
      $$CommandsTableFilterComposer,
      $$CommandsTableOrderingComposer,
      $$CommandsTableAnnotationComposer,
      $$CommandsTableCreateCompanionBuilder,
      $$CommandsTableUpdateCompanionBuilder,
      (Command, $$CommandsTableReferences),
      Command,
      PrefetchHooks Function({
        bool inventoryMovementsRefs,
        bool eventCloseoutsRefs,
        bool forecastSnapshotsRefs,
      })
    >;
typedef $$ItemsTableCreateCompanionBuilder =
    ItemsCompanion Function({
      required String id,
      required String name,
      required String unit,
      required int packSizeMicros,
      Value<String?> category,
      Value<String> notes,
      Value<int?> archivedAtMicros,
      required int createdAtMicros,
      required int updatedAtMicros,
      Value<int> rowid,
    });
typedef $$ItemsTableUpdateCompanionBuilder =
    ItemsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> unit,
      Value<int> packSizeMicros,
      Value<String?> category,
      Value<String> notes,
      Value<int?> archivedAtMicros,
      Value<int> createdAtMicros,
      Value<int> updatedAtMicros,
      Value<int> rowid,
    });

final class $$ItemsTableReferences
    extends BaseReferences<_$AppDatabase, $ItemsTable, Item> {
  $$ItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$EventItemsTable, List<EventItem>>
  _eventItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.eventItems,
    aliasName: 'items__id__event_items__item_id',
  );

  $$EventItemsTableProcessedTableManager get eventItemsRefs {
    final manager = $$EventItemsTableTableManager(
      $_db,
      $_db.eventItems,
    ).filter((f) => f.itemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_eventItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$InventoryMovementsTable, List<InventoryMovement>>
  _inventoryMovementsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.inventoryMovements,
        aliasName: 'items__id__inventory_movements__item_id',
      );

  $$InventoryMovementsTableProcessedTableManager get inventoryMovementsRefs {
    final manager = $$InventoryMovementsTableTableManager(
      $_db,
      $_db.inventoryMovements,
    ).filter((f) => f.itemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _inventoryMovementsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CloseoutLinesTable, List<CloseoutLine>>
  _closeoutLinesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.closeoutLines,
    aliasName: 'items__id__closeout_lines__item_id',
  );

  $$CloseoutLinesTableProcessedTableManager get closeoutLinesRefs {
    final manager = $$CloseoutLinesTableTableManager(
      $_db,
      $_db.closeoutLines,
    ).filter((f) => f.itemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_closeoutLinesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RecipesTable, List<Recipe>> _recipesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.recipes,
    aliasName: 'items__id__recipes__output_item_id',
  );

  $$RecipesTableProcessedTableManager get recipesRefs {
    final manager = $$RecipesTableTableManager(
      $_db,
      $_db.recipes,
    ).filter((f) => f.outputItemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_recipesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RecipeLinesTable, List<RecipeLine>>
  _recipeLinesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.recipeLines,
    aliasName: 'items__id__recipe_lines__ingredient_item_id',
  );

  $$RecipeLinesTableProcessedTableManager get recipeLinesRefs {
    final manager = $$RecipeLinesTableTableManager($_db, $_db.recipeLines)
        .filter(
          (f) => f.ingredientItemId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(_recipeLinesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ForecastLinesTable, List<ForecastLine>>
  _forecastLinesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.forecastLines,
    aliasName: 'items__id__forecast_lines__item_id',
  );

  $$ForecastLinesTableProcessedTableManager get forecastLinesRefs {
    final manager = $$ForecastLinesTableTableManager(
      $_db,
      $_db.forecastLines,
    ).filter((f) => f.itemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_forecastLinesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ForecastEvidenceTable, List<ForecastEvidenceData>>
  _forecastEvidenceRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.forecastEvidence,
    aliasName: 'items__id__forecast_evidence__item_id',
  );

  $$ForecastEvidenceTableProcessedTableManager get forecastEvidenceRefs {
    final manager = $$ForecastEvidenceTableTableManager(
      $_db,
      $_db.forecastEvidence,
    ).filter((f) => f.itemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _forecastEvidenceRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ForecastOverridesTable, List<ForecastOverride>>
  _forecastOverridesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.forecastOverrides,
        aliasName: 'items__id__forecast_overrides__item_id',
      );

  $$ForecastOverridesTableProcessedTableManager get forecastOverridesRefs {
    final manager = $$ForecastOverridesTableTableManager(
      $_db,
      $_db.forecastOverrides,
    ).filter((f) => f.itemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _forecastOverridesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ItemsTableFilterComposer extends Composer<_$AppDatabase, $ItemsTable> {
  $$ItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get packSizeMicros => $composableBuilder(
    column: $table.packSizeMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get archivedAtMicros => $composableBuilder(
    column: $table.archivedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> eventItemsRefs(
    Expression<bool> Function($$EventItemsTableFilterComposer f) f,
  ) {
    final $$EventItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.eventItems,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventItemsTableFilterComposer(
            $db: $db,
            $table: $db.eventItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> inventoryMovementsRefs(
    Expression<bool> Function($$InventoryMovementsTableFilterComposer f) f,
  ) {
    final $$InventoryMovementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.inventoryMovements,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryMovementsTableFilterComposer(
            $db: $db,
            $table: $db.inventoryMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> closeoutLinesRefs(
    Expression<bool> Function($$CloseoutLinesTableFilterComposer f) f,
  ) {
    final $$CloseoutLinesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.closeoutLines,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CloseoutLinesTableFilterComposer(
            $db: $db,
            $table: $db.closeoutLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> recipesRefs(
    Expression<bool> Function($$RecipesTableFilterComposer f) f,
  ) {
    final $$RecipesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.outputItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableFilterComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> recipeLinesRefs(
    Expression<bool> Function($$RecipeLinesTableFilterComposer f) f,
  ) {
    final $$RecipeLinesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipeLines,
      getReferencedColumn: (t) => t.ingredientItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeLinesTableFilterComposer(
            $db: $db,
            $table: $db.recipeLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> forecastLinesRefs(
    Expression<bool> Function($$ForecastLinesTableFilterComposer f) f,
  ) {
    final $$ForecastLinesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastLines,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastLinesTableFilterComposer(
            $db: $db,
            $table: $db.forecastLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> forecastEvidenceRefs(
    Expression<bool> Function($$ForecastEvidenceTableFilterComposer f) f,
  ) {
    final $$ForecastEvidenceTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastEvidence,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastEvidenceTableFilterComposer(
            $db: $db,
            $table: $db.forecastEvidence,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> forecastOverridesRefs(
    Expression<bool> Function($$ForecastOverridesTableFilterComposer f) f,
  ) {
    final $$ForecastOverridesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastOverrides,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastOverridesTableFilterComposer(
            $db: $db,
            $table: $db.forecastOverrides,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $ItemsTable> {
  $$ItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get packSizeMicros => $composableBuilder(
    column: $table.packSizeMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get archivedAtMicros => $composableBuilder(
    column: $table.archivedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ItemsTable> {
  $$ItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<int> get packSizeMicros => $composableBuilder(
    column: $table.packSizeMicros,
    builder: (column) => column,
  );

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get archivedAtMicros => $composableBuilder(
    column: $table.archivedAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => column,
  );

  Expression<T> eventItemsRefs<T extends Object>(
    Expression<T> Function($$EventItemsTableAnnotationComposer a) f,
  ) {
    final $$EventItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.eventItems,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.eventItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> inventoryMovementsRefs<T extends Object>(
    Expression<T> Function($$InventoryMovementsTableAnnotationComposer a) f,
  ) {
    final $$InventoryMovementsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.inventoryMovements,
          getReferencedColumn: (t) => t.itemId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$InventoryMovementsTableAnnotationComposer(
                $db: $db,
                $table: $db.inventoryMovements,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> closeoutLinesRefs<T extends Object>(
    Expression<T> Function($$CloseoutLinesTableAnnotationComposer a) f,
  ) {
    final $$CloseoutLinesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.closeoutLines,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CloseoutLinesTableAnnotationComposer(
            $db: $db,
            $table: $db.closeoutLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> recipesRefs<T extends Object>(
    Expression<T> Function($$RecipesTableAnnotationComposer a) f,
  ) {
    final $$RecipesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.outputItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableAnnotationComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> recipeLinesRefs<T extends Object>(
    Expression<T> Function($$RecipeLinesTableAnnotationComposer a) f,
  ) {
    final $$RecipeLinesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipeLines,
      getReferencedColumn: (t) => t.ingredientItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeLinesTableAnnotationComposer(
            $db: $db,
            $table: $db.recipeLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> forecastLinesRefs<T extends Object>(
    Expression<T> Function($$ForecastLinesTableAnnotationComposer a) f,
  ) {
    final $$ForecastLinesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastLines,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastLinesTableAnnotationComposer(
            $db: $db,
            $table: $db.forecastLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> forecastEvidenceRefs<T extends Object>(
    Expression<T> Function($$ForecastEvidenceTableAnnotationComposer a) f,
  ) {
    final $$ForecastEvidenceTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastEvidence,
      getReferencedColumn: (t) => t.itemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastEvidenceTableAnnotationComposer(
            $db: $db,
            $table: $db.forecastEvidence,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> forecastOverridesRefs<T extends Object>(
    Expression<T> Function($$ForecastOverridesTableAnnotationComposer a) f,
  ) {
    final $$ForecastOverridesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.forecastOverrides,
          getReferencedColumn: (t) => t.itemId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ForecastOverridesTableAnnotationComposer(
                $db: $db,
                $table: $db.forecastOverrides,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ItemsTable,
          Item,
          $$ItemsTableFilterComposer,
          $$ItemsTableOrderingComposer,
          $$ItemsTableAnnotationComposer,
          $$ItemsTableCreateCompanionBuilder,
          $$ItemsTableUpdateCompanionBuilder,
          (Item, $$ItemsTableReferences),
          Item,
          PrefetchHooks Function({
            bool eventItemsRefs,
            bool inventoryMovementsRefs,
            bool closeoutLinesRefs,
            bool recipesRefs,
            bool recipeLinesRefs,
            bool forecastLinesRefs,
            bool forecastEvidenceRefs,
            bool forecastOverridesRefs,
          })
        > {
  $$ItemsTableTableManager(_$AppDatabase db, $ItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<int> packSizeMicros = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<int?> archivedAtMicros = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> updatedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ItemsCompanion(
                id: id,
                name: name,
                unit: unit,
                packSizeMicros: packSizeMicros,
                category: category,
                notes: notes,
                archivedAtMicros: archivedAtMicros,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String unit,
                required int packSizeMicros,
                Value<String?> category = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<int?> archivedAtMicros = const Value.absent(),
                required int createdAtMicros,
                required int updatedAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => ItemsCompanion.insert(
                id: id,
                name: name,
                unit: unit,
                packSizeMicros: packSizeMicros,
                category: category,
                notes: notes,
                archivedAtMicros: archivedAtMicros,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$ItemsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                eventItemsRefs = false,
                inventoryMovementsRefs = false,
                closeoutLinesRefs = false,
                recipesRefs = false,
                recipeLinesRefs = false,
                forecastLinesRefs = false,
                forecastEvidenceRefs = false,
                forecastOverridesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (eventItemsRefs) db.eventItems,
                    if (inventoryMovementsRefs) db.inventoryMovements,
                    if (closeoutLinesRefs) db.closeoutLines,
                    if (recipesRefs) db.recipes,
                    if (recipeLinesRefs) db.recipeLines,
                    if (forecastLinesRefs) db.forecastLines,
                    if (forecastEvidenceRefs) db.forecastEvidence,
                    if (forecastOverridesRefs) db.forecastOverrides,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (eventItemsRefs)
                        await $_getPrefetchedData<Item, $ItemsTable, EventItem>(
                          currentTable: table,
                          referencedTable: $$ItemsTableReferences
                              ._eventItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).eventItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.itemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (inventoryMovementsRefs)
                        await $_getPrefetchedData<
                          Item,
                          $ItemsTable,
                          InventoryMovement
                        >(
                          currentTable: table,
                          referencedTable: $$ItemsTableReferences
                              ._inventoryMovementsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).inventoryMovementsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.itemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (closeoutLinesRefs)
                        await $_getPrefetchedData<
                          Item,
                          $ItemsTable,
                          CloseoutLine
                        >(
                          currentTable: table,
                          referencedTable: $$ItemsTableReferences
                              ._closeoutLinesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).closeoutLinesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.itemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (recipesRefs)
                        await $_getPrefetchedData<Item, $ItemsTable, Recipe>(
                          currentTable: table,
                          referencedTable: $$ItemsTableReferences
                              ._recipesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ItemsTableReferences(db, table, p0).recipesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.outputItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (recipeLinesRefs)
                        await $_getPrefetchedData<
                          Item,
                          $ItemsTable,
                          RecipeLine
                        >(
                          currentTable: table,
                          referencedTable: $$ItemsTableReferences
                              ._recipeLinesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).recipeLinesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ingredientItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (forecastLinesRefs)
                        await $_getPrefetchedData<
                          Item,
                          $ItemsTable,
                          ForecastLine
                        >(
                          currentTable: table,
                          referencedTable: $$ItemsTableReferences
                              ._forecastLinesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).forecastLinesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.itemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (forecastEvidenceRefs)
                        await $_getPrefetchedData<
                          Item,
                          $ItemsTable,
                          ForecastEvidenceData
                        >(
                          currentTable: table,
                          referencedTable: $$ItemsTableReferences
                              ._forecastEvidenceRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).forecastEvidenceRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.itemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (forecastOverridesRefs)
                        await $_getPrefetchedData<
                          Item,
                          $ItemsTable,
                          ForecastOverride
                        >(
                          currentTable: table,
                          referencedTable: $$ItemsTableReferences
                              ._forecastOverridesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).forecastOverridesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.itemId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ItemsTable,
      Item,
      $$ItemsTableFilterComposer,
      $$ItemsTableOrderingComposer,
      $$ItemsTableAnnotationComposer,
      $$ItemsTableCreateCompanionBuilder,
      $$ItemsTableUpdateCompanionBuilder,
      (Item, $$ItemsTableReferences),
      Item,
      PrefetchHooks Function({
        bool eventItemsRefs,
        bool inventoryMovementsRefs,
        bool closeoutLinesRefs,
        bool recipesRefs,
        bool recipeLinesRefs,
        bool forecastLinesRefs,
        bool forecastEvidenceRefs,
        bool forecastOverridesRefs,
      })
    >;
typedef $$EventsTableCreateCompanionBuilder =
    EventsCompanion Function({
      required String id,
      required String name,
      Value<String?> venue,
      required String scheduledDate,
      Value<int?> startsAtMicros,
      Value<int?> endsAtMicros,
      Value<String> status,
      Value<int?> plannedExposure,
      Value<int?> closedAtMicros,
      Value<String?> notes,
      required int createdAtMicros,
      required int updatedAtMicros,
      Value<int> rowid,
    });
typedef $$EventsTableUpdateCompanionBuilder =
    EventsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> venue,
      Value<String> scheduledDate,
      Value<int?> startsAtMicros,
      Value<int?> endsAtMicros,
      Value<String> status,
      Value<int?> plannedExposure,
      Value<int?> closedAtMicros,
      Value<String?> notes,
      Value<int> createdAtMicros,
      Value<int> updatedAtMicros,
      Value<int> rowid,
    });

final class $$EventsTableReferences
    extends BaseReferences<_$AppDatabase, $EventsTable, Event> {
  $$EventsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$EventItemsTable, List<EventItem>>
  _eventItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.eventItems,
    aliasName: 'events__id__event_items__event_id',
  );

  $$EventItemsTableProcessedTableManager get eventItemsRefs {
    final manager = $$EventItemsTableTableManager(
      $_db,
      $_db.eventItems,
    ).filter((f) => f.eventId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_eventItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$InventoryMovementsTable, List<InventoryMovement>>
  _inventoryMovementsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.inventoryMovements,
        aliasName: 'events__id__inventory_movements__event_id',
      );

  $$InventoryMovementsTableProcessedTableManager get inventoryMovementsRefs {
    final manager = $$InventoryMovementsTableTableManager(
      $_db,
      $_db.inventoryMovements,
    ).filter((f) => f.eventId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _inventoryMovementsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$EventCloseoutsTable, List<EventCloseout>>
  _eventCloseoutsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.eventCloseouts,
    aliasName: 'events__id__event_closeouts__event_id',
  );

  $$EventCloseoutsTableProcessedTableManager get eventCloseoutsRefs {
    final manager = $$EventCloseoutsTableTableManager(
      $_db,
      $_db.eventCloseouts,
    ).filter((f) => f.eventId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_eventCloseoutsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CloseoutDraftsTable, List<CloseoutDraft>>
  _closeoutDraftsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.closeoutDrafts,
    aliasName: 'events__id__closeout_drafts__event_id',
  );

  $$CloseoutDraftsTableProcessedTableManager get closeoutDraftsRefs {
    final manager = $$CloseoutDraftsTableTableManager(
      $_db,
      $_db.closeoutDrafts,
    ).filter((f) => f.eventId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_closeoutDraftsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ForecastSnapshotsTable, List<ForecastSnapshot>>
  _forecastSnapshotsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.forecastSnapshots,
        aliasName: 'events__id__forecast_snapshots__event_id',
      );

  $$ForecastSnapshotsTableProcessedTableManager get forecastSnapshotsRefs {
    final manager = $$ForecastSnapshotsTableTableManager(
      $_db,
      $_db.forecastSnapshots,
    ).filter((f) => f.eventId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _forecastSnapshotsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ForecastEvidenceTable, List<ForecastEvidenceData>>
  _forecastEvidenceRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.forecastEvidence,
    aliasName: 'events__id__forecast_evidence__source_event_id',
  );

  $$ForecastEvidenceTableProcessedTableManager get forecastEvidenceRefs {
    final manager = $$ForecastEvidenceTableTableManager(
      $_db,
      $_db.forecastEvidence,
    ).filter((f) => f.sourceEventId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _forecastEvidenceRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$EventsTableFilterComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get venue => $composableBuilder(
    column: $table.venue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scheduledDate => $composableBuilder(
    column: $table.scheduledDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startsAtMicros => $composableBuilder(
    column: $table.startsAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endsAtMicros => $composableBuilder(
    column: $table.endsAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get plannedExposure => $composableBuilder(
    column: $table.plannedExposure,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get closedAtMicros => $composableBuilder(
    column: $table.closedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> eventItemsRefs(
    Expression<bool> Function($$EventItemsTableFilterComposer f) f,
  ) {
    final $$EventItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.eventItems,
      getReferencedColumn: (t) => t.eventId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventItemsTableFilterComposer(
            $db: $db,
            $table: $db.eventItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> inventoryMovementsRefs(
    Expression<bool> Function($$InventoryMovementsTableFilterComposer f) f,
  ) {
    final $$InventoryMovementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.inventoryMovements,
      getReferencedColumn: (t) => t.eventId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryMovementsTableFilterComposer(
            $db: $db,
            $table: $db.inventoryMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> eventCloseoutsRefs(
    Expression<bool> Function($$EventCloseoutsTableFilterComposer f) f,
  ) {
    final $$EventCloseoutsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.eventCloseouts,
      getReferencedColumn: (t) => t.eventId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventCloseoutsTableFilterComposer(
            $db: $db,
            $table: $db.eventCloseouts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> closeoutDraftsRefs(
    Expression<bool> Function($$CloseoutDraftsTableFilterComposer f) f,
  ) {
    final $$CloseoutDraftsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.closeoutDrafts,
      getReferencedColumn: (t) => t.eventId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CloseoutDraftsTableFilterComposer(
            $db: $db,
            $table: $db.closeoutDrafts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> forecastSnapshotsRefs(
    Expression<bool> Function($$ForecastSnapshotsTableFilterComposer f) f,
  ) {
    final $$ForecastSnapshotsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastSnapshots,
      getReferencedColumn: (t) => t.eventId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastSnapshotsTableFilterComposer(
            $db: $db,
            $table: $db.forecastSnapshots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> forecastEvidenceRefs(
    Expression<bool> Function($$ForecastEvidenceTableFilterComposer f) f,
  ) {
    final $$ForecastEvidenceTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastEvidence,
      getReferencedColumn: (t) => t.sourceEventId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastEvidenceTableFilterComposer(
            $db: $db,
            $table: $db.forecastEvidence,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$EventsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get venue => $composableBuilder(
    column: $table.venue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scheduledDate => $composableBuilder(
    column: $table.scheduledDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startsAtMicros => $composableBuilder(
    column: $table.startsAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endsAtMicros => $composableBuilder(
    column: $table.endsAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get plannedExposure => $composableBuilder(
    column: $table.plannedExposure,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get closedAtMicros => $composableBuilder(
    column: $table.closedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get venue =>
      $composableBuilder(column: $table.venue, builder: (column) => column);

  GeneratedColumn<String> get scheduledDate => $composableBuilder(
    column: $table.scheduledDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startsAtMicros => $composableBuilder(
    column: $table.startsAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endsAtMicros => $composableBuilder(
    column: $table.endsAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get plannedExposure => $composableBuilder(
    column: $table.plannedExposure,
    builder: (column) => column,
  );

  GeneratedColumn<int> get closedAtMicros => $composableBuilder(
    column: $table.closedAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => column,
  );

  Expression<T> eventItemsRefs<T extends Object>(
    Expression<T> Function($$EventItemsTableAnnotationComposer a) f,
  ) {
    final $$EventItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.eventItems,
      getReferencedColumn: (t) => t.eventId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.eventItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> inventoryMovementsRefs<T extends Object>(
    Expression<T> Function($$InventoryMovementsTableAnnotationComposer a) f,
  ) {
    final $$InventoryMovementsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.inventoryMovements,
          getReferencedColumn: (t) => t.eventId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$InventoryMovementsTableAnnotationComposer(
                $db: $db,
                $table: $db.inventoryMovements,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> eventCloseoutsRefs<T extends Object>(
    Expression<T> Function($$EventCloseoutsTableAnnotationComposer a) f,
  ) {
    final $$EventCloseoutsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.eventCloseouts,
      getReferencedColumn: (t) => t.eventId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventCloseoutsTableAnnotationComposer(
            $db: $db,
            $table: $db.eventCloseouts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> closeoutDraftsRefs<T extends Object>(
    Expression<T> Function($$CloseoutDraftsTableAnnotationComposer a) f,
  ) {
    final $$CloseoutDraftsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.closeoutDrafts,
      getReferencedColumn: (t) => t.eventId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CloseoutDraftsTableAnnotationComposer(
            $db: $db,
            $table: $db.closeoutDrafts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> forecastSnapshotsRefs<T extends Object>(
    Expression<T> Function($$ForecastSnapshotsTableAnnotationComposer a) f,
  ) {
    final $$ForecastSnapshotsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.forecastSnapshots,
          getReferencedColumn: (t) => t.eventId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ForecastSnapshotsTableAnnotationComposer(
                $db: $db,
                $table: $db.forecastSnapshots,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> forecastEvidenceRefs<T extends Object>(
    Expression<T> Function($$ForecastEvidenceTableAnnotationComposer a) f,
  ) {
    final $$ForecastEvidenceTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastEvidence,
      getReferencedColumn: (t) => t.sourceEventId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastEvidenceTableAnnotationComposer(
            $db: $db,
            $table: $db.forecastEvidence,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$EventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventsTable,
          Event,
          $$EventsTableFilterComposer,
          $$EventsTableOrderingComposer,
          $$EventsTableAnnotationComposer,
          $$EventsTableCreateCompanionBuilder,
          $$EventsTableUpdateCompanionBuilder,
          (Event, $$EventsTableReferences),
          Event,
          PrefetchHooks Function({
            bool eventItemsRefs,
            bool inventoryMovementsRefs,
            bool eventCloseoutsRefs,
            bool closeoutDraftsRefs,
            bool forecastSnapshotsRefs,
            bool forecastEvidenceRefs,
          })
        > {
  $$EventsTableTableManager(_$AppDatabase db, $EventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> venue = const Value.absent(),
                Value<String> scheduledDate = const Value.absent(),
                Value<int?> startsAtMicros = const Value.absent(),
                Value<int?> endsAtMicros = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> plannedExposure = const Value.absent(),
                Value<int?> closedAtMicros = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> updatedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventsCompanion(
                id: id,
                name: name,
                venue: venue,
                scheduledDate: scheduledDate,
                startsAtMicros: startsAtMicros,
                endsAtMicros: endsAtMicros,
                status: status,
                plannedExposure: plannedExposure,
                closedAtMicros: closedAtMicros,
                notes: notes,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> venue = const Value.absent(),
                required String scheduledDate,
                Value<int?> startsAtMicros = const Value.absent(),
                Value<int?> endsAtMicros = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> plannedExposure = const Value.absent(),
                Value<int?> closedAtMicros = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                required int createdAtMicros,
                required int updatedAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => EventsCompanion.insert(
                id: id,
                name: name,
                venue: venue,
                scheduledDate: scheduledDate,
                startsAtMicros: startsAtMicros,
                endsAtMicros: endsAtMicros,
                status: status,
                plannedExposure: plannedExposure,
                closedAtMicros: closedAtMicros,
                notes: notes,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$EventsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                eventItemsRefs = false,
                inventoryMovementsRefs = false,
                eventCloseoutsRefs = false,
                closeoutDraftsRefs = false,
                forecastSnapshotsRefs = false,
                forecastEvidenceRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (eventItemsRefs) db.eventItems,
                    if (inventoryMovementsRefs) db.inventoryMovements,
                    if (eventCloseoutsRefs) db.eventCloseouts,
                    if (closeoutDraftsRefs) db.closeoutDrafts,
                    if (forecastSnapshotsRefs) db.forecastSnapshots,
                    if (forecastEvidenceRefs) db.forecastEvidence,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (eventItemsRefs)
                        await $_getPrefetchedData<
                          Event,
                          $EventsTable,
                          EventItem
                        >(
                          currentTable: table,
                          referencedTable: $$EventsTableReferences
                              ._eventItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$EventsTableReferences(
                                db,
                                table,
                                p0,
                              ).eventItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.eventId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (inventoryMovementsRefs)
                        await $_getPrefetchedData<
                          Event,
                          $EventsTable,
                          InventoryMovement
                        >(
                          currentTable: table,
                          referencedTable: $$EventsTableReferences
                              ._inventoryMovementsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$EventsTableReferences(
                                db,
                                table,
                                p0,
                              ).inventoryMovementsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.eventId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (eventCloseoutsRefs)
                        await $_getPrefetchedData<
                          Event,
                          $EventsTable,
                          EventCloseout
                        >(
                          currentTable: table,
                          referencedTable: $$EventsTableReferences
                              ._eventCloseoutsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$EventsTableReferences(
                                db,
                                table,
                                p0,
                              ).eventCloseoutsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.eventId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (closeoutDraftsRefs)
                        await $_getPrefetchedData<
                          Event,
                          $EventsTable,
                          CloseoutDraft
                        >(
                          currentTable: table,
                          referencedTable: $$EventsTableReferences
                              ._closeoutDraftsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$EventsTableReferences(
                                db,
                                table,
                                p0,
                              ).closeoutDraftsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.eventId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (forecastSnapshotsRefs)
                        await $_getPrefetchedData<
                          Event,
                          $EventsTable,
                          ForecastSnapshot
                        >(
                          currentTable: table,
                          referencedTable: $$EventsTableReferences
                              ._forecastSnapshotsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$EventsTableReferences(
                                db,
                                table,
                                p0,
                              ).forecastSnapshotsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.eventId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (forecastEvidenceRefs)
                        await $_getPrefetchedData<
                          Event,
                          $EventsTable,
                          ForecastEvidenceData
                        >(
                          currentTable: table,
                          referencedTable: $$EventsTableReferences
                              ._forecastEvidenceRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$EventsTableReferences(
                                db,
                                table,
                                p0,
                              ).forecastEvidenceRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sourceEventId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$EventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventsTable,
      Event,
      $$EventsTableFilterComposer,
      $$EventsTableOrderingComposer,
      $$EventsTableAnnotationComposer,
      $$EventsTableCreateCompanionBuilder,
      $$EventsTableUpdateCompanionBuilder,
      (Event, $$EventsTableReferences),
      Event,
      PrefetchHooks Function({
        bool eventItemsRefs,
        bool inventoryMovementsRefs,
        bool eventCloseoutsRefs,
        bool closeoutDraftsRefs,
        bool forecastSnapshotsRefs,
        bool forecastEvidenceRefs,
      })
    >;
typedef $$EventItemsTableCreateCompanionBuilder =
    EventItemsCompanion Function({
      required String eventId,
      required String itemId,
      required int position,
      Value<int> rowid,
    });
typedef $$EventItemsTableUpdateCompanionBuilder =
    EventItemsCompanion Function({
      Value<String> eventId,
      Value<String> itemId,
      Value<int> position,
      Value<int> rowid,
    });

final class $$EventItemsTableReferences
    extends BaseReferences<_$AppDatabase, $EventItemsTable, EventItem> {
  $$EventItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $EventsTable _eventIdTable(_$AppDatabase db) =>
      db.events.createAlias('event_items__event_id__events__id');

  $$EventsTableProcessedTableManager get eventId {
    final $_column = $_itemColumn<String>('event_id')!;

    final manager = $$EventsTableTableManager(
      $_db,
      $_db.events,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_eventIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ItemsTable _itemIdTable(_$AppDatabase db) =>
      db.items.createAlias('event_items__item_id__items__id');

  $$ItemsTableProcessedTableManager get itemId {
    final $_column = $_itemColumn<String>('item_id')!;

    final manager = $$ItemsTableTableManager(
      $_db,
      $_db.items,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_itemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EventItemsTableFilterComposer
    extends Composer<_$AppDatabase, $EventItemsTable> {
  $$EventItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  $$EventsTableFilterComposer get eventId {
    final $$EventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.eventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableFilterComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ItemsTableFilterComposer get itemId {
    final $$ItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableFilterComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EventItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventItemsTable> {
  $$EventItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  $$EventsTableOrderingComposer get eventId {
    final $$EventsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.eventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableOrderingComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ItemsTableOrderingComposer get itemId {
    final $$ItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableOrderingComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EventItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventItemsTable> {
  $$EventItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  $$EventsTableAnnotationComposer get eventId {
    final $$EventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.eventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableAnnotationComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ItemsTableAnnotationComposer get itemId {
    final $$ItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EventItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventItemsTable,
          EventItem,
          $$EventItemsTableFilterComposer,
          $$EventItemsTableOrderingComposer,
          $$EventItemsTableAnnotationComposer,
          $$EventItemsTableCreateCompanionBuilder,
          $$EventItemsTableUpdateCompanionBuilder,
          (EventItem, $$EventItemsTableReferences),
          EventItem,
          PrefetchHooks Function({bool eventId, bool itemId})
        > {
  $$EventItemsTableTableManager(_$AppDatabase db, $EventItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> eventId = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventItemsCompanion(
                eventId: eventId,
                itemId: itemId,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String eventId,
                required String itemId,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => EventItemsCompanion.insert(
                eventId: eventId,
                itemId: itemId,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EventItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({eventId = false, itemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (eventId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.eventId,
                                referencedTable: $$EventItemsTableReferences
                                    ._eventIdTable(db),
                                referencedColumn: $$EventItemsTableReferences
                                    ._eventIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (itemId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.itemId,
                                referencedTable: $$EventItemsTableReferences
                                    ._itemIdTable(db),
                                referencedColumn: $$EventItemsTableReferences
                                    ._itemIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$EventItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventItemsTable,
      EventItem,
      $$EventItemsTableFilterComposer,
      $$EventItemsTableOrderingComposer,
      $$EventItemsTableAnnotationComposer,
      $$EventItemsTableCreateCompanionBuilder,
      $$EventItemsTableUpdateCompanionBuilder,
      (EventItem, $$EventItemsTableReferences),
      EventItem,
      PrefetchHooks Function({bool eventId, bool itemId})
    >;
typedef $$InventoryMovementsTableCreateCompanionBuilder =
    InventoryMovementsCompanion Function({
      required String id,
      required String itemId,
      required String kind,
      required int deltaMicros,
      Value<String?> eventId,
      Value<String?> reversesMovementId,
      required String sourceCommandId,
      required int occurredAtMicros,
      required int recordedAtMicros,
      Value<String> note,
      Value<int> rowid,
    });
typedef $$InventoryMovementsTableUpdateCompanionBuilder =
    InventoryMovementsCompanion Function({
      Value<String> id,
      Value<String> itemId,
      Value<String> kind,
      Value<int> deltaMicros,
      Value<String?> eventId,
      Value<String?> reversesMovementId,
      Value<String> sourceCommandId,
      Value<int> occurredAtMicros,
      Value<int> recordedAtMicros,
      Value<String> note,
      Value<int> rowid,
    });

final class $$InventoryMovementsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $InventoryMovementsTable,
          InventoryMovement
        > {
  $$InventoryMovementsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ItemsTable _itemIdTable(_$AppDatabase db) =>
      db.items.createAlias('inventory_movements__item_id__items__id');

  $$ItemsTableProcessedTableManager get itemId {
    final $_column = $_itemColumn<String>('item_id')!;

    final manager = $$ItemsTableTableManager(
      $_db,
      $_db.items,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_itemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $EventsTable _eventIdTable(_$AppDatabase db) =>
      db.events.createAlias('inventory_movements__event_id__events__id');

  $$EventsTableProcessedTableManager? get eventId {
    final $_column = $_itemColumn<String>('event_id');
    if ($_column == null) return null;
    final manager = $$EventsTableTableManager(
      $_db,
      $_db.events,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_eventIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $InventoryMovementsTable _reversesMovementIdTable(_$AppDatabase db) =>
      db.inventoryMovements.createAlias(
        'inventory_movements__reverses_movement_id__inventory_movements__id',
      );

  $$InventoryMovementsTableProcessedTableManager? get reversesMovementId {
    final $_column = $_itemColumn<String>('reverses_movement_id');
    if ($_column == null) return null;
    final manager = $$InventoryMovementsTableTableManager(
      $_db,
      $_db.inventoryMovements,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_reversesMovementIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CommandsTable _sourceCommandIdTable(_$AppDatabase db) => db.commands
      .createAlias('inventory_movements__source_command_id__commands__id');

  $$CommandsTableProcessedTableManager get sourceCommandId {
    final $_column = $_itemColumn<String>('source_command_id')!;

    final manager = $$CommandsTableTableManager(
      $_db,
      $_db.commands,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceCommandIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$InventoryMovementsTableFilterComposer
    extends Composer<_$AppDatabase, $InventoryMovementsTable> {
  $$InventoryMovementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deltaMicros => $composableBuilder(
    column: $table.deltaMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get occurredAtMicros => $composableBuilder(
    column: $table.occurredAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recordedAtMicros => $composableBuilder(
    column: $table.recordedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  $$ItemsTableFilterComposer get itemId {
    final $$ItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableFilterComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EventsTableFilterComposer get eventId {
    final $$EventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.eventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableFilterComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$InventoryMovementsTableFilterComposer get reversesMovementId {
    final $$InventoryMovementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.reversesMovementId,
      referencedTable: $db.inventoryMovements,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryMovementsTableFilterComposer(
            $db: $db,
            $table: $db.inventoryMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CommandsTableFilterComposer get sourceCommandId {
    final $$CommandsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceCommandId,
      referencedTable: $db.commands,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CommandsTableFilterComposer(
            $db: $db,
            $table: $db.commands,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InventoryMovementsTableOrderingComposer
    extends Composer<_$AppDatabase, $InventoryMovementsTable> {
  $$InventoryMovementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deltaMicros => $composableBuilder(
    column: $table.deltaMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurredAtMicros => $composableBuilder(
    column: $table.occurredAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recordedAtMicros => $composableBuilder(
    column: $table.recordedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  $$ItemsTableOrderingComposer get itemId {
    final $$ItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableOrderingComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EventsTableOrderingComposer get eventId {
    final $$EventsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.eventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableOrderingComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$InventoryMovementsTableOrderingComposer get reversesMovementId {
    final $$InventoryMovementsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.reversesMovementId,
      referencedTable: $db.inventoryMovements,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryMovementsTableOrderingComposer(
            $db: $db,
            $table: $db.inventoryMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CommandsTableOrderingComposer get sourceCommandId {
    final $$CommandsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceCommandId,
      referencedTable: $db.commands,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CommandsTableOrderingComposer(
            $db: $db,
            $table: $db.commands,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InventoryMovementsTableAnnotationComposer
    extends Composer<_$AppDatabase, $InventoryMovementsTable> {
  $$InventoryMovementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get deltaMicros => $composableBuilder(
    column: $table.deltaMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get occurredAtMicros => $composableBuilder(
    column: $table.occurredAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recordedAtMicros => $composableBuilder(
    column: $table.recordedAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  $$ItemsTableAnnotationComposer get itemId {
    final $$ItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EventsTableAnnotationComposer get eventId {
    final $$EventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.eventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableAnnotationComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$InventoryMovementsTableAnnotationComposer get reversesMovementId {
    final $$InventoryMovementsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.reversesMovementId,
          referencedTable: $db.inventoryMovements,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$InventoryMovementsTableAnnotationComposer(
                $db: $db,
                $table: $db.inventoryMovements,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$CommandsTableAnnotationComposer get sourceCommandId {
    final $$CommandsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceCommandId,
      referencedTable: $db.commands,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CommandsTableAnnotationComposer(
            $db: $db,
            $table: $db.commands,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InventoryMovementsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InventoryMovementsTable,
          InventoryMovement,
          $$InventoryMovementsTableFilterComposer,
          $$InventoryMovementsTableOrderingComposer,
          $$InventoryMovementsTableAnnotationComposer,
          $$InventoryMovementsTableCreateCompanionBuilder,
          $$InventoryMovementsTableUpdateCompanionBuilder,
          (InventoryMovement, $$InventoryMovementsTableReferences),
          InventoryMovement,
          PrefetchHooks Function({
            bool itemId,
            bool eventId,
            bool reversesMovementId,
            bool sourceCommandId,
          })
        > {
  $$InventoryMovementsTableTableManager(
    _$AppDatabase db,
    $InventoryMovementsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InventoryMovementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InventoryMovementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InventoryMovementsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> deltaMicros = const Value.absent(),
                Value<String?> eventId = const Value.absent(),
                Value<String?> reversesMovementId = const Value.absent(),
                Value<String> sourceCommandId = const Value.absent(),
                Value<int> occurredAtMicros = const Value.absent(),
                Value<int> recordedAtMicros = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryMovementsCompanion(
                id: id,
                itemId: itemId,
                kind: kind,
                deltaMicros: deltaMicros,
                eventId: eventId,
                reversesMovementId: reversesMovementId,
                sourceCommandId: sourceCommandId,
                occurredAtMicros: occurredAtMicros,
                recordedAtMicros: recordedAtMicros,
                note: note,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String itemId,
                required String kind,
                required int deltaMicros,
                Value<String?> eventId = const Value.absent(),
                Value<String?> reversesMovementId = const Value.absent(),
                required String sourceCommandId,
                required int occurredAtMicros,
                required int recordedAtMicros,
                Value<String> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryMovementsCompanion.insert(
                id: id,
                itemId: itemId,
                kind: kind,
                deltaMicros: deltaMicros,
                eventId: eventId,
                reversesMovementId: reversesMovementId,
                sourceCommandId: sourceCommandId,
                occurredAtMicros: occurredAtMicros,
                recordedAtMicros: recordedAtMicros,
                note: note,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$InventoryMovementsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                itemId = false,
                eventId = false,
                reversesMovementId = false,
                sourceCommandId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (itemId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.itemId,
                                    referencedTable:
                                        $$InventoryMovementsTableReferences
                                            ._itemIdTable(db),
                                    referencedColumn:
                                        $$InventoryMovementsTableReferences
                                            ._itemIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (eventId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.eventId,
                                    referencedTable:
                                        $$InventoryMovementsTableReferences
                                            ._eventIdTable(db),
                                    referencedColumn:
                                        $$InventoryMovementsTableReferences
                                            ._eventIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (reversesMovementId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.reversesMovementId,
                                    referencedTable:
                                        $$InventoryMovementsTableReferences
                                            ._reversesMovementIdTable(db),
                                    referencedColumn:
                                        $$InventoryMovementsTableReferences
                                            ._reversesMovementIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (sourceCommandId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.sourceCommandId,
                                    referencedTable:
                                        $$InventoryMovementsTableReferences
                                            ._sourceCommandIdTable(db),
                                    referencedColumn:
                                        $$InventoryMovementsTableReferences
                                            ._sourceCommandIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$InventoryMovementsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InventoryMovementsTable,
      InventoryMovement,
      $$InventoryMovementsTableFilterComposer,
      $$InventoryMovementsTableOrderingComposer,
      $$InventoryMovementsTableAnnotationComposer,
      $$InventoryMovementsTableCreateCompanionBuilder,
      $$InventoryMovementsTableUpdateCompanionBuilder,
      (InventoryMovement, $$InventoryMovementsTableReferences),
      InventoryMovement,
      PrefetchHooks Function({
        bool itemId,
        bool eventId,
        bool reversesMovementId,
        bool sourceCommandId,
      })
    >;
typedef $$EventCloseoutsTableCreateCompanionBuilder =
    EventCloseoutsCompanion Function({
      required String id,
      required String eventId,
      required int revision,
      Value<String?> supersedesCloseoutId,
      required int confirmedExposure,
      Value<String> note,
      required String sourceCommandId,
      required int confirmedAtMicros,
      Value<int> rowid,
    });
typedef $$EventCloseoutsTableUpdateCompanionBuilder =
    EventCloseoutsCompanion Function({
      Value<String> id,
      Value<String> eventId,
      Value<int> revision,
      Value<String?> supersedesCloseoutId,
      Value<int> confirmedExposure,
      Value<String> note,
      Value<String> sourceCommandId,
      Value<int> confirmedAtMicros,
      Value<int> rowid,
    });

final class $$EventCloseoutsTableReferences
    extends BaseReferences<_$AppDatabase, $EventCloseoutsTable, EventCloseout> {
  $$EventCloseoutsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $EventsTable _eventIdTable(_$AppDatabase db) =>
      db.events.createAlias('event_closeouts__event_id__events__id');

  $$EventsTableProcessedTableManager get eventId {
    final $_column = $_itemColumn<String>('event_id')!;

    final manager = $$EventsTableTableManager(
      $_db,
      $_db.events,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_eventIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $EventCloseoutsTable _supersedesCloseoutIdTable(_$AppDatabase db) =>
      db.eventCloseouts.createAlias(
        'event_closeouts__supersedes_closeout_id__event_closeouts__id',
      );

  $$EventCloseoutsTableProcessedTableManager? get supersedesCloseoutId {
    final $_column = $_itemColumn<String>('supersedes_closeout_id');
    if ($_column == null) return null;
    final manager = $$EventCloseoutsTableTableManager(
      $_db,
      $_db.eventCloseouts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(
      _supersedesCloseoutIdTable($_db),
    );
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CommandsTable _sourceCommandIdTable(_$AppDatabase db) => db.commands
      .createAlias('event_closeouts__source_command_id__commands__id');

  $$CommandsTableProcessedTableManager get sourceCommandId {
    final $_column = $_itemColumn<String>('source_command_id')!;

    final manager = $$CommandsTableTableManager(
      $_db,
      $_db.commands,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceCommandIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$CloseoutLinesTable, List<CloseoutLine>>
  _closeoutLinesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.closeoutLines,
    aliasName: 'event_closeouts__id__closeout_lines__closeout_id',
  );

  $$CloseoutLinesTableProcessedTableManager get closeoutLinesRefs {
    final manager = $$CloseoutLinesTableTableManager(
      $_db,
      $_db.closeoutLines,
    ).filter((f) => f.closeoutId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_closeoutLinesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ForecastEvidenceTable, List<ForecastEvidenceData>>
  _forecastEvidenceRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.forecastEvidence,
    aliasName: 'event_closeouts__id__forecast_evidence__closeout_id',
  );

  $$ForecastEvidenceTableProcessedTableManager get forecastEvidenceRefs {
    final manager = $$ForecastEvidenceTableTableManager(
      $_db,
      $_db.forecastEvidence,
    ).filter((f) => f.closeoutId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _forecastEvidenceRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$EventCloseoutsTableFilterComposer
    extends Composer<_$AppDatabase, $EventCloseoutsTable> {
  $$EventCloseoutsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get confirmedExposure => $composableBuilder(
    column: $table.confirmedExposure,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get confirmedAtMicros => $composableBuilder(
    column: $table.confirmedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$EventsTableFilterComposer get eventId {
    final $$EventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.eventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableFilterComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EventCloseoutsTableFilterComposer get supersedesCloseoutId {
    final $$EventCloseoutsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supersedesCloseoutId,
      referencedTable: $db.eventCloseouts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventCloseoutsTableFilterComposer(
            $db: $db,
            $table: $db.eventCloseouts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CommandsTableFilterComposer get sourceCommandId {
    final $$CommandsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceCommandId,
      referencedTable: $db.commands,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CommandsTableFilterComposer(
            $db: $db,
            $table: $db.commands,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> closeoutLinesRefs(
    Expression<bool> Function($$CloseoutLinesTableFilterComposer f) f,
  ) {
    final $$CloseoutLinesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.closeoutLines,
      getReferencedColumn: (t) => t.closeoutId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CloseoutLinesTableFilterComposer(
            $db: $db,
            $table: $db.closeoutLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> forecastEvidenceRefs(
    Expression<bool> Function($$ForecastEvidenceTableFilterComposer f) f,
  ) {
    final $$ForecastEvidenceTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastEvidence,
      getReferencedColumn: (t) => t.closeoutId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastEvidenceTableFilterComposer(
            $db: $db,
            $table: $db.forecastEvidence,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$EventCloseoutsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventCloseoutsTable> {
  $$EventCloseoutsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get confirmedExposure => $composableBuilder(
    column: $table.confirmedExposure,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get confirmedAtMicros => $composableBuilder(
    column: $table.confirmedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$EventsTableOrderingComposer get eventId {
    final $$EventsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.eventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableOrderingComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EventCloseoutsTableOrderingComposer get supersedesCloseoutId {
    final $$EventCloseoutsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supersedesCloseoutId,
      referencedTable: $db.eventCloseouts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventCloseoutsTableOrderingComposer(
            $db: $db,
            $table: $db.eventCloseouts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CommandsTableOrderingComposer get sourceCommandId {
    final $$CommandsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceCommandId,
      referencedTable: $db.commands,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CommandsTableOrderingComposer(
            $db: $db,
            $table: $db.commands,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EventCloseoutsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventCloseoutsTable> {
  $$EventCloseoutsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get confirmedExposure => $composableBuilder(
    column: $table.confirmedExposure,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get confirmedAtMicros => $composableBuilder(
    column: $table.confirmedAtMicros,
    builder: (column) => column,
  );

  $$EventsTableAnnotationComposer get eventId {
    final $$EventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.eventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableAnnotationComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EventCloseoutsTableAnnotationComposer get supersedesCloseoutId {
    final $$EventCloseoutsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.supersedesCloseoutId,
      referencedTable: $db.eventCloseouts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventCloseoutsTableAnnotationComposer(
            $db: $db,
            $table: $db.eventCloseouts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CommandsTableAnnotationComposer get sourceCommandId {
    final $$CommandsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceCommandId,
      referencedTable: $db.commands,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CommandsTableAnnotationComposer(
            $db: $db,
            $table: $db.commands,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> closeoutLinesRefs<T extends Object>(
    Expression<T> Function($$CloseoutLinesTableAnnotationComposer a) f,
  ) {
    final $$CloseoutLinesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.closeoutLines,
      getReferencedColumn: (t) => t.closeoutId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CloseoutLinesTableAnnotationComposer(
            $db: $db,
            $table: $db.closeoutLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> forecastEvidenceRefs<T extends Object>(
    Expression<T> Function($$ForecastEvidenceTableAnnotationComposer a) f,
  ) {
    final $$ForecastEvidenceTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastEvidence,
      getReferencedColumn: (t) => t.closeoutId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastEvidenceTableAnnotationComposer(
            $db: $db,
            $table: $db.forecastEvidence,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$EventCloseoutsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventCloseoutsTable,
          EventCloseout,
          $$EventCloseoutsTableFilterComposer,
          $$EventCloseoutsTableOrderingComposer,
          $$EventCloseoutsTableAnnotationComposer,
          $$EventCloseoutsTableCreateCompanionBuilder,
          $$EventCloseoutsTableUpdateCompanionBuilder,
          (EventCloseout, $$EventCloseoutsTableReferences),
          EventCloseout,
          PrefetchHooks Function({
            bool eventId,
            bool supersedesCloseoutId,
            bool sourceCommandId,
            bool closeoutLinesRefs,
            bool forecastEvidenceRefs,
          })
        > {
  $$EventCloseoutsTableTableManager(
    _$AppDatabase db,
    $EventCloseoutsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventCloseoutsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventCloseoutsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventCloseoutsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<String?> supersedesCloseoutId = const Value.absent(),
                Value<int> confirmedExposure = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String> sourceCommandId = const Value.absent(),
                Value<int> confirmedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventCloseoutsCompanion(
                id: id,
                eventId: eventId,
                revision: revision,
                supersedesCloseoutId: supersedesCloseoutId,
                confirmedExposure: confirmedExposure,
                note: note,
                sourceCommandId: sourceCommandId,
                confirmedAtMicros: confirmedAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String eventId,
                required int revision,
                Value<String?> supersedesCloseoutId = const Value.absent(),
                required int confirmedExposure,
                Value<String> note = const Value.absent(),
                required String sourceCommandId,
                required int confirmedAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => EventCloseoutsCompanion.insert(
                id: id,
                eventId: eventId,
                revision: revision,
                supersedesCloseoutId: supersedesCloseoutId,
                confirmedExposure: confirmedExposure,
                note: note,
                sourceCommandId: sourceCommandId,
                confirmedAtMicros: confirmedAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EventCloseoutsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                eventId = false,
                supersedesCloseoutId = false,
                sourceCommandId = false,
                closeoutLinesRefs = false,
                forecastEvidenceRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (closeoutLinesRefs) db.closeoutLines,
                    if (forecastEvidenceRefs) db.forecastEvidence,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (eventId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.eventId,
                                    referencedTable:
                                        $$EventCloseoutsTableReferences
                                            ._eventIdTable(db),
                                    referencedColumn:
                                        $$EventCloseoutsTableReferences
                                            ._eventIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (supersedesCloseoutId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.supersedesCloseoutId,
                                    referencedTable:
                                        $$EventCloseoutsTableReferences
                                            ._supersedesCloseoutIdTable(db),
                                    referencedColumn:
                                        $$EventCloseoutsTableReferences
                                            ._supersedesCloseoutIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (sourceCommandId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.sourceCommandId,
                                    referencedTable:
                                        $$EventCloseoutsTableReferences
                                            ._sourceCommandIdTable(db),
                                    referencedColumn:
                                        $$EventCloseoutsTableReferences
                                            ._sourceCommandIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (closeoutLinesRefs)
                        await $_getPrefetchedData<
                          EventCloseout,
                          $EventCloseoutsTable,
                          CloseoutLine
                        >(
                          currentTable: table,
                          referencedTable: $$EventCloseoutsTableReferences
                              ._closeoutLinesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$EventCloseoutsTableReferences(
                                db,
                                table,
                                p0,
                              ).closeoutLinesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.closeoutId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (forecastEvidenceRefs)
                        await $_getPrefetchedData<
                          EventCloseout,
                          $EventCloseoutsTable,
                          ForecastEvidenceData
                        >(
                          currentTable: table,
                          referencedTable: $$EventCloseoutsTableReferences
                              ._forecastEvidenceRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$EventCloseoutsTableReferences(
                                db,
                                table,
                                p0,
                              ).forecastEvidenceRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.closeoutId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$EventCloseoutsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventCloseoutsTable,
      EventCloseout,
      $$EventCloseoutsTableFilterComposer,
      $$EventCloseoutsTableOrderingComposer,
      $$EventCloseoutsTableAnnotationComposer,
      $$EventCloseoutsTableCreateCompanionBuilder,
      $$EventCloseoutsTableUpdateCompanionBuilder,
      (EventCloseout, $$EventCloseoutsTableReferences),
      EventCloseout,
      PrefetchHooks Function({
        bool eventId,
        bool supersedesCloseoutId,
        bool sourceCommandId,
        bool closeoutLinesRefs,
        bool forecastEvidenceRefs,
      })
    >;
typedef $$CloseoutLinesTableCreateCompanionBuilder =
    CloseoutLinesCompanion Function({
      required String closeoutId,
      required String itemId,
      Value<int?> loadedMicros,
      Value<int?> returnedMicros,
      Value<int?> wasteMicros,
      required int depletionMicros,
      Value<bool> stockout,
      Value<bool> approximate,
      Value<String?> consumptionMovementId,
      Value<String?> wasteMovementId,
      Value<int> rowid,
    });
typedef $$CloseoutLinesTableUpdateCompanionBuilder =
    CloseoutLinesCompanion Function({
      Value<String> closeoutId,
      Value<String> itemId,
      Value<int?> loadedMicros,
      Value<int?> returnedMicros,
      Value<int?> wasteMicros,
      Value<int> depletionMicros,
      Value<bool> stockout,
      Value<bool> approximate,
      Value<String?> consumptionMovementId,
      Value<String?> wasteMovementId,
      Value<int> rowid,
    });

final class $$CloseoutLinesTableReferences
    extends BaseReferences<_$AppDatabase, $CloseoutLinesTable, CloseoutLine> {
  $$CloseoutLinesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $EventCloseoutsTable _closeoutIdTable(_$AppDatabase db) => db
      .eventCloseouts
      .createAlias('closeout_lines__closeout_id__event_closeouts__id');

  $$EventCloseoutsTableProcessedTableManager get closeoutId {
    final $_column = $_itemColumn<String>('closeout_id')!;

    final manager = $$EventCloseoutsTableTableManager(
      $_db,
      $_db.eventCloseouts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_closeoutIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ItemsTable _itemIdTable(_$AppDatabase db) =>
      db.items.createAlias('closeout_lines__item_id__items__id');

  $$ItemsTableProcessedTableManager get itemId {
    final $_column = $_itemColumn<String>('item_id')!;

    final manager = $$ItemsTableTableManager(
      $_db,
      $_db.items,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_itemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $InventoryMovementsTable _consumptionMovementIdTable(
    _$AppDatabase db,
  ) => db.inventoryMovements.createAlias(
    'closeout_lines__consumption_movement_id__inventory_movements__id',
  );

  $$InventoryMovementsTableProcessedTableManager? get consumptionMovementId {
    final $_column = $_itemColumn<String>('consumption_movement_id');
    if ($_column == null) return null;
    final manager = $$InventoryMovementsTableTableManager(
      $_db,
      $_db.inventoryMovements,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(
      _consumptionMovementIdTable($_db),
    );
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $InventoryMovementsTable _wasteMovementIdTable(_$AppDatabase db) =>
      db.inventoryMovements.createAlias(
        'closeout_lines__waste_movement_id__inventory_movements__id',
      );

  $$InventoryMovementsTableProcessedTableManager? get wasteMovementId {
    final $_column = $_itemColumn<String>('waste_movement_id');
    if ($_column == null) return null;
    final manager = $$InventoryMovementsTableTableManager(
      $_db,
      $_db.inventoryMovements,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_wasteMovementIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CloseoutLinesTableFilterComposer
    extends Composer<_$AppDatabase, $CloseoutLinesTable> {
  $$CloseoutLinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get loadedMicros => $composableBuilder(
    column: $table.loadedMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get returnedMicros => $composableBuilder(
    column: $table.returnedMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wasteMicros => $composableBuilder(
    column: $table.wasteMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get depletionMicros => $composableBuilder(
    column: $table.depletionMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get stockout => $composableBuilder(
    column: $table.stockout,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get approximate => $composableBuilder(
    column: $table.approximate,
    builder: (column) => ColumnFilters(column),
  );

  $$EventCloseoutsTableFilterComposer get closeoutId {
    final $$EventCloseoutsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.closeoutId,
      referencedTable: $db.eventCloseouts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventCloseoutsTableFilterComposer(
            $db: $db,
            $table: $db.eventCloseouts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ItemsTableFilterComposer get itemId {
    final $$ItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableFilterComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$InventoryMovementsTableFilterComposer get consumptionMovementId {
    final $$InventoryMovementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.consumptionMovementId,
      referencedTable: $db.inventoryMovements,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryMovementsTableFilterComposer(
            $db: $db,
            $table: $db.inventoryMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$InventoryMovementsTableFilterComposer get wasteMovementId {
    final $$InventoryMovementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wasteMovementId,
      referencedTable: $db.inventoryMovements,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryMovementsTableFilterComposer(
            $db: $db,
            $table: $db.inventoryMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CloseoutLinesTableOrderingComposer
    extends Composer<_$AppDatabase, $CloseoutLinesTable> {
  $$CloseoutLinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get loadedMicros => $composableBuilder(
    column: $table.loadedMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get returnedMicros => $composableBuilder(
    column: $table.returnedMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wasteMicros => $composableBuilder(
    column: $table.wasteMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get depletionMicros => $composableBuilder(
    column: $table.depletionMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get stockout => $composableBuilder(
    column: $table.stockout,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get approximate => $composableBuilder(
    column: $table.approximate,
    builder: (column) => ColumnOrderings(column),
  );

  $$EventCloseoutsTableOrderingComposer get closeoutId {
    final $$EventCloseoutsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.closeoutId,
      referencedTable: $db.eventCloseouts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventCloseoutsTableOrderingComposer(
            $db: $db,
            $table: $db.eventCloseouts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ItemsTableOrderingComposer get itemId {
    final $$ItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableOrderingComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$InventoryMovementsTableOrderingComposer get consumptionMovementId {
    final $$InventoryMovementsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.consumptionMovementId,
      referencedTable: $db.inventoryMovements,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryMovementsTableOrderingComposer(
            $db: $db,
            $table: $db.inventoryMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$InventoryMovementsTableOrderingComposer get wasteMovementId {
    final $$InventoryMovementsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.wasteMovementId,
      referencedTable: $db.inventoryMovements,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryMovementsTableOrderingComposer(
            $db: $db,
            $table: $db.inventoryMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CloseoutLinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CloseoutLinesTable> {
  $$CloseoutLinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get loadedMicros => $composableBuilder(
    column: $table.loadedMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get returnedMicros => $composableBuilder(
    column: $table.returnedMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get wasteMicros => $composableBuilder(
    column: $table.wasteMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get depletionMicros => $composableBuilder(
    column: $table.depletionMicros,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get stockout =>
      $composableBuilder(column: $table.stockout, builder: (column) => column);

  GeneratedColumn<bool> get approximate => $composableBuilder(
    column: $table.approximate,
    builder: (column) => column,
  );

  $$EventCloseoutsTableAnnotationComposer get closeoutId {
    final $$EventCloseoutsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.closeoutId,
      referencedTable: $db.eventCloseouts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventCloseoutsTableAnnotationComposer(
            $db: $db,
            $table: $db.eventCloseouts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ItemsTableAnnotationComposer get itemId {
    final $$ItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$InventoryMovementsTableAnnotationComposer get consumptionMovementId {
    final $$InventoryMovementsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.consumptionMovementId,
          referencedTable: $db.inventoryMovements,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$InventoryMovementsTableAnnotationComposer(
                $db: $db,
                $table: $db.inventoryMovements,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$InventoryMovementsTableAnnotationComposer get wasteMovementId {
    final $$InventoryMovementsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.wasteMovementId,
          referencedTable: $db.inventoryMovements,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$InventoryMovementsTableAnnotationComposer(
                $db: $db,
                $table: $db.inventoryMovements,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$CloseoutLinesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CloseoutLinesTable,
          CloseoutLine,
          $$CloseoutLinesTableFilterComposer,
          $$CloseoutLinesTableOrderingComposer,
          $$CloseoutLinesTableAnnotationComposer,
          $$CloseoutLinesTableCreateCompanionBuilder,
          $$CloseoutLinesTableUpdateCompanionBuilder,
          (CloseoutLine, $$CloseoutLinesTableReferences),
          CloseoutLine,
          PrefetchHooks Function({
            bool closeoutId,
            bool itemId,
            bool consumptionMovementId,
            bool wasteMovementId,
          })
        > {
  $$CloseoutLinesTableTableManager(_$AppDatabase db, $CloseoutLinesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CloseoutLinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CloseoutLinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CloseoutLinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> closeoutId = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<int?> loadedMicros = const Value.absent(),
                Value<int?> returnedMicros = const Value.absent(),
                Value<int?> wasteMicros = const Value.absent(),
                Value<int> depletionMicros = const Value.absent(),
                Value<bool> stockout = const Value.absent(),
                Value<bool> approximate = const Value.absent(),
                Value<String?> consumptionMovementId = const Value.absent(),
                Value<String?> wasteMovementId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CloseoutLinesCompanion(
                closeoutId: closeoutId,
                itemId: itemId,
                loadedMicros: loadedMicros,
                returnedMicros: returnedMicros,
                wasteMicros: wasteMicros,
                depletionMicros: depletionMicros,
                stockout: stockout,
                approximate: approximate,
                consumptionMovementId: consumptionMovementId,
                wasteMovementId: wasteMovementId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String closeoutId,
                required String itemId,
                Value<int?> loadedMicros = const Value.absent(),
                Value<int?> returnedMicros = const Value.absent(),
                Value<int?> wasteMicros = const Value.absent(),
                required int depletionMicros,
                Value<bool> stockout = const Value.absent(),
                Value<bool> approximate = const Value.absent(),
                Value<String?> consumptionMovementId = const Value.absent(),
                Value<String?> wasteMovementId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CloseoutLinesCompanion.insert(
                closeoutId: closeoutId,
                itemId: itemId,
                loadedMicros: loadedMicros,
                returnedMicros: returnedMicros,
                wasteMicros: wasteMicros,
                depletionMicros: depletionMicros,
                stockout: stockout,
                approximate: approximate,
                consumptionMovementId: consumptionMovementId,
                wasteMovementId: wasteMovementId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CloseoutLinesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                closeoutId = false,
                itemId = false,
                consumptionMovementId = false,
                wasteMovementId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (closeoutId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.closeoutId,
                                    referencedTable:
                                        $$CloseoutLinesTableReferences
                                            ._closeoutIdTable(db),
                                    referencedColumn:
                                        $$CloseoutLinesTableReferences
                                            ._closeoutIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (itemId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.itemId,
                                    referencedTable:
                                        $$CloseoutLinesTableReferences
                                            ._itemIdTable(db),
                                    referencedColumn:
                                        $$CloseoutLinesTableReferences
                                            ._itemIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (consumptionMovementId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.consumptionMovementId,
                                    referencedTable:
                                        $$CloseoutLinesTableReferences
                                            ._consumptionMovementIdTable(db),
                                    referencedColumn:
                                        $$CloseoutLinesTableReferences
                                            ._consumptionMovementIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (wasteMovementId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.wasteMovementId,
                                    referencedTable:
                                        $$CloseoutLinesTableReferences
                                            ._wasteMovementIdTable(db),
                                    referencedColumn:
                                        $$CloseoutLinesTableReferences
                                            ._wasteMovementIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$CloseoutLinesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CloseoutLinesTable,
      CloseoutLine,
      $$CloseoutLinesTableFilterComposer,
      $$CloseoutLinesTableOrderingComposer,
      $$CloseoutLinesTableAnnotationComposer,
      $$CloseoutLinesTableCreateCompanionBuilder,
      $$CloseoutLinesTableUpdateCompanionBuilder,
      (CloseoutLine, $$CloseoutLinesTableReferences),
      CloseoutLine,
      PrefetchHooks Function({
        bool closeoutId,
        bool itemId,
        bool consumptionMovementId,
        bool wasteMovementId,
      })
    >;
typedef $$CloseoutDraftsTableCreateCompanionBuilder =
    CloseoutDraftsCompanion Function({
      required String eventId,
      required String payloadJson,
      required int updatedAtMicros,
      Value<int> rowid,
    });
typedef $$CloseoutDraftsTableUpdateCompanionBuilder =
    CloseoutDraftsCompanion Function({
      Value<String> eventId,
      Value<String> payloadJson,
      Value<int> updatedAtMicros,
      Value<int> rowid,
    });

final class $$CloseoutDraftsTableReferences
    extends BaseReferences<_$AppDatabase, $CloseoutDraftsTable, CloseoutDraft> {
  $$CloseoutDraftsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $EventsTable _eventIdTable(_$AppDatabase db) =>
      db.events.createAlias('closeout_drafts__event_id__events__id');

  $$EventsTableProcessedTableManager get eventId {
    final $_column = $_itemColumn<String>('event_id')!;

    final manager = $$EventsTableTableManager(
      $_db,
      $_db.events,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_eventIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CloseoutDraftsTableFilterComposer
    extends Composer<_$AppDatabase, $CloseoutDraftsTable> {
  $$CloseoutDraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$EventsTableFilterComposer get eventId {
    final $$EventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.eventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableFilterComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CloseoutDraftsTableOrderingComposer
    extends Composer<_$AppDatabase, $CloseoutDraftsTable> {
  $$CloseoutDraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$EventsTableOrderingComposer get eventId {
    final $$EventsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.eventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableOrderingComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CloseoutDraftsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CloseoutDraftsTable> {
  $$CloseoutDraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => column,
  );

  $$EventsTableAnnotationComposer get eventId {
    final $$EventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.eventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableAnnotationComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CloseoutDraftsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CloseoutDraftsTable,
          CloseoutDraft,
          $$CloseoutDraftsTableFilterComposer,
          $$CloseoutDraftsTableOrderingComposer,
          $$CloseoutDraftsTableAnnotationComposer,
          $$CloseoutDraftsTableCreateCompanionBuilder,
          $$CloseoutDraftsTableUpdateCompanionBuilder,
          (CloseoutDraft, $$CloseoutDraftsTableReferences),
          CloseoutDraft,
          PrefetchHooks Function({bool eventId})
        > {
  $$CloseoutDraftsTableTableManager(
    _$AppDatabase db,
    $CloseoutDraftsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CloseoutDraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CloseoutDraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CloseoutDraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> eventId = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> updatedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CloseoutDraftsCompanion(
                eventId: eventId,
                payloadJson: payloadJson,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String eventId,
                required String payloadJson,
                required int updatedAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => CloseoutDraftsCompanion.insert(
                eventId: eventId,
                payloadJson: payloadJson,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CloseoutDraftsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({eventId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (eventId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.eventId,
                                referencedTable: $$CloseoutDraftsTableReferences
                                    ._eventIdTable(db),
                                referencedColumn:
                                    $$CloseoutDraftsTableReferences
                                        ._eventIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CloseoutDraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CloseoutDraftsTable,
      CloseoutDraft,
      $$CloseoutDraftsTableFilterComposer,
      $$CloseoutDraftsTableOrderingComposer,
      $$CloseoutDraftsTableAnnotationComposer,
      $$CloseoutDraftsTableCreateCompanionBuilder,
      $$CloseoutDraftsTableUpdateCompanionBuilder,
      (CloseoutDraft, $$CloseoutDraftsTableReferences),
      CloseoutDraft,
      PrefetchHooks Function({bool eventId})
    >;
typedef $$RecipesTableCreateCompanionBuilder =
    RecipesCompanion Function({
      required String id,
      required String outputItemId,
      required String name,
      Value<int?> archivedAtMicros,
      required int createdAtMicros,
      Value<int> rowid,
    });
typedef $$RecipesTableUpdateCompanionBuilder =
    RecipesCompanion Function({
      Value<String> id,
      Value<String> outputItemId,
      Value<String> name,
      Value<int?> archivedAtMicros,
      Value<int> createdAtMicros,
      Value<int> rowid,
    });

final class $$RecipesTableReferences
    extends BaseReferences<_$AppDatabase, $RecipesTable, Recipe> {
  $$RecipesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ItemsTable _outputItemIdTable(_$AppDatabase db) =>
      db.items.createAlias('recipes__output_item_id__items__id');

  $$ItemsTableProcessedTableManager get outputItemId {
    final $_column = $_itemColumn<String>('output_item_id')!;

    final manager = $$ItemsTableTableManager(
      $_db,
      $_db.items,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_outputItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$RecipeRevisionsTable, List<RecipeRevision>>
  _recipeRevisionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.recipeRevisions,
    aliasName: 'recipes__id__recipe_revisions__recipe_id',
  );

  $$RecipeRevisionsTableProcessedTableManager get recipeRevisionsRefs {
    final manager = $$RecipeRevisionsTableTableManager(
      $_db,
      $_db.recipeRevisions,
    ).filter((f) => f.recipeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _recipeRevisionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$RecipesTableFilterComposer
    extends Composer<_$AppDatabase, $RecipesTable> {
  $$RecipesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get archivedAtMicros => $composableBuilder(
    column: $table.archivedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$ItemsTableFilterComposer get outputItemId {
    final $$ItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.outputItemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableFilterComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> recipeRevisionsRefs(
    Expression<bool> Function($$RecipeRevisionsTableFilterComposer f) f,
  ) {
    final $$RecipeRevisionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipeRevisions,
      getReferencedColumn: (t) => t.recipeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeRevisionsTableFilterComposer(
            $db: $db,
            $table: $db.recipeRevisions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RecipesTableOrderingComposer
    extends Composer<_$AppDatabase, $RecipesTable> {
  $$RecipesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get archivedAtMicros => $composableBuilder(
    column: $table.archivedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$ItemsTableOrderingComposer get outputItemId {
    final $$ItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.outputItemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableOrderingComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecipesTable> {
  $$RecipesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get archivedAtMicros => $composableBuilder(
    column: $table.archivedAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  $$ItemsTableAnnotationComposer get outputItemId {
    final $$ItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.outputItemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> recipeRevisionsRefs<T extends Object>(
    Expression<T> Function($$RecipeRevisionsTableAnnotationComposer a) f,
  ) {
    final $$RecipeRevisionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipeRevisions,
      getReferencedColumn: (t) => t.recipeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeRevisionsTableAnnotationComposer(
            $db: $db,
            $table: $db.recipeRevisions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RecipesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecipesTable,
          Recipe,
          $$RecipesTableFilterComposer,
          $$RecipesTableOrderingComposer,
          $$RecipesTableAnnotationComposer,
          $$RecipesTableCreateCompanionBuilder,
          $$RecipesTableUpdateCompanionBuilder,
          (Recipe, $$RecipesTableReferences),
          Recipe,
          PrefetchHooks Function({bool outputItemId, bool recipeRevisionsRefs})
        > {
  $$RecipesTableTableManager(_$AppDatabase db, $RecipesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecipesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecipesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecipesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> outputItemId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int?> archivedAtMicros = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecipesCompanion(
                id: id,
                outputItemId: outputItemId,
                name: name,
                archivedAtMicros: archivedAtMicros,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String outputItemId,
                required String name,
                Value<int?> archivedAtMicros = const Value.absent(),
                required int createdAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => RecipesCompanion.insert(
                id: id,
                outputItemId: outputItemId,
                name: name,
                archivedAtMicros: archivedAtMicros,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RecipesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({outputItemId = false, recipeRevisionsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (recipeRevisionsRefs) db.recipeRevisions,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (outputItemId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.outputItemId,
                                    referencedTable: $$RecipesTableReferences
                                        ._outputItemIdTable(db),
                                    referencedColumn: $$RecipesTableReferences
                                        ._outputItemIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (recipeRevisionsRefs)
                        await $_getPrefetchedData<
                          Recipe,
                          $RecipesTable,
                          RecipeRevision
                        >(
                          currentTable: table,
                          referencedTable: $$RecipesTableReferences
                              ._recipeRevisionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RecipesTableReferences(
                                db,
                                table,
                                p0,
                              ).recipeRevisionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.recipeId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$RecipesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecipesTable,
      Recipe,
      $$RecipesTableFilterComposer,
      $$RecipesTableOrderingComposer,
      $$RecipesTableAnnotationComposer,
      $$RecipesTableCreateCompanionBuilder,
      $$RecipesTableUpdateCompanionBuilder,
      (Recipe, $$RecipesTableReferences),
      Recipe,
      PrefetchHooks Function({bool outputItemId, bool recipeRevisionsRefs})
    >;
typedef $$RecipeRevisionsTableCreateCompanionBuilder =
    RecipeRevisionsCompanion Function({
      required String id,
      required String recipeId,
      required int revision,
      required int yieldMicros,
      Value<String?> yieldLabel,
      required String sourceKind,
      Value<String> note,
      required int createdAtMicros,
      Value<int> rowid,
    });
typedef $$RecipeRevisionsTableUpdateCompanionBuilder =
    RecipeRevisionsCompanion Function({
      Value<String> id,
      Value<String> recipeId,
      Value<int> revision,
      Value<int> yieldMicros,
      Value<String?> yieldLabel,
      Value<String> sourceKind,
      Value<String> note,
      Value<int> createdAtMicros,
      Value<int> rowid,
    });

final class $$RecipeRevisionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $RecipeRevisionsTable, RecipeRevision> {
  $$RecipeRevisionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $RecipesTable _recipeIdTable(_$AppDatabase db) =>
      db.recipes.createAlias('recipe_revisions__recipe_id__recipes__id');

  $$RecipesTableProcessedTableManager get recipeId {
    final $_column = $_itemColumn<String>('recipe_id')!;

    final manager = $$RecipesTableTableManager(
      $_db,
      $_db.recipes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recipeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$RecipeLinesTable, List<RecipeLine>>
  _recipeLinesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.recipeLines,
    aliasName: 'recipe_revisions__id__recipe_lines__revision_id',
  );

  $$RecipeLinesTableProcessedTableManager get recipeLinesRefs {
    final manager = $$RecipeLinesTableTableManager(
      $_db,
      $_db.recipeLines,
    ).filter((f) => f.revisionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_recipeLinesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$RecipeRevisionsTableFilterComposer
    extends Composer<_$AppDatabase, $RecipeRevisionsTable> {
  $$RecipeRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get yieldMicros => $composableBuilder(
    column: $table.yieldMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get yieldLabel => $composableBuilder(
    column: $table.yieldLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$RecipesTableFilterComposer get recipeId {
    final $$RecipesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableFilterComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> recipeLinesRefs(
    Expression<bool> Function($$RecipeLinesTableFilterComposer f) f,
  ) {
    final $$RecipeLinesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipeLines,
      getReferencedColumn: (t) => t.revisionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeLinesTableFilterComposer(
            $db: $db,
            $table: $db.recipeLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RecipeRevisionsTableOrderingComposer
    extends Composer<_$AppDatabase, $RecipeRevisionsTable> {
  $$RecipeRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get yieldMicros => $composableBuilder(
    column: $table.yieldMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get yieldLabel => $composableBuilder(
    column: $table.yieldLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$RecipesTableOrderingComposer get recipeId {
    final $$RecipesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableOrderingComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeRevisionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecipeRevisionsTable> {
  $$RecipeRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get yieldMicros => $composableBuilder(
    column: $table.yieldMicros,
    builder: (column) => column,
  );

  GeneratedColumn<String> get yieldLabel => $composableBuilder(
    column: $table.yieldLabel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  $$RecipesTableAnnotationComposer get recipeId {
    final $$RecipesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.recipeId,
      referencedTable: $db.recipes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipesTableAnnotationComposer(
            $db: $db,
            $table: $db.recipes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> recipeLinesRefs<T extends Object>(
    Expression<T> Function($$RecipeLinesTableAnnotationComposer a) f,
  ) {
    final $$RecipeLinesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.recipeLines,
      getReferencedColumn: (t) => t.revisionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeLinesTableAnnotationComposer(
            $db: $db,
            $table: $db.recipeLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RecipeRevisionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecipeRevisionsTable,
          RecipeRevision,
          $$RecipeRevisionsTableFilterComposer,
          $$RecipeRevisionsTableOrderingComposer,
          $$RecipeRevisionsTableAnnotationComposer,
          $$RecipeRevisionsTableCreateCompanionBuilder,
          $$RecipeRevisionsTableUpdateCompanionBuilder,
          (RecipeRevision, $$RecipeRevisionsTableReferences),
          RecipeRevision,
          PrefetchHooks Function({bool recipeId, bool recipeLinesRefs})
        > {
  $$RecipeRevisionsTableTableManager(
    _$AppDatabase db,
    $RecipeRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecipeRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecipeRevisionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecipeRevisionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> recipeId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> yieldMicros = const Value.absent(),
                Value<String?> yieldLabel = const Value.absent(),
                Value<String> sourceKind = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecipeRevisionsCompanion(
                id: id,
                recipeId: recipeId,
                revision: revision,
                yieldMicros: yieldMicros,
                yieldLabel: yieldLabel,
                sourceKind: sourceKind,
                note: note,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String recipeId,
                required int revision,
                required int yieldMicros,
                Value<String?> yieldLabel = const Value.absent(),
                required String sourceKind,
                Value<String> note = const Value.absent(),
                required int createdAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => RecipeRevisionsCompanion.insert(
                id: id,
                recipeId: recipeId,
                revision: revision,
                yieldMicros: yieldMicros,
                yieldLabel: yieldLabel,
                sourceKind: sourceKind,
                note: note,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RecipeRevisionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({recipeId = false, recipeLinesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (recipeLinesRefs) db.recipeLines],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (recipeId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.recipeId,
                                referencedTable:
                                    $$RecipeRevisionsTableReferences
                                        ._recipeIdTable(db),
                                referencedColumn:
                                    $$RecipeRevisionsTableReferences
                                        ._recipeIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (recipeLinesRefs)
                    await $_getPrefetchedData<
                      RecipeRevision,
                      $RecipeRevisionsTable,
                      RecipeLine
                    >(
                      currentTable: table,
                      referencedTable: $$RecipeRevisionsTableReferences
                          ._recipeLinesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$RecipeRevisionsTableReferences(
                            db,
                            table,
                            p0,
                          ).recipeLinesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.revisionId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$RecipeRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecipeRevisionsTable,
      RecipeRevision,
      $$RecipeRevisionsTableFilterComposer,
      $$RecipeRevisionsTableOrderingComposer,
      $$RecipeRevisionsTableAnnotationComposer,
      $$RecipeRevisionsTableCreateCompanionBuilder,
      $$RecipeRevisionsTableUpdateCompanionBuilder,
      (RecipeRevision, $$RecipeRevisionsTableReferences),
      RecipeRevision,
      PrefetchHooks Function({bool recipeId, bool recipeLinesRefs})
    >;
typedef $$RecipeLinesTableCreateCompanionBuilder =
    RecipeLinesCompanion Function({
      required String revisionId,
      required int lineIndex,
      required String ingredientItemId,
      required int quantityPerBatchMicros,
      Value<int> rowid,
    });
typedef $$RecipeLinesTableUpdateCompanionBuilder =
    RecipeLinesCompanion Function({
      Value<String> revisionId,
      Value<int> lineIndex,
      Value<String> ingredientItemId,
      Value<int> quantityPerBatchMicros,
      Value<int> rowid,
    });

final class $$RecipeLinesTableReferences
    extends BaseReferences<_$AppDatabase, $RecipeLinesTable, RecipeLine> {
  $$RecipeLinesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $RecipeRevisionsTable _revisionIdTable(_$AppDatabase db) => db
      .recipeRevisions
      .createAlias('recipe_lines__revision_id__recipe_revisions__id');

  $$RecipeRevisionsTableProcessedTableManager get revisionId {
    final $_column = $_itemColumn<String>('revision_id')!;

    final manager = $$RecipeRevisionsTableTableManager(
      $_db,
      $_db.recipeRevisions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_revisionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ItemsTable _ingredientItemIdTable(_$AppDatabase db) =>
      db.items.createAlias('recipe_lines__ingredient_item_id__items__id');

  $$ItemsTableProcessedTableManager get ingredientItemId {
    final $_column = $_itemColumn<String>('ingredient_item_id')!;

    final manager = $$ItemsTableTableManager(
      $_db,
      $_db.items,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ingredientItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RecipeLinesTableFilterComposer
    extends Composer<_$AppDatabase, $RecipeLinesTable> {
  $$RecipeLinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get lineIndex => $composableBuilder(
    column: $table.lineIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantityPerBatchMicros => $composableBuilder(
    column: $table.quantityPerBatchMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$RecipeRevisionsTableFilterComposer get revisionId {
    final $$RecipeRevisionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.revisionId,
      referencedTable: $db.recipeRevisions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeRevisionsTableFilterComposer(
            $db: $db,
            $table: $db.recipeRevisions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ItemsTableFilterComposer get ingredientItemId {
    final $$ItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ingredientItemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableFilterComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeLinesTableOrderingComposer
    extends Composer<_$AppDatabase, $RecipeLinesTable> {
  $$RecipeLinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get lineIndex => $composableBuilder(
    column: $table.lineIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantityPerBatchMicros => $composableBuilder(
    column: $table.quantityPerBatchMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$RecipeRevisionsTableOrderingComposer get revisionId {
    final $$RecipeRevisionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.revisionId,
      referencedTable: $db.recipeRevisions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeRevisionsTableOrderingComposer(
            $db: $db,
            $table: $db.recipeRevisions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ItemsTableOrderingComposer get ingredientItemId {
    final $$ItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ingredientItemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableOrderingComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeLinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecipeLinesTable> {
  $$RecipeLinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get lineIndex =>
      $composableBuilder(column: $table.lineIndex, builder: (column) => column);

  GeneratedColumn<int> get quantityPerBatchMicros => $composableBuilder(
    column: $table.quantityPerBatchMicros,
    builder: (column) => column,
  );

  $$RecipeRevisionsTableAnnotationComposer get revisionId {
    final $$RecipeRevisionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.revisionId,
      referencedTable: $db.recipeRevisions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RecipeRevisionsTableAnnotationComposer(
            $db: $db,
            $table: $db.recipeRevisions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ItemsTableAnnotationComposer get ingredientItemId {
    final $$ItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ingredientItemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RecipeLinesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecipeLinesTable,
          RecipeLine,
          $$RecipeLinesTableFilterComposer,
          $$RecipeLinesTableOrderingComposer,
          $$RecipeLinesTableAnnotationComposer,
          $$RecipeLinesTableCreateCompanionBuilder,
          $$RecipeLinesTableUpdateCompanionBuilder,
          (RecipeLine, $$RecipeLinesTableReferences),
          RecipeLine,
          PrefetchHooks Function({bool revisionId, bool ingredientItemId})
        > {
  $$RecipeLinesTableTableManager(_$AppDatabase db, $RecipeLinesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecipeLinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecipeLinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecipeLinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> revisionId = const Value.absent(),
                Value<int> lineIndex = const Value.absent(),
                Value<String> ingredientItemId = const Value.absent(),
                Value<int> quantityPerBatchMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecipeLinesCompanion(
                revisionId: revisionId,
                lineIndex: lineIndex,
                ingredientItemId: ingredientItemId,
                quantityPerBatchMicros: quantityPerBatchMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String revisionId,
                required int lineIndex,
                required String ingredientItemId,
                required int quantityPerBatchMicros,
                Value<int> rowid = const Value.absent(),
              }) => RecipeLinesCompanion.insert(
                revisionId: revisionId,
                lineIndex: lineIndex,
                ingredientItemId: ingredientItemId,
                quantityPerBatchMicros: quantityPerBatchMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RecipeLinesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({revisionId = false, ingredientItemId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (revisionId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.revisionId,
                                    referencedTable:
                                        $$RecipeLinesTableReferences
                                            ._revisionIdTable(db),
                                    referencedColumn:
                                        $$RecipeLinesTableReferences
                                            ._revisionIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (ingredientItemId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.ingredientItemId,
                                    referencedTable:
                                        $$RecipeLinesTableReferences
                                            ._ingredientItemIdTable(db),
                                    referencedColumn:
                                        $$RecipeLinesTableReferences
                                            ._ingredientItemIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$RecipeLinesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecipeLinesTable,
      RecipeLine,
      $$RecipeLinesTableFilterComposer,
      $$RecipeLinesTableOrderingComposer,
      $$RecipeLinesTableAnnotationComposer,
      $$RecipeLinesTableCreateCompanionBuilder,
      $$RecipeLinesTableUpdateCompanionBuilder,
      (RecipeLine, $$RecipeLinesTableReferences),
      RecipeLine,
      PrefetchHooks Function({bool revisionId, bool ingredientItemId})
    >;
typedef $$ForecastSnapshotsTableCreateCompanionBuilder =
    ForecastSnapshotsCompanion Function({
      required String id,
      required String eventId,
      required String method,
      required int methodVersion,
      required String policy,
      required int upcomingExposure,
      required int historyWindow,
      required String inputsHash,
      Value<String> assumptionsJson,
      required String sourceCommandId,
      required int createdAtMicros,
      Value<int> rowid,
    });
typedef $$ForecastSnapshotsTableUpdateCompanionBuilder =
    ForecastSnapshotsCompanion Function({
      Value<String> id,
      Value<String> eventId,
      Value<String> method,
      Value<int> methodVersion,
      Value<String> policy,
      Value<int> upcomingExposure,
      Value<int> historyWindow,
      Value<String> inputsHash,
      Value<String> assumptionsJson,
      Value<String> sourceCommandId,
      Value<int> createdAtMicros,
      Value<int> rowid,
    });

final class $$ForecastSnapshotsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ForecastSnapshotsTable,
          ForecastSnapshot
        > {
  $$ForecastSnapshotsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $EventsTable _eventIdTable(_$AppDatabase db) =>
      db.events.createAlias('forecast_snapshots__event_id__events__id');

  $$EventsTableProcessedTableManager get eventId {
    final $_column = $_itemColumn<String>('event_id')!;

    final manager = $$EventsTableTableManager(
      $_db,
      $_db.events,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_eventIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $CommandsTable _sourceCommandIdTable(_$AppDatabase db) => db.commands
      .createAlias('forecast_snapshots__source_command_id__commands__id');

  $$CommandsTableProcessedTableManager get sourceCommandId {
    final $_column = $_itemColumn<String>('source_command_id')!;

    final manager = $$CommandsTableTableManager(
      $_db,
      $_db.commands,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceCommandIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ForecastLinesTable, List<ForecastLine>>
  _forecastLinesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.forecastLines,
    aliasName: 'forecast_snapshots__id__forecast_lines__snapshot_id',
  );

  $$ForecastLinesTableProcessedTableManager get forecastLinesRefs {
    final manager = $$ForecastLinesTableTableManager(
      $_db,
      $_db.forecastLines,
    ).filter((f) => f.snapshotId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_forecastLinesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ForecastEvidenceTable, List<ForecastEvidenceData>>
  _forecastEvidenceRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.forecastEvidence,
    aliasName: 'forecast_snapshots__id__forecast_evidence__snapshot_id',
  );

  $$ForecastEvidenceTableProcessedTableManager get forecastEvidenceRefs {
    final manager = $$ForecastEvidenceTableTableManager(
      $_db,
      $_db.forecastEvidence,
    ).filter((f) => f.snapshotId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _forecastEvidenceRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ForecastOverridesTable, List<ForecastOverride>>
  _forecastOverridesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.forecastOverrides,
        aliasName: 'forecast_snapshots__id__forecast_overrides__snapshot_id',
      );

  $$ForecastOverridesTableProcessedTableManager get forecastOverridesRefs {
    final manager = $$ForecastOverridesTableTableManager(
      $_db,
      $_db.forecastOverrides,
    ).filter((f) => f.snapshotId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _forecastOverridesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ForecastSnapshotsTableFilterComposer
    extends Composer<_$AppDatabase, $ForecastSnapshotsTable> {
  $$ForecastSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get methodVersion => $composableBuilder(
    column: $table.methodVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get policy => $composableBuilder(
    column: $table.policy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get upcomingExposure => $composableBuilder(
    column: $table.upcomingExposure,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get historyWindow => $composableBuilder(
    column: $table.historyWindow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inputsHash => $composableBuilder(
    column: $table.inputsHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assumptionsJson => $composableBuilder(
    column: $table.assumptionsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$EventsTableFilterComposer get eventId {
    final $$EventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.eventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableFilterComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CommandsTableFilterComposer get sourceCommandId {
    final $$CommandsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceCommandId,
      referencedTable: $db.commands,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CommandsTableFilterComposer(
            $db: $db,
            $table: $db.commands,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> forecastLinesRefs(
    Expression<bool> Function($$ForecastLinesTableFilterComposer f) f,
  ) {
    final $$ForecastLinesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastLines,
      getReferencedColumn: (t) => t.snapshotId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastLinesTableFilterComposer(
            $db: $db,
            $table: $db.forecastLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> forecastEvidenceRefs(
    Expression<bool> Function($$ForecastEvidenceTableFilterComposer f) f,
  ) {
    final $$ForecastEvidenceTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastEvidence,
      getReferencedColumn: (t) => t.snapshotId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastEvidenceTableFilterComposer(
            $db: $db,
            $table: $db.forecastEvidence,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> forecastOverridesRefs(
    Expression<bool> Function($$ForecastOverridesTableFilterComposer f) f,
  ) {
    final $$ForecastOverridesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastOverrides,
      getReferencedColumn: (t) => t.snapshotId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastOverridesTableFilterComposer(
            $db: $db,
            $table: $db.forecastOverrides,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ForecastSnapshotsTableOrderingComposer
    extends Composer<_$AppDatabase, $ForecastSnapshotsTable> {
  $$ForecastSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get methodVersion => $composableBuilder(
    column: $table.methodVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get policy => $composableBuilder(
    column: $table.policy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get upcomingExposure => $composableBuilder(
    column: $table.upcomingExposure,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get historyWindow => $composableBuilder(
    column: $table.historyWindow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputsHash => $composableBuilder(
    column: $table.inputsHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assumptionsJson => $composableBuilder(
    column: $table.assumptionsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$EventsTableOrderingComposer get eventId {
    final $$EventsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.eventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableOrderingComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CommandsTableOrderingComposer get sourceCommandId {
    final $$CommandsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceCommandId,
      referencedTable: $db.commands,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CommandsTableOrderingComposer(
            $db: $db,
            $table: $db.commands,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ForecastSnapshotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ForecastSnapshotsTable> {
  $$ForecastSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<int> get methodVersion => $composableBuilder(
    column: $table.methodVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get policy =>
      $composableBuilder(column: $table.policy, builder: (column) => column);

  GeneratedColumn<int> get upcomingExposure => $composableBuilder(
    column: $table.upcomingExposure,
    builder: (column) => column,
  );

  GeneratedColumn<int> get historyWindow => $composableBuilder(
    column: $table.historyWindow,
    builder: (column) => column,
  );

  GeneratedColumn<String> get inputsHash => $composableBuilder(
    column: $table.inputsHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get assumptionsJson => $composableBuilder(
    column: $table.assumptionsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  $$EventsTableAnnotationComposer get eventId {
    final $$EventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.eventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableAnnotationComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$CommandsTableAnnotationComposer get sourceCommandId {
    final $$CommandsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceCommandId,
      referencedTable: $db.commands,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CommandsTableAnnotationComposer(
            $db: $db,
            $table: $db.commands,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> forecastLinesRefs<T extends Object>(
    Expression<T> Function($$ForecastLinesTableAnnotationComposer a) f,
  ) {
    final $$ForecastLinesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastLines,
      getReferencedColumn: (t) => t.snapshotId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastLinesTableAnnotationComposer(
            $db: $db,
            $table: $db.forecastLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> forecastEvidenceRefs<T extends Object>(
    Expression<T> Function($$ForecastEvidenceTableAnnotationComposer a) f,
  ) {
    final $$ForecastEvidenceTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.forecastEvidence,
      getReferencedColumn: (t) => t.snapshotId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastEvidenceTableAnnotationComposer(
            $db: $db,
            $table: $db.forecastEvidence,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> forecastOverridesRefs<T extends Object>(
    Expression<T> Function($$ForecastOverridesTableAnnotationComposer a) f,
  ) {
    final $$ForecastOverridesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.forecastOverrides,
          getReferencedColumn: (t) => t.snapshotId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ForecastOverridesTableAnnotationComposer(
                $db: $db,
                $table: $db.forecastOverrides,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ForecastSnapshotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ForecastSnapshotsTable,
          ForecastSnapshot,
          $$ForecastSnapshotsTableFilterComposer,
          $$ForecastSnapshotsTableOrderingComposer,
          $$ForecastSnapshotsTableAnnotationComposer,
          $$ForecastSnapshotsTableCreateCompanionBuilder,
          $$ForecastSnapshotsTableUpdateCompanionBuilder,
          (ForecastSnapshot, $$ForecastSnapshotsTableReferences),
          ForecastSnapshot,
          PrefetchHooks Function({
            bool eventId,
            bool sourceCommandId,
            bool forecastLinesRefs,
            bool forecastEvidenceRefs,
            bool forecastOverridesRefs,
          })
        > {
  $$ForecastSnapshotsTableTableManager(
    _$AppDatabase db,
    $ForecastSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ForecastSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ForecastSnapshotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ForecastSnapshotsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<String> method = const Value.absent(),
                Value<int> methodVersion = const Value.absent(),
                Value<String> policy = const Value.absent(),
                Value<int> upcomingExposure = const Value.absent(),
                Value<int> historyWindow = const Value.absent(),
                Value<String> inputsHash = const Value.absent(),
                Value<String> assumptionsJson = const Value.absent(),
                Value<String> sourceCommandId = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ForecastSnapshotsCompanion(
                id: id,
                eventId: eventId,
                method: method,
                methodVersion: methodVersion,
                policy: policy,
                upcomingExposure: upcomingExposure,
                historyWindow: historyWindow,
                inputsHash: inputsHash,
                assumptionsJson: assumptionsJson,
                sourceCommandId: sourceCommandId,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String eventId,
                required String method,
                required int methodVersion,
                required String policy,
                required int upcomingExposure,
                required int historyWindow,
                required String inputsHash,
                Value<String> assumptionsJson = const Value.absent(),
                required String sourceCommandId,
                required int createdAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => ForecastSnapshotsCompanion.insert(
                id: id,
                eventId: eventId,
                method: method,
                methodVersion: methodVersion,
                policy: policy,
                upcomingExposure: upcomingExposure,
                historyWindow: historyWindow,
                inputsHash: inputsHash,
                assumptionsJson: assumptionsJson,
                sourceCommandId: sourceCommandId,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ForecastSnapshotsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                eventId = false,
                sourceCommandId = false,
                forecastLinesRefs = false,
                forecastEvidenceRefs = false,
                forecastOverridesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (forecastLinesRefs) db.forecastLines,
                    if (forecastEvidenceRefs) db.forecastEvidence,
                    if (forecastOverridesRefs) db.forecastOverrides,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (eventId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.eventId,
                                    referencedTable:
                                        $$ForecastSnapshotsTableReferences
                                            ._eventIdTable(db),
                                    referencedColumn:
                                        $$ForecastSnapshotsTableReferences
                                            ._eventIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (sourceCommandId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.sourceCommandId,
                                    referencedTable:
                                        $$ForecastSnapshotsTableReferences
                                            ._sourceCommandIdTable(db),
                                    referencedColumn:
                                        $$ForecastSnapshotsTableReferences
                                            ._sourceCommandIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (forecastLinesRefs)
                        await $_getPrefetchedData<
                          ForecastSnapshot,
                          $ForecastSnapshotsTable,
                          ForecastLine
                        >(
                          currentTable: table,
                          referencedTable: $$ForecastSnapshotsTableReferences
                              ._forecastLinesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ForecastSnapshotsTableReferences(
                                db,
                                table,
                                p0,
                              ).forecastLinesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.snapshotId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (forecastEvidenceRefs)
                        await $_getPrefetchedData<
                          ForecastSnapshot,
                          $ForecastSnapshotsTable,
                          ForecastEvidenceData
                        >(
                          currentTable: table,
                          referencedTable: $$ForecastSnapshotsTableReferences
                              ._forecastEvidenceRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ForecastSnapshotsTableReferences(
                                db,
                                table,
                                p0,
                              ).forecastEvidenceRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.snapshotId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (forecastOverridesRefs)
                        await $_getPrefetchedData<
                          ForecastSnapshot,
                          $ForecastSnapshotsTable,
                          ForecastOverride
                        >(
                          currentTable: table,
                          referencedTable: $$ForecastSnapshotsTableReferences
                              ._forecastOverridesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ForecastSnapshotsTableReferences(
                                db,
                                table,
                                p0,
                              ).forecastOverridesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.snapshotId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ForecastSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ForecastSnapshotsTable,
      ForecastSnapshot,
      $$ForecastSnapshotsTableFilterComposer,
      $$ForecastSnapshotsTableOrderingComposer,
      $$ForecastSnapshotsTableAnnotationComposer,
      $$ForecastSnapshotsTableCreateCompanionBuilder,
      $$ForecastSnapshotsTableUpdateCompanionBuilder,
      (ForecastSnapshot, $$ForecastSnapshotsTableReferences),
      ForecastSnapshot,
      PrefetchHooks Function({
        bool eventId,
        bool sourceCommandId,
        bool forecastLinesRefs,
        bool forecastEvidenceRefs,
        bool forecastOverridesRefs,
      })
    >;
typedef $$ForecastLinesTableCreateCompanionBuilder =
    ForecastLinesCompanion Function({
      required String snapshotId,
      required String itemId,
      required int packSizeMicros,
      required int onHandMicros,
      Value<int> confirmedInboundMicros,
      Value<int?> expectedUseMicros,
      Value<int?> plannedMicros,
      Value<int?> loadMicros,
      Value<int?> acquireMicros,
      required String evidenceGrade,
      Value<String> warningsJson,
      Value<int> rowid,
    });
typedef $$ForecastLinesTableUpdateCompanionBuilder =
    ForecastLinesCompanion Function({
      Value<String> snapshotId,
      Value<String> itemId,
      Value<int> packSizeMicros,
      Value<int> onHandMicros,
      Value<int> confirmedInboundMicros,
      Value<int?> expectedUseMicros,
      Value<int?> plannedMicros,
      Value<int?> loadMicros,
      Value<int?> acquireMicros,
      Value<String> evidenceGrade,
      Value<String> warningsJson,
      Value<int> rowid,
    });

final class $$ForecastLinesTableReferences
    extends BaseReferences<_$AppDatabase, $ForecastLinesTable, ForecastLine> {
  $$ForecastLinesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ForecastSnapshotsTable _snapshotIdTable(_$AppDatabase db) => db
      .forecastSnapshots
      .createAlias('forecast_lines__snapshot_id__forecast_snapshots__id');

  $$ForecastSnapshotsTableProcessedTableManager get snapshotId {
    final $_column = $_itemColumn<String>('snapshot_id')!;

    final manager = $$ForecastSnapshotsTableTableManager(
      $_db,
      $_db.forecastSnapshots,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_snapshotIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ItemsTable _itemIdTable(_$AppDatabase db) =>
      db.items.createAlias('forecast_lines__item_id__items__id');

  $$ItemsTableProcessedTableManager get itemId {
    final $_column = $_itemColumn<String>('item_id')!;

    final manager = $$ItemsTableTableManager(
      $_db,
      $_db.items,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_itemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ForecastLinesTableFilterComposer
    extends Composer<_$AppDatabase, $ForecastLinesTable> {
  $$ForecastLinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get packSizeMicros => $composableBuilder(
    column: $table.packSizeMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get onHandMicros => $composableBuilder(
    column: $table.onHandMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get confirmedInboundMicros => $composableBuilder(
    column: $table.confirmedInboundMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expectedUseMicros => $composableBuilder(
    column: $table.expectedUseMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get plannedMicros => $composableBuilder(
    column: $table.plannedMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get loadMicros => $composableBuilder(
    column: $table.loadMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get acquireMicros => $composableBuilder(
    column: $table.acquireMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evidenceGrade => $composableBuilder(
    column: $table.evidenceGrade,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get warningsJson => $composableBuilder(
    column: $table.warningsJson,
    builder: (column) => ColumnFilters(column),
  );

  $$ForecastSnapshotsTableFilterComposer get snapshotId {
    final $$ForecastSnapshotsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snapshotId,
      referencedTable: $db.forecastSnapshots,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastSnapshotsTableFilterComposer(
            $db: $db,
            $table: $db.forecastSnapshots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ItemsTableFilterComposer get itemId {
    final $$ItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableFilterComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ForecastLinesTableOrderingComposer
    extends Composer<_$AppDatabase, $ForecastLinesTable> {
  $$ForecastLinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get packSizeMicros => $composableBuilder(
    column: $table.packSizeMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get onHandMicros => $composableBuilder(
    column: $table.onHandMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get confirmedInboundMicros => $composableBuilder(
    column: $table.confirmedInboundMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expectedUseMicros => $composableBuilder(
    column: $table.expectedUseMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get plannedMicros => $composableBuilder(
    column: $table.plannedMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get loadMicros => $composableBuilder(
    column: $table.loadMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get acquireMicros => $composableBuilder(
    column: $table.acquireMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evidenceGrade => $composableBuilder(
    column: $table.evidenceGrade,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get warningsJson => $composableBuilder(
    column: $table.warningsJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$ForecastSnapshotsTableOrderingComposer get snapshotId {
    final $$ForecastSnapshotsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snapshotId,
      referencedTable: $db.forecastSnapshots,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastSnapshotsTableOrderingComposer(
            $db: $db,
            $table: $db.forecastSnapshots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ItemsTableOrderingComposer get itemId {
    final $$ItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableOrderingComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ForecastLinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ForecastLinesTable> {
  $$ForecastLinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get packSizeMicros => $composableBuilder(
    column: $table.packSizeMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get onHandMicros => $composableBuilder(
    column: $table.onHandMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get confirmedInboundMicros => $composableBuilder(
    column: $table.confirmedInboundMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expectedUseMicros => $composableBuilder(
    column: $table.expectedUseMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get plannedMicros => $composableBuilder(
    column: $table.plannedMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get loadMicros => $composableBuilder(
    column: $table.loadMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get acquireMicros => $composableBuilder(
    column: $table.acquireMicros,
    builder: (column) => column,
  );

  GeneratedColumn<String> get evidenceGrade => $composableBuilder(
    column: $table.evidenceGrade,
    builder: (column) => column,
  );

  GeneratedColumn<String> get warningsJson => $composableBuilder(
    column: $table.warningsJson,
    builder: (column) => column,
  );

  $$ForecastSnapshotsTableAnnotationComposer get snapshotId {
    final $$ForecastSnapshotsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.snapshotId,
          referencedTable: $db.forecastSnapshots,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ForecastSnapshotsTableAnnotationComposer(
                $db: $db,
                $table: $db.forecastSnapshots,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$ItemsTableAnnotationComposer get itemId {
    final $$ItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ForecastLinesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ForecastLinesTable,
          ForecastLine,
          $$ForecastLinesTableFilterComposer,
          $$ForecastLinesTableOrderingComposer,
          $$ForecastLinesTableAnnotationComposer,
          $$ForecastLinesTableCreateCompanionBuilder,
          $$ForecastLinesTableUpdateCompanionBuilder,
          (ForecastLine, $$ForecastLinesTableReferences),
          ForecastLine,
          PrefetchHooks Function({bool snapshotId, bool itemId})
        > {
  $$ForecastLinesTableTableManager(_$AppDatabase db, $ForecastLinesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ForecastLinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ForecastLinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ForecastLinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> snapshotId = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<int> packSizeMicros = const Value.absent(),
                Value<int> onHandMicros = const Value.absent(),
                Value<int> confirmedInboundMicros = const Value.absent(),
                Value<int?> expectedUseMicros = const Value.absent(),
                Value<int?> plannedMicros = const Value.absent(),
                Value<int?> loadMicros = const Value.absent(),
                Value<int?> acquireMicros = const Value.absent(),
                Value<String> evidenceGrade = const Value.absent(),
                Value<String> warningsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ForecastLinesCompanion(
                snapshotId: snapshotId,
                itemId: itemId,
                packSizeMicros: packSizeMicros,
                onHandMicros: onHandMicros,
                confirmedInboundMicros: confirmedInboundMicros,
                expectedUseMicros: expectedUseMicros,
                plannedMicros: plannedMicros,
                loadMicros: loadMicros,
                acquireMicros: acquireMicros,
                evidenceGrade: evidenceGrade,
                warningsJson: warningsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String snapshotId,
                required String itemId,
                required int packSizeMicros,
                required int onHandMicros,
                Value<int> confirmedInboundMicros = const Value.absent(),
                Value<int?> expectedUseMicros = const Value.absent(),
                Value<int?> plannedMicros = const Value.absent(),
                Value<int?> loadMicros = const Value.absent(),
                Value<int?> acquireMicros = const Value.absent(),
                required String evidenceGrade,
                Value<String> warningsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ForecastLinesCompanion.insert(
                snapshotId: snapshotId,
                itemId: itemId,
                packSizeMicros: packSizeMicros,
                onHandMicros: onHandMicros,
                confirmedInboundMicros: confirmedInboundMicros,
                expectedUseMicros: expectedUseMicros,
                plannedMicros: plannedMicros,
                loadMicros: loadMicros,
                acquireMicros: acquireMicros,
                evidenceGrade: evidenceGrade,
                warningsJson: warningsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ForecastLinesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({snapshotId = false, itemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (snapshotId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.snapshotId,
                                referencedTable: $$ForecastLinesTableReferences
                                    ._snapshotIdTable(db),
                                referencedColumn: $$ForecastLinesTableReferences
                                    ._snapshotIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (itemId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.itemId,
                                referencedTable: $$ForecastLinesTableReferences
                                    ._itemIdTable(db),
                                referencedColumn: $$ForecastLinesTableReferences
                                    ._itemIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ForecastLinesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ForecastLinesTable,
      ForecastLine,
      $$ForecastLinesTableFilterComposer,
      $$ForecastLinesTableOrderingComposer,
      $$ForecastLinesTableAnnotationComposer,
      $$ForecastLinesTableCreateCompanionBuilder,
      $$ForecastLinesTableUpdateCompanionBuilder,
      (ForecastLine, $$ForecastLinesTableReferences),
      ForecastLine,
      PrefetchHooks Function({bool snapshotId, bool itemId})
    >;
typedef $$ForecastEvidenceTableCreateCompanionBuilder =
    ForecastEvidenceCompanion Function({
      required String snapshotId,
      required String itemId,
      required int position,
      required String closeoutId,
      required String sourceEventId,
      required int exposure,
      required int depletionMicros,
      required bool stockout,
      required bool approximate,
      Value<int> rowid,
    });
typedef $$ForecastEvidenceTableUpdateCompanionBuilder =
    ForecastEvidenceCompanion Function({
      Value<String> snapshotId,
      Value<String> itemId,
      Value<int> position,
      Value<String> closeoutId,
      Value<String> sourceEventId,
      Value<int> exposure,
      Value<int> depletionMicros,
      Value<bool> stockout,
      Value<bool> approximate,
      Value<int> rowid,
    });

final class $$ForecastEvidenceTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ForecastEvidenceTable,
          ForecastEvidenceData
        > {
  $$ForecastEvidenceTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ForecastSnapshotsTable _snapshotIdTable(_$AppDatabase db) => db
      .forecastSnapshots
      .createAlias('forecast_evidence__snapshot_id__forecast_snapshots__id');

  $$ForecastSnapshotsTableProcessedTableManager get snapshotId {
    final $_column = $_itemColumn<String>('snapshot_id')!;

    final manager = $$ForecastSnapshotsTableTableManager(
      $_db,
      $_db.forecastSnapshots,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_snapshotIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ItemsTable _itemIdTable(_$AppDatabase db) =>
      db.items.createAlias('forecast_evidence__item_id__items__id');

  $$ItemsTableProcessedTableManager get itemId {
    final $_column = $_itemColumn<String>('item_id')!;

    final manager = $$ItemsTableTableManager(
      $_db,
      $_db.items,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_itemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $EventCloseoutsTable _closeoutIdTable(_$AppDatabase db) => db
      .eventCloseouts
      .createAlias('forecast_evidence__closeout_id__event_closeouts__id');

  $$EventCloseoutsTableProcessedTableManager get closeoutId {
    final $_column = $_itemColumn<String>('closeout_id')!;

    final manager = $$EventCloseoutsTableTableManager(
      $_db,
      $_db.eventCloseouts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_closeoutIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $EventsTable _sourceEventIdTable(_$AppDatabase db) =>
      db.events.createAlias('forecast_evidence__source_event_id__events__id');

  $$EventsTableProcessedTableManager get sourceEventId {
    final $_column = $_itemColumn<String>('source_event_id')!;

    final manager = $$EventsTableTableManager(
      $_db,
      $_db.events,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceEventIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ForecastEvidenceTableFilterComposer
    extends Composer<_$AppDatabase, $ForecastEvidenceTable> {
  $$ForecastEvidenceTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get exposure => $composableBuilder(
    column: $table.exposure,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get depletionMicros => $composableBuilder(
    column: $table.depletionMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get stockout => $composableBuilder(
    column: $table.stockout,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get approximate => $composableBuilder(
    column: $table.approximate,
    builder: (column) => ColumnFilters(column),
  );

  $$ForecastSnapshotsTableFilterComposer get snapshotId {
    final $$ForecastSnapshotsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snapshotId,
      referencedTable: $db.forecastSnapshots,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastSnapshotsTableFilterComposer(
            $db: $db,
            $table: $db.forecastSnapshots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ItemsTableFilterComposer get itemId {
    final $$ItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableFilterComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EventCloseoutsTableFilterComposer get closeoutId {
    final $$EventCloseoutsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.closeoutId,
      referencedTable: $db.eventCloseouts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventCloseoutsTableFilterComposer(
            $db: $db,
            $table: $db.eventCloseouts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EventsTableFilterComposer get sourceEventId {
    final $$EventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceEventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableFilterComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ForecastEvidenceTableOrderingComposer
    extends Composer<_$AppDatabase, $ForecastEvidenceTable> {
  $$ForecastEvidenceTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get exposure => $composableBuilder(
    column: $table.exposure,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get depletionMicros => $composableBuilder(
    column: $table.depletionMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get stockout => $composableBuilder(
    column: $table.stockout,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get approximate => $composableBuilder(
    column: $table.approximate,
    builder: (column) => ColumnOrderings(column),
  );

  $$ForecastSnapshotsTableOrderingComposer get snapshotId {
    final $$ForecastSnapshotsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snapshotId,
      referencedTable: $db.forecastSnapshots,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastSnapshotsTableOrderingComposer(
            $db: $db,
            $table: $db.forecastSnapshots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ItemsTableOrderingComposer get itemId {
    final $$ItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableOrderingComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EventCloseoutsTableOrderingComposer get closeoutId {
    final $$EventCloseoutsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.closeoutId,
      referencedTable: $db.eventCloseouts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventCloseoutsTableOrderingComposer(
            $db: $db,
            $table: $db.eventCloseouts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EventsTableOrderingComposer get sourceEventId {
    final $$EventsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceEventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableOrderingComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ForecastEvidenceTableAnnotationComposer
    extends Composer<_$AppDatabase, $ForecastEvidenceTable> {
  $$ForecastEvidenceTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<int> get exposure =>
      $composableBuilder(column: $table.exposure, builder: (column) => column);

  GeneratedColumn<int> get depletionMicros => $composableBuilder(
    column: $table.depletionMicros,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get stockout =>
      $composableBuilder(column: $table.stockout, builder: (column) => column);

  GeneratedColumn<bool> get approximate => $composableBuilder(
    column: $table.approximate,
    builder: (column) => column,
  );

  $$ForecastSnapshotsTableAnnotationComposer get snapshotId {
    final $$ForecastSnapshotsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.snapshotId,
          referencedTable: $db.forecastSnapshots,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ForecastSnapshotsTableAnnotationComposer(
                $db: $db,
                $table: $db.forecastSnapshots,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$ItemsTableAnnotationComposer get itemId {
    final $$ItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EventCloseoutsTableAnnotationComposer get closeoutId {
    final $$EventCloseoutsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.closeoutId,
      referencedTable: $db.eventCloseouts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventCloseoutsTableAnnotationComposer(
            $db: $db,
            $table: $db.eventCloseouts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$EventsTableAnnotationComposer get sourceEventId {
    final $$EventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceEventId,
      referencedTable: $db.events,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EventsTableAnnotationComposer(
            $db: $db,
            $table: $db.events,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ForecastEvidenceTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ForecastEvidenceTable,
          ForecastEvidenceData,
          $$ForecastEvidenceTableFilterComposer,
          $$ForecastEvidenceTableOrderingComposer,
          $$ForecastEvidenceTableAnnotationComposer,
          $$ForecastEvidenceTableCreateCompanionBuilder,
          $$ForecastEvidenceTableUpdateCompanionBuilder,
          (ForecastEvidenceData, $$ForecastEvidenceTableReferences),
          ForecastEvidenceData,
          PrefetchHooks Function({
            bool snapshotId,
            bool itemId,
            bool closeoutId,
            bool sourceEventId,
          })
        > {
  $$ForecastEvidenceTableTableManager(
    _$AppDatabase db,
    $ForecastEvidenceTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ForecastEvidenceTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ForecastEvidenceTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ForecastEvidenceTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> snapshotId = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> closeoutId = const Value.absent(),
                Value<String> sourceEventId = const Value.absent(),
                Value<int> exposure = const Value.absent(),
                Value<int> depletionMicros = const Value.absent(),
                Value<bool> stockout = const Value.absent(),
                Value<bool> approximate = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ForecastEvidenceCompanion(
                snapshotId: snapshotId,
                itemId: itemId,
                position: position,
                closeoutId: closeoutId,
                sourceEventId: sourceEventId,
                exposure: exposure,
                depletionMicros: depletionMicros,
                stockout: stockout,
                approximate: approximate,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String snapshotId,
                required String itemId,
                required int position,
                required String closeoutId,
                required String sourceEventId,
                required int exposure,
                required int depletionMicros,
                required bool stockout,
                required bool approximate,
                Value<int> rowid = const Value.absent(),
              }) => ForecastEvidenceCompanion.insert(
                snapshotId: snapshotId,
                itemId: itemId,
                position: position,
                closeoutId: closeoutId,
                sourceEventId: sourceEventId,
                exposure: exposure,
                depletionMicros: depletionMicros,
                stockout: stockout,
                approximate: approximate,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ForecastEvidenceTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                snapshotId = false,
                itemId = false,
                closeoutId = false,
                sourceEventId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (snapshotId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.snapshotId,
                                    referencedTable:
                                        $$ForecastEvidenceTableReferences
                                            ._snapshotIdTable(db),
                                    referencedColumn:
                                        $$ForecastEvidenceTableReferences
                                            ._snapshotIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (itemId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.itemId,
                                    referencedTable:
                                        $$ForecastEvidenceTableReferences
                                            ._itemIdTable(db),
                                    referencedColumn:
                                        $$ForecastEvidenceTableReferences
                                            ._itemIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (closeoutId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.closeoutId,
                                    referencedTable:
                                        $$ForecastEvidenceTableReferences
                                            ._closeoutIdTable(db),
                                    referencedColumn:
                                        $$ForecastEvidenceTableReferences
                                            ._closeoutIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (sourceEventId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.sourceEventId,
                                    referencedTable:
                                        $$ForecastEvidenceTableReferences
                                            ._sourceEventIdTable(db),
                                    referencedColumn:
                                        $$ForecastEvidenceTableReferences
                                            ._sourceEventIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$ForecastEvidenceTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ForecastEvidenceTable,
      ForecastEvidenceData,
      $$ForecastEvidenceTableFilterComposer,
      $$ForecastEvidenceTableOrderingComposer,
      $$ForecastEvidenceTableAnnotationComposer,
      $$ForecastEvidenceTableCreateCompanionBuilder,
      $$ForecastEvidenceTableUpdateCompanionBuilder,
      (ForecastEvidenceData, $$ForecastEvidenceTableReferences),
      ForecastEvidenceData,
      PrefetchHooks Function({
        bool snapshotId,
        bool itemId,
        bool closeoutId,
        bool sourceEventId,
      })
    >;
typedef $$ForecastOverridesTableCreateCompanionBuilder =
    ForecastOverridesCompanion Function({
      required String id,
      required String snapshotId,
      required String itemId,
      Value<int?> overrideLoadMicros,
      required String reason,
      required int createdAtMicros,
      Value<int> rowid,
    });
typedef $$ForecastOverridesTableUpdateCompanionBuilder =
    ForecastOverridesCompanion Function({
      Value<String> id,
      Value<String> snapshotId,
      Value<String> itemId,
      Value<int?> overrideLoadMicros,
      Value<String> reason,
      Value<int> createdAtMicros,
      Value<int> rowid,
    });

final class $$ForecastOverridesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ForecastOverridesTable,
          ForecastOverride
        > {
  $$ForecastOverridesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ForecastSnapshotsTable _snapshotIdTable(_$AppDatabase db) => db
      .forecastSnapshots
      .createAlias('forecast_overrides__snapshot_id__forecast_snapshots__id');

  $$ForecastSnapshotsTableProcessedTableManager get snapshotId {
    final $_column = $_itemColumn<String>('snapshot_id')!;

    final manager = $$ForecastSnapshotsTableTableManager(
      $_db,
      $_db.forecastSnapshots,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_snapshotIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ItemsTable _itemIdTable(_$AppDatabase db) =>
      db.items.createAlias('forecast_overrides__item_id__items__id');

  $$ItemsTableProcessedTableManager get itemId {
    final $_column = $_itemColumn<String>('item_id')!;

    final manager = $$ItemsTableTableManager(
      $_db,
      $_db.items,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_itemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ForecastOverridesTableFilterComposer
    extends Composer<_$AppDatabase, $ForecastOverridesTable> {
  $$ForecastOverridesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get overrideLoadMicros => $composableBuilder(
    column: $table.overrideLoadMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$ForecastSnapshotsTableFilterComposer get snapshotId {
    final $$ForecastSnapshotsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snapshotId,
      referencedTable: $db.forecastSnapshots,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastSnapshotsTableFilterComposer(
            $db: $db,
            $table: $db.forecastSnapshots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ItemsTableFilterComposer get itemId {
    final $$ItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableFilterComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ForecastOverridesTableOrderingComposer
    extends Composer<_$AppDatabase, $ForecastOverridesTable> {
  $$ForecastOverridesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get overrideLoadMicros => $composableBuilder(
    column: $table.overrideLoadMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$ForecastSnapshotsTableOrderingComposer get snapshotId {
    final $$ForecastSnapshotsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.snapshotId,
      referencedTable: $db.forecastSnapshots,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ForecastSnapshotsTableOrderingComposer(
            $db: $db,
            $table: $db.forecastSnapshots,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ItemsTableOrderingComposer get itemId {
    final $$ItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableOrderingComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ForecastOverridesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ForecastOverridesTable> {
  $$ForecastOverridesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get overrideLoadMicros => $composableBuilder(
    column: $table.overrideLoadMicros,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  $$ForecastSnapshotsTableAnnotationComposer get snapshotId {
    final $$ForecastSnapshotsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.snapshotId,
          referencedTable: $db.forecastSnapshots,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ForecastSnapshotsTableAnnotationComposer(
                $db: $db,
                $table: $db.forecastSnapshots,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$ItemsTableAnnotationComposer get itemId {
    final $$ItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.itemId,
      referencedTable: $db.items,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.items,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ForecastOverridesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ForecastOverridesTable,
          ForecastOverride,
          $$ForecastOverridesTableFilterComposer,
          $$ForecastOverridesTableOrderingComposer,
          $$ForecastOverridesTableAnnotationComposer,
          $$ForecastOverridesTableCreateCompanionBuilder,
          $$ForecastOverridesTableUpdateCompanionBuilder,
          (ForecastOverride, $$ForecastOverridesTableReferences),
          ForecastOverride,
          PrefetchHooks Function({bool snapshotId, bool itemId})
        > {
  $$ForecastOverridesTableTableManager(
    _$AppDatabase db,
    $ForecastOverridesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ForecastOverridesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ForecastOverridesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ForecastOverridesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> snapshotId = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<int?> overrideLoadMicros = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ForecastOverridesCompanion(
                id: id,
                snapshotId: snapshotId,
                itemId: itemId,
                overrideLoadMicros: overrideLoadMicros,
                reason: reason,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String snapshotId,
                required String itemId,
                Value<int?> overrideLoadMicros = const Value.absent(),
                required String reason,
                required int createdAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => ForecastOverridesCompanion.insert(
                id: id,
                snapshotId: snapshotId,
                itemId: itemId,
                overrideLoadMicros: overrideLoadMicros,
                reason: reason,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ForecastOverridesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({snapshotId = false, itemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (snapshotId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.snapshotId,
                                referencedTable:
                                    $$ForecastOverridesTableReferences
                                        ._snapshotIdTable(db),
                                referencedColumn:
                                    $$ForecastOverridesTableReferences
                                        ._snapshotIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (itemId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.itemId,
                                referencedTable:
                                    $$ForecastOverridesTableReferences
                                        ._itemIdTable(db),
                                referencedColumn:
                                    $$ForecastOverridesTableReferences
                                        ._itemIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ForecastOverridesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ForecastOverridesTable,
      ForecastOverride,
      $$ForecastOverridesTableFilterComposer,
      $$ForecastOverridesTableOrderingComposer,
      $$ForecastOverridesTableAnnotationComposer,
      $$ForecastOverridesTableCreateCompanionBuilder,
      $$ForecastOverridesTableUpdateCompanionBuilder,
      (ForecastOverride, $$ForecastOverridesTableReferences),
      ForecastOverride,
      PrefetchHooks Function({bool snapshotId, bool itemId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$WorkspaceMetaTableTableManager get workspaceMeta =>
      $$WorkspaceMetaTableTableManager(_db, _db.workspaceMeta);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$CommandsTableTableManager get commands =>
      $$CommandsTableTableManager(_db, _db.commands);
  $$ItemsTableTableManager get items =>
      $$ItemsTableTableManager(_db, _db.items);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db, _db.events);
  $$EventItemsTableTableManager get eventItems =>
      $$EventItemsTableTableManager(_db, _db.eventItems);
  $$InventoryMovementsTableTableManager get inventoryMovements =>
      $$InventoryMovementsTableTableManager(_db, _db.inventoryMovements);
  $$EventCloseoutsTableTableManager get eventCloseouts =>
      $$EventCloseoutsTableTableManager(_db, _db.eventCloseouts);
  $$CloseoutLinesTableTableManager get closeoutLines =>
      $$CloseoutLinesTableTableManager(_db, _db.closeoutLines);
  $$CloseoutDraftsTableTableManager get closeoutDrafts =>
      $$CloseoutDraftsTableTableManager(_db, _db.closeoutDrafts);
  $$RecipesTableTableManager get recipes =>
      $$RecipesTableTableManager(_db, _db.recipes);
  $$RecipeRevisionsTableTableManager get recipeRevisions =>
      $$RecipeRevisionsTableTableManager(_db, _db.recipeRevisions);
  $$RecipeLinesTableTableManager get recipeLines =>
      $$RecipeLinesTableTableManager(_db, _db.recipeLines);
  $$ForecastSnapshotsTableTableManager get forecastSnapshots =>
      $$ForecastSnapshotsTableTableManager(_db, _db.forecastSnapshots);
  $$ForecastLinesTableTableManager get forecastLines =>
      $$ForecastLinesTableTableManager(_db, _db.forecastLines);
  $$ForecastEvidenceTableTableManager get forecastEvidence =>
      $$ForecastEvidenceTableTableManager(_db, _db.forecastEvidence);
  $$ForecastOverridesTableTableManager get forecastOverrides =>
      $$ForecastOverridesTableTableManager(_db, _db.forecastOverrides);
}
