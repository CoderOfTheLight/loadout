/// A structural guard for one bug that has now been written twice.
///
/// `SliverPersistentHeader` caches the widget its delegate builds and re-runs
/// `SliverPersistentHeaderDelegate.build` only when `shouldRebuild` returns
/// true — and `shouldRebuild` receives the old delegate, not a
/// `BuildContext`, so it cannot know the theme changed. A delegate that
/// resolves `Theme.of(context)` (or any theme extension) inside `build`
/// therefore FREEZES its colours in whichever brightness happened to be live
/// when the header first mounted: flip the system to dark and the pinned
/// folder headers stay cream on a near-black list.
///
/// Both fixes are the same shape — the delegate carries data, an ordinary
/// `StatelessWidget` carries the pixels — and both are easy to undo by
/// someone adding "just one colour" to a delegate. This test scans lib/ for
/// the pattern instead of trusting a comment.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every `class … extends SliverPersistentHeaderDelegate` body in lib/, as
/// (file, class name, source) triples. Bodies are cut at the next top-level
/// `class ` declaration, which is enough: a delegate is always a top-level
/// class in this repo.
Iterable<(String, String, String)> _delegateBodies() sync* {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
  for (final file in files) {
    final source = file.readAsStringSync();
    if (!source.contains('SliverPersistentHeaderDelegate')) continue;
    final chunks = source.split(RegExp(r'^class ', multiLine: true));
    for (final chunk in chunks.skip(1)) {
      if (!chunk.startsWith(RegExp(r'\w+ extends SliverPersistentHeader'))) {
        continue;
      }
      yield (file.path, chunk.split(RegExp(r'\s')).first, chunk);
    }
  }
}

void main() {
  test('no sliver header delegate resolves the theme in its build', () {
    final delegates = _delegateBodies().toList();
    expect(
      delegates,
      isNotEmpty,
      reason: 'the scanner must actually be finding the delegates',
    );
    for (final (path, name, body) in delegates) {
      for (final lookup in [
        'Theme.of(',
        'FolderPalette.of(',
        'StatusColors.of(',
        'DefaultTextStyle.of(',
      ]) {
        expect(
          body.contains(lookup),
          isFalse,
          reason:
              '$path: $name calls $lookup inside a '
              'SliverPersistentHeaderDelegate, which caches its child and '
              'cannot rebuild on a theme change. Move the pixels into a '
              'StatelessWidget and keep the delegate to data only.',
        );
      }
    }
  });
}
