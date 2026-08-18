// Candidate D — "Stacked tubs".
// The strongest idea from research: evolve the existing single-tub mark into
// a stack of three nested event tubs — amber on top, cream, then sand — the
// after-event load stacked and counted. One bold, ownable silhouette that
// keeps continuity with the shipped icon.

import 'dart:ui';

import '../harness.dart';
import '../shapes.dart';

class CandidateDStack extends LoadoutIconCandidate {
  // ---- palette (swap here) -------------------------------------------------
  static const bgTop = Color(0xFF38735A);
  static const bgBottom = Color(0xFF234233);
  static const glow = Color(0x14FFFFFF);
  static const amber = Color(0xFFECA83F); // top tub
  static const amberRim = Color(0xFFC07C24);
  static const cream = Color(0xFFF4EEDF); // middle tub
  static const creamRim = Color(0xFFE2D5B6);
  static const sand = Color(0xFFE7DCBE); // bottom tub
  static const sandRim = Color(0xFFD2C29C);
  static const sandSlot = Color(0xFFBCAB84); // handle slot on bottom tub
  static const shadow = Color(0x26000000);
  // -------------------------------------------------------------------------

  @override
  String get id => 'd_stack';

  @override
  double get artExtent => 0.645;

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
      Rect.fromCenter(center: const Offset(512, 826), width: 660, height: 88),
      Paint()
        ..color = shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );
  }

  void _tub(
    Canvas canvas, {
    required double top,
    required double bottom,
    required double topWidth,
    required double bottomWidth,
    required Color body,
    required Color rim,
    double rimDepth = 46,
  }) {
    final path = roundedTrapezoid(
      centerX: 512,
      top: top,
      bottom: bottom,
      topWidth: topWidth,
      bottomWidth: bottomWidth,
      radius: 26,
    );
    canvas.drawPath(path, Paint()..color = body);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      Rect.fromLTRB(120, top, 904, top + rimDepth),
      Paint()..color = rim,
    );
    canvas.restore();
  }

  @override
  void paintForeground(Canvas canvas) {
    // Top tub (amber).
    _tub(
      canvas,
      top: 212,
      bottom: 384,
      topWidth: 478,
      bottomWidth: 410,
      body: amber,
      rim: amberRim,
      rimDepth: 42,
    );
    // Middle tub (cream).
    _tub(
      canvas,
      top: 402,
      bottom: 590,
      topWidth: 572,
      bottomWidth: 498,
      body: cream,
      rim: creamRim,
    );
    // Bottom tub (sand) with handle slot.
    _tub(
      canvas,
      top: 608,
      bottom: 812,
      topWidth: 660,
      bottomWidth: 572,
      body: sand,
      rim: sandRim,
      rimDepth: 48,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(407, 700, 617, 756),
        const Radius.circular(28),
      ),
      Paint()..color = sandSlot,
    );
  }
}
