import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/time.dart';
import '../../../data/db/app_database.dart';
import '../../forecasting/domain/forecast_engine.dart';
import '../../../data/db/table_watch.dart';

/// Workspace read model (design §6.5): the singleton `workspace_meta` row
/// plus the preference settings.
final class Workspace {
  const Workspace({
    required this.uid,
    required this.displayName,
    required this.defaultPolicy,
    required this.exposureLabel,
    required this.historyWindow,
    required this.createdAt,
  });

  final String uid;
  final String displayName;
  final PlanningPolicy defaultPolicy;
  final String exposureLabel;
  final int historyWindow;
  final Instant createdAt;
}

/// Preference upserts — an explicit exception to the command path
/// (design §6.4): settings and workspace_meta are not records.
abstract interface class SettingsService {
  /// Names the seeded workspace and stores the chosen defaults; the
  /// workspace becomes visible to [watchWorkspace] afterwards.
  Future<Workspace> createWorkspace({
    required String name,
    required PlanningPolicy defaultPolicy,
  });

  Future<void> updatePreferences({
    String? name,
    PlanningPolicy? defaultPolicy,
    String? exposureLabel,
    int? historyWindow,
  });

  Stream<Workspace?> watchWorkspace();
}

final class DriftSettingsService implements SettingsService {
  DriftSettingsService(AppDatabase db, {this._clock = const SystemClock()})
    : _db = db;

  final AppDatabase _db;
  final Clock _clock;

  /// The DB seed always creates `workspace_meta`; this flag records that the
  /// user finished `/welcome/create`, so [watchWorkspace] can emit null
  /// before then (drives the router redirect).
  static const String _createdKey = 'workspace_created';
  static const String _policyKey = 'planning_policy_default';
  static const String _exposureLabelKey = 'exposure_label';
  static const String _historyWindowKey = 'history_window_events';

  @override
  Future<Workspace> createWorkspace({
    required String name,
    required PlanningPolicy defaultPolicy,
  }) async {
    await _db.transaction(() async {
      await updatePreferences(name: name, defaultPolicy: defaultPolicy);
      await _upsertSetting(_createdKey, jsonEncode(true));
    });
    return (await _loadWorkspace(requireCreated: false))!;
  }

  @override
  Future<void> updatePreferences({
    String? name,
    PlanningPolicy? defaultPolicy,
    String? exposureLabel,
    int? historyWindow,
  }) async {
    if (historyWindow != null && historyWindow < 1) {
      throw ArgumentError.value(
        historyWindow,
        'historyWindow',
        'must be positive',
      );
    }
    await _db.transaction(() async {
      if (name != null) {
        await _db
            .update(_db.workspaceMeta)
            .write(WorkspaceMetaCompanion(displayName: Value(name.trim())));
      }
      if (defaultPolicy != null) {
        await _upsertSetting(_policyKey, jsonEncode(defaultPolicy.name));
      }
      if (exposureLabel != null) {
        await _upsertSetting(_exposureLabelKey, jsonEncode(exposureLabel));
      }
      if (historyWindow != null) {
        await _upsertSetting(_historyWindowKey, jsonEncode(historyWindow));
      }
    });
  }

  @override
  Stream<Workspace?> watchWorkspace() => _db
      .watchTables('settings.workspace', {_db.workspaceMeta, _db.settings})
      .asyncMap((_) => _loadWorkspace());

  Future<Workspace?> _loadWorkspace({bool requireCreated = true}) async {
    final meta = await _db.select(_db.workspaceMeta).getSingleOrNull();
    if (meta == null) return null;
    if (requireCreated) {
      final created = await _db.settingsDao.value(_createdKey);
      if (created != 'true') return null;
    }
    return Workspace(
      uid: meta.workspaceUid,
      displayName: meta.displayName,
      defaultPolicy: await defaultPolicy(),
      exposureLabel: await exposureLabel(),
      historyWindow: await historyWindow(),
      createdAt: Instant(meta.createdAtMicros),
    );
  }

  /// Shared typed accessors (also used by ForecastService).
  Future<PlanningPolicy> defaultPolicy() async {
    final raw = await _db.settingsDao.value(_policyKey);
    if (raw == null) return PlanningPolicy.balanced;
    return PlanningPolicy.values.byName(jsonDecode(raw) as String);
  }

  Future<String> exposureLabel() async {
    final raw = await _db.settingsDao.value(_exposureLabelKey);
    return raw == null ? 'attendance' : jsonDecode(raw) as String;
  }

  Future<int> historyWindow() async {
    final raw = await _db.settingsDao.value(_historyWindowKey);
    return raw == null ? 12 : jsonDecode(raw) as int;
  }

  Future<void> _upsertSetting(String key, String value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: key,
          value: value,
          updatedAtMicros: _clock.now().epochMicrosUtc,
        ),
      );
}
