/// Canonical on-disk layout under the app-support directory (design §7.2,
/// §10): `support/db/loadout.db`, `support/scratch/<purpose>/<session>/`,
/// `support/diag/diag.log`. App-private on both platforms — never
/// `Documents`, never external storage.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final class LoadoutPaths {
  LoadoutPaths(this.supportDir);

  /// Production resolution via path_provider.
  static Future<LoadoutPaths> resolve() async =>
      LoadoutPaths(await getApplicationSupportDirectory());

  final Directory supportDir;

  Directory get dbDir => Directory(p.join(supportDir.path, 'db'));

  File get databaseFile => File(p.join(dbDir.path, 'loadout.db'));

  Directory get scratchDir => Directory(p.join(supportDir.path, 'scratch'));

  Directory get diagDir => Directory(p.join(supportDir.path, 'diag'));

  File get diagLogFile => File(p.join(diagDir.path, 'diag.log'));

  /// Archive name for orphaned ciphertext (§7.3 start-fresh; never deleted).
  File orphanedDatabaseFile(DateTime utcNow) {
    final t = utcNow.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${t.year}${two(t.month)}${two(t.day)}'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
    return File(p.join(dbDir.path, 'orphaned-$stamp.db'));
  }
}
