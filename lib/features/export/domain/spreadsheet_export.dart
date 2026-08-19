/// The four spreadsheets Loadout can hand over, and what each file is
/// called — pure Dart, no Flutter.
///
/// Everything in this app leaves as one encrypted container that only this
/// app can read. That is the right shape for a backup and the wrong shape
/// for a treasurer, a successor coordinator, or anyone who has Excel and
/// nothing else. These four exports are the plain-CSV answer: no encryption,
/// no app, no import step — a file that opens.
library;

/// One export the owner can save. Ordered as the screen lists them.
enum SpreadsheetExport {
  /// Everything in the item list, with what it is worth.
  items(
    title: 'Items',
    blurb: 'Every item, what you have, and what it is worth',
    buttonLabel: 'Save items…',
    fileStem: 'items',
  ),

  /// Every event with its attendance and its money.
  events(
    title: 'Events',
    blurb: 'Every event, its attendance, and what it cost',
    buttonLabel: 'Save events…',
    fileStem: 'events',
  ),

  /// One closed event's confirmed count — the treasurer's artifact.
  eventCount(
    title: "One event's count",
    blurb: 'What you counted at one event, against what was expected',
    buttonLabel: 'Choose an event…',
    fileStem: 'count',
  ),

  /// Recipes with their ingredients.
  recipes(
    title: 'Recipes',
    blurb: 'Each recipe with its ingredients and amounts',
    buttonLabel: 'Save recipes…',
    fileStem: 'recipes',
  );

  const SpreadsheetExport({
    required this.title,
    required this.blurb,
    required this.buttonLabel,
    required this.fileStem,
  });

  /// Row heading on the export screen.
  final String title;

  /// The one line under the heading. One line, on purpose.
  final String blurb;

  /// The button that starts this export. Never an icon alone (§9), and
  /// never the same words four times over — a screen reader hears these
  /// one after another.
  final String buttonLabel;

  /// The middle of the file name: `loadout-<stem>-<date>.csv`.
  final String fileStem;
}

/// `loadout-items-2026-08-19.csv`, or `loadout-count-summer-fete-
/// 2026-07-04.csv` when [subject] names what the file is about (the event a
/// count belongs to — a count with no event in its name is an orphan the
/// moment it is emailed on).
String exportFileName(
  SpreadsheetExport export, {
  required String datePart,
  String? subject,
}) {
  final slug = subject == null ? null : fileNameSlug(subject);
  final middle = slug == null || slug.isEmpty
      ? export.fileStem
      : '${export.fileStem}-$slug';
  return 'loadout-$middle-$datePart.csv';
}

/// Lowercase, ASCII-safe, hyphen-joined, and bounded — a name that survives
/// every file system the save dialog might land on.
String fileNameSlug(String value, {int maxLength = 40}) {
  final buffer = StringBuffer();
  var pendingHyphen = false;
  for (final rune in value.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final isSafe =
        (rune >= 0x30 && rune <= 0x39) || (rune >= 0x61 && rune <= 0x7a);
    if (isSafe) {
      if (pendingHyphen && buffer.isNotEmpty) buffer.write('-');
      pendingHyphen = false;
      buffer.write(char);
      if (buffer.length >= maxLength) break;
    } else {
      pendingHyphen = true;
    }
  }
  return buffer.toString();
}
