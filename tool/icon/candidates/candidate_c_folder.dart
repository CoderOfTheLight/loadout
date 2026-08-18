// Candidate C — "Folder of supplies".
// The app's folder-chip identity as a mark: a sand folder with a tab, three
// supplies poking out of the pocket (amber round, sage box, terracotta box),
// cream front pocket. Ties the icon to the in-app organizing metaphor.

import 'dart:ui';

import '../harness.dart';
import '../shapes.dart';

class CandidateCFolder extends LoadoutIconCandidate {
  // ---- palette (swap here) -------------------------------------------------
  static const bgTop = Color(0xFF38735A);
  static const bgBottom = Color(0xFF234233);
  static const glow = Color(0x14FFFFFF);
  static const folderBack = Color(0xFFD8C9A6); // back panel + tab
  static const folderFront = Color(0xFFF4EEDF); // front pocket
  static const folderFrontLo = Color(0xFFE8DDC0); // pocket bottom shade
  static const pocketSlot = Color(0xFFCDBE9B); // handle slot on pocket
  static const amber = Color(0xFFE9A43C); // round item
  static const sage = Color(0xFF9CBFA3); // tall item
  static const terracotta = Color(0xFFC9704B); // square item
  static const shadow = Color(0x26000000);
  // -------------------------------------------------------------------------

  @override
  String get id => 'c_folder';

  @override
  double get artExtent => 0.59;

  @override
  void paintBackground(Canvas canvas) {
    canvas.drawRect(
      designRect,
      verticalGradient(designRect, const [bgTop, bgBottom]),
    );
    canvas.drawRect(
      designRect,
      Paint()
        ..shader = Gradient.radial(const Offset(512, 400), 640, const [
          glow,
          Color(0x00FFFFFF),
        ]),
    );
  }

  @override
  void paintShadow(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(512, 826), width: 660, height: 84),
      Paint()
        ..color = shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );
  }

  @override
  void paintForeground(Canvas canvas) {
    // Back panel with tab (top-left). Tab kept clear of the items.
    final back = roundedPoly(
      const [
        Offset(250, 306), // tab top-left
        Offset(438, 306), // tab top-right
        Offset(482, 372), // tab slope meets body top
        Offset(774, 372), // body top-right
        Offset(774, 780), // body bottom-right
        Offset(250, 780), // body bottom-left
      ],
      40,
      radii: const [28, 28, 8, 38, 38, 38],
    );
    canvas.drawPath(back, Paint()..color = folderBack);

    // Supplies poking out of the pocket (bottoms hidden by front panel).
    canvas.drawCircle(const Offset(452, 452), 80, Paint()..color = amber);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(556, 316, 672, 600),
        const Radius.circular(26),
      ),
      Paint()..color = sage,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(692, 420, 786, 600),
        const Radius.circular(24),
      ),
      Paint()..color = terracotta,
    );

    // Front pocket: shorter than the back panel, slightly wider, with a
    // handle slot tying the folder to the app's crate/tote identity.
    final frontRect = const Rect.fromLTRB(228, 532, 796, 806);
    final front = roundedPoly(const [
      Offset(238, 532),
      Offset(786, 532),
      Offset(796, 806),
      Offset(228, 806),
    ], 44);
    canvas.drawPath(
      front,
      verticalGradient(
        frontRect,
        const [folderFront, folderFrontLo],
        const [0.55, 1.0],
      ),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(407, 616, 617, 672),
        const Radius.circular(28),
      ),
      Paint()..color = pocketSlot,
    );
  }
}
