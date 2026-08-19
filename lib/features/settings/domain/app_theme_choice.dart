/// The appearance preference (`settings.theme_mode`): whether Loadout
/// follows the phone's light/dark setting or pins one brightness itself.
///
/// Deliberately Flutter-free, like `FolderHue` in core/: the service reads
/// and writes it, the settings screen labels it, and the ONE place that
/// needs Flutter's `ThemeMode` — the app root, `lib/app/app.dart` — maps it
/// there. Appearance is a preference, not a record: it rides the key-value
/// `settings` table, so nothing here touches the schema.
library;

enum AppThemeChoice {
  system('system', 'Follow phone'),
  light('light', 'Light'),
  dark('dark', 'Dark');

  const AppThemeChoice(this.dbValue, this.displayName);

  /// The persisted string, JSON-encoded into `settings.value`. Spelled out
  /// rather than taken from [name] so renaming a constant can never silently
  /// orphan a stored preference.
  final String dbValue;

  /// The word on the control. Every option carries one — this app has no
  /// icon-only controls.
  final String displayName;

  /// The choice [value] names, or null when this build does not know it.
  ///
  /// Null rather than a throw on purpose: appearance is a preference, so an
  /// unreadable row falls back to [system] instead of taking the app down
  /// before it can paint.
  static AppThemeChoice? fromDb(String value) {
    for (final choice in values) {
      if (choice.dbValue == value) return choice;
    }
    return null;
  }
}
