/// The appearance preference at the service seam: one key-value `settings`
/// row (`theme_mode`), no schema change, defaulting to "follow the phone",
/// readable without a workspace, and watchable on its own stream — the app
/// root paints `/welcome` and `/recovery` long before a workspace exists.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:loadout/data/db/app_database.dart';
import 'package:loadout/features/forecasting/domain/forecast_engine.dart';
import 'package:loadout/features/settings/application/settings_service.dart';
import 'package:loadout/features/settings/domain/app_theme_choice.dart';

import '../../db/fixtures.dart';

void main() {
  late AppDatabase db;
  late DriftSettingsService service;

  setUp(() {
    db = openTestDb();
    service = DriftSettingsService(db);
  });

  tearDown(() => db.close());

  test('unset means follow the phone', () async {
    expect(await service.themeMode(), AppThemeChoice.system);
    expect(await service.watchThemeMode().first, AppThemeChoice.system);
  });

  test('readable before any workspace was created', () async {
    // No createWorkspace() call anywhere in this test: the welcome flow runs
    // before watchWorkspace() emits, and still has to know the appearance.
    expect(await service.watchWorkspace().first, isNull);
    await service.setThemeMode(AppThemeChoice.dark);
    expect(await service.watchThemeMode().first, AppThemeChoice.dark);
  });

  test('every choice round-trips', () async {
    for (final choice in AppThemeChoice.values) {
      await service.setThemeMode(choice);
      expect(await service.themeMode(), choice, reason: choice.dbValue);
      expect(await service.watchThemeMode().first, choice);
    }
  });

  test('the stored value is the JSON-encoded dbValue', () async {
    await service.setThemeMode(AppThemeChoice.light);
    expect(await db.settingsDao.value('theme_mode'), '"light"');
  });

  test('survives a service restart over the same database', () async {
    await service.setThemeMode(AppThemeChoice.dark);
    expect(await DriftSettingsService(db).themeMode(), AppThemeChoice.dark);
  });

  test(
    'a value this build cannot read falls back to follow the phone',
    () async {
      await service.setThemeMode(AppThemeChoice.dark);
      await db.customStatement('UPDATE settings SET value = ? WHERE key = ?', [
        '"sepia"',
        'theme_mode',
      ]);
      expect(await service.themeMode(), AppThemeChoice.system);
    },
  );

  test('the stream emits on change, and only on change', () async {
    final seen = <AppThemeChoice>[];
    final sub = service.watchThemeMode().listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    await service.setThemeMode(AppThemeChoice.dark);
    await pumpEventQueue();
    await service.setThemeMode(AppThemeChoice.light);
    await pumpEventQueue();
    // A different preference also touches `settings`; the appearance stream
    // must not re-emit an unchanged choice.
    await service.updatePreferences(exposureLabel: 'covers');
    await pumpEventQueue();

    expect(seen, [
      AppThemeChoice.system,
      AppThemeChoice.dark,
      AppThemeChoice.light,
    ]);
  });

  test('its watch does not collide with the workspace watch', () async {
    // Drift caches query streams by statement text, not by readsFrom: a
    // shared watchTables label would hand this watcher the workspace's
    // stream and it would never see its own value.
    await service.createWorkspace(
      name: 'Test workspace',
      defaultPolicy: PlanningPolicy.balanced,
    );
    final workspaces = <Workspace?>[];
    final choices = <AppThemeChoice>[];
    final subA = service.watchWorkspace().listen(workspaces.add);
    final subB = service.watchThemeMode().listen(choices.add);
    addTearDown(subA.cancel);
    addTearDown(subB.cancel);
    await pumpEventQueue();

    await service.setThemeMode(AppThemeChoice.dark);
    await pumpEventQueue();

    expect(choices.last, AppThemeChoice.dark);
    expect(workspaces.last?.displayName, 'Test workspace');
  });
}
