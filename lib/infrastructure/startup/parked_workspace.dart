/// Parked workspace ciphertext — a real workspace sitting on disk beside
/// (or instead of) `db/loadout.db` (design §7.3, §8.2).
///
/// Two things park a workspace, and neither of them is a fresh install:
///
///  * `db/loadout.db.pre-restore` — `restoreBackup` renames the live
///    workspace aside before it re-encrypts the restored payload (§8.2). If
///    the process dies in that window (OOM, force quit, reboot) the rename
///    back never happens and the next launch finds no live database at all.
///  * `db/orphaned-<utcstamp>.db` — start-fresh / workspace reset archives
///    the previous ciphertext (§7.3). Never deleted, and its key is retained.
///
/// Both are openable data. Bootstrap must find them BEFORE it concludes
/// "fresh install", because that conclusion rotates the key — and rotating
/// over recoverable ciphertext is silent data loss.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../files/loadout_paths.dart';

/// How a workspace copy came to be parked.
enum ParkedWorkspaceKind {
  /// `db/loadout.db.pre-restore`: a restore was interrupted mid-swap.
  interruptedRestore,

  /// `db/orphaned-<utcstamp>.db`: archived by start-fresh / workspace reset.
  archived,
}

/// The `<live db path>` suffix `restoreBackup` parks the live workspace
/// under. Sidecars are parked as `loadout.db-wal.pre-restore` /
/// `loadout.db-shm.pre-restore` — the suffix goes LAST (see
/// `BackupServiceImpl._renameSidecars`), which is why [memberFor] exists.
const String preRestoreSuffix = '.pre-restore';

/// One recoverable workspace copy found in `db/`.
final class ParkedWorkspace {
  const ParkedWorkspace({
    required this.file,
    required this.kind,
    required this.label,
    required this.parkedAtUtc,
    required this.sizeBytes,
  });

  /// The main database file (never a sidecar).
  final File file;

  final ParkedWorkspaceKind kind;

  /// Retained-key label for an [ParkedWorkspaceKind.archived] copy
  /// (`orphaned-<utcstamp>`, exactly what `retainDatabaseKey` was given);
  /// `pre-restore` for an interrupted restore, whose ciphertext is under the
  /// live device key rather than a retained one.
  final String label;

  /// When the copy was parked: parsed from the archive stamp when the name
  /// carries one, otherwise the file's modification time.
  final DateTime parkedAtUtc;

  final int sizeBytes;

  /// The parked file holding db sidecar [suffix] (`''`, `'-wal'`, `'-shm'`).
  File memberFor(String suffix) => switch (kind) {
    ParkedWorkspaceKind.interruptedRestore => File(
      '${file.path.substring(0, file.path.length - preRestoreSuffix.length)}'
      '$suffix$preRestoreSuffix',
    ),
    ParkedWorkspaceKind.archived => File('${file.path}$suffix'),
  };

  /// The `''`/`-wal`/`-shm` members that actually exist, main file first.
  List<(String suffix, File file)> existingMembers() => [
    for (final suffix in const ['', '-wal', '-shm'])
      if (memberFor(suffix).existsSync()) (suffix, memberFor(suffix)),
  ];
}

/// `orphaned-<14 digits>[-<n>].db`; the optional `-<n>` disambiguates two
/// archives made in the same second.
final RegExp _archiveName = RegExp(r'^orphaned-(\d{14})(?:-\d+)?\.db$');

/// Every recoverable copy in `db/`, newest first. Pure inspection: this
/// never creates, renames, or deletes anything.
List<ParkedWorkspace> scanParkedWorkspaces(LoadoutPaths paths) {
  final dir = paths.dbDir;
  if (!dir.existsSync()) {
    return const [];
  }
  final preRestoreName =
      '${p.basename(paths.databaseFile.path)}'
      '$preRestoreSuffix';
  final found = <ParkedWorkspace>[];
  for (final entity in dir.listSync()) {
    if (entity is! File) {
      continue;
    }
    final name = p.basename(entity.path);
    final stat = entity.statSync();
    if (name == preRestoreName) {
      found.add(
        ParkedWorkspace(
          file: entity,
          kind: ParkedWorkspaceKind.interruptedRestore,
          label: 'pre-restore',
          parkedAtUtc: stat.modified.toUtc(),
          sizeBytes: stat.size,
        ),
      );
      continue;
    }
    final match = _archiveName.firstMatch(name);
    if (match != null) {
      found.add(
        ParkedWorkspace(
          file: entity,
          kind: ParkedWorkspaceKind.archived,
          // Exactly the label `startFreshFromRecovery` retained the key
          // under: basename without the `.db` extension.
          label: p.basenameWithoutExtension(name),
          parkedAtUtc: _parseStamp(match.group(1)!) ?? stat.modified.toUtc(),
          sizeBytes: stat.size,
        ),
      );
    }
  }
  found.sort(_newestFirst);
  return found;
}

/// Newest first; an interrupted restore outranks an archive parked in the
/// same second (it is the more recent event), then label descending so the
/// order is total and stable.
int _newestFirst(ParkedWorkspace a, ParkedWorkspace b) {
  final byTime = b.parkedAtUtc.compareTo(a.parkedAtUtc);
  if (byTime != 0) {
    return byTime;
  }
  if (a.kind != b.kind) {
    return a.kind == ParkedWorkspaceKind.interruptedRestore ? -1 : 1;
  }
  return b.label.compareTo(a.label);
}

/// `yyyyMMddHHmmss` (the [LoadoutPaths.utcStamp] shape) → UTC instant.
DateTime? _parseStamp(String stamp) {
  int at(int start, int end) => int.parse(stamp.substring(start, end));
  try {
    return DateTime.utc(
      at(0, 4),
      at(4, 6),
      at(6, 8),
      at(8, 10),
      at(10, 12),
      at(12, 14),
    );
  } on FormatException {
    return null;
  }
}
