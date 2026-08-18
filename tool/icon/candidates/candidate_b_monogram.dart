// Candidate B — "L of crates".
// A bold letter L assembled from five stacked supply crates (each with a
// tiny handle slot), the last crate amber — the one just counted. Reads as a
// solid monogram at 60px, reveals the crate construction at full size.

import 'dart:ui';

import '../harness.dart';
import '../shapes.dart';

class CandidateBMonogram extends LoadoutIconCandidate {
  // ---- palette (swap here) -------------------------------------------------
  static const bgTop = Color(0xFF38735A);
  static const bgBottom = Color(0xFF234233);
  static const glow = Color(0x14FFFFFF);
  static const creamHi = Color(0xFFF8F2E4); // crate top
  static const creamLo = Color(0xFFE9DEC2); // crate bottom
  static const creamSlot = Color(0xFFCDBE9B);
  static const amberHi = Color(0xFFEDA93F);
  static const amberLo = Color(0xFFD98F2B);
  static const amberSlot = Color(0xFFB0731D);
  static const shadow = Color(0x22000000);
  // -------------------------------------------------------------------------

  static const _unit = 196.0; // crate side
  static const _gap = 16.0; // gap between crates
  // Geometric centring plus an optical shift toward the L's empty top-right
  // corner, so the letter's bottom-left mass doesn't drag the mark off-balance.
  static const _origin = 202.0; // (1024 - (3*unit + 2*gap)) / 2
  static const _opticalShift = Offset(30, -22);

  @override
  String get id => 'b_monogram';

  @override
  double get artExtent => 0.60;

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
      Rect.fromCenter(center: const Offset(512, 830), width: 640, height: 80),
      Paint()
        ..color = shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );
  }

  Rect _cell(int row, int col) {
    final x = _origin + col * (_unit + _gap);
    final y = _origin + row * (_unit + _gap);
    return Rect.fromLTWH(x, y, _unit, _unit);
  }

  void _crate(Canvas canvas, Rect rect, bool isAmber) {
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(38));
    canvas.drawRRect(
      rrect,
      verticalGradient(
        rect,
        isAmber ? const [amberHi, amberLo] : const [creamHi, creamLo],
      ),
    );
    // Tiny handle slot.
    final slot = Rect.fromCenter(
      center: rect.center.translate(0, -14),
      width: 92,
      height: 26,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(slot, const Radius.circular(13)),
      Paint()..color = isAmber ? amberSlot : creamSlot,
    );
  }

  @override
  void paintForeground(Canvas canvas) {
    canvas.save();
    canvas.translate(_opticalShift.dx, _opticalShift.dy);
    // Vertical stroke of the L: rows 0..2 in column 0.
    _crate(canvas, _cell(0, 0), false);
    _crate(canvas, _cell(1, 0), false);
    _crate(canvas, _cell(2, 0), false);
    // Foot of the L: row 2, columns 1..2; the end crate is amber.
    _crate(canvas, _cell(2, 1), false);
    _crate(canvas, _cell(2, 2), true);
    canvas.restore();
  }
}
