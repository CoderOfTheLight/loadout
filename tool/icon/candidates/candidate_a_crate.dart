// Candidate A — "Packed crate". THE SHIPPING ICON.
// A cream supply tote seen straight-on with a hint of interior depth, tilted
// a few degrees, with three simple supplies rising above the rim: a terracotta
// box, an amber can, a sage produce round. Says "packed and ready for the
// event". Installed to both platforms by ../install_icons_test.dart.

import 'dart:ui';

import '../harness.dart';
import '../shapes.dart';

class CandidateACrate extends LoadoutIconCandidate {
  // ---- palette (swap here) -------------------------------------------------
  // Palette direction "A · Warm Paper, finished": paper #FBF8F2,
  // green #2F6B57, pending #B8791B, short #A33E36, ink #191C18.
  static const bgTop = Color(0xFF2F6B57); // brand green, base of the field
  static const bgBottom = Color(0xFF245243); // subtle deepening at the bottom
  static const glow = Color(0x14FFFFFF); // soft radial light behind art
  static const cream = Color(0xFFFBF8F2); // crate body — the paper colour
  static const creamRim = Color(0xFFE0D6C2); // crate rim interior band
  static const creamSlot = Color(0xFF9E8F79); // handle slot
  static const box = Color(0xFFC9704B); // box item (terracotta)
  static const amber = Color(0xFFDD9A2A); // can item (pending-family warmth)
  static const amberDeep = Color(0xFFB8791B); // can lid — pending, exactly
  static const sage = Color(0xFFA8CBAE); // produce item
  static const shadow = Color(0x1C000000); // grounding shadow
  // -------------------------------------------------------------------------

  static const _tiltRadians = -0.055; // ~ -3.2 degrees
  static const _pivot = Offset(512, 560);

  @override
  String get id => 'a_crate';

  // The art is 620 wide but 546 tall, so its corners sit further out than its
  // width suggests; 0.72 (rather than the 0.605 the width alone would ask for)
  // is what keeps the tote's bottom corners inside a circular launcher mask.
  @override
  double get artExtent => 0.72;

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
      Rect.fromCenter(center: const Offset(512, 800), width: 540, height: 72),
      Paint()
        ..color = shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
  }

  // ---- geometry, shared by the colour and monochrome passes ----------------
  static final _box = RRect.fromRectAndRadius(
    const Rect.fromLTRB(330, 285, 458, 540),
    const Radius.circular(26),
  );
  static final _can = RRect.fromRectAndRadius(
    const Rect.fromLTRB(470, 258, 622, 540),
    const Radius.circular(30),
  );
  static const _canLid = Rect.fromLTRB(482, 246, 610, 296);
  static const _produceCenter = Offset(668, 380);
  static const _produceRadius = 88.0;
  static final _crate = roundedTrapezoid(
    centerX: 512,
    top: 430,
    bottom: 792,
    topWidth: 620,
    bottomWidth: 508,
    radius: 32,
  );
  static final _slot = RRect.fromRectAndRadius(
    const Rect.fromLTRB(402, 548, 622, 604),
    const Radius.circular(28),
  );

  /// Applies the crate's tilt, runs [draw], and restores.
  void _tilted(Canvas canvas, void Function(Canvas) draw) {
    canvas.save();
    canvas.translate(_pivot.dx, _pivot.dy);
    canvas.rotate(_tiltRadians);
    canvas.translate(-_pivot.dx, -_pivot.dy);
    draw(canvas);
    canvas.restore();
  }

  @override
  void paintForeground(Canvas canvas) => _tilted(canvas, (c) {
    // Supplies rising above the rim (bottoms hidden by the crate front).
    c.drawRRect(_box, Paint()..color = box);
    c.drawRRect(_can, Paint()..color = amber);
    c.drawOval(_canLid, Paint()..color = amberDeep);
    c.drawCircle(_produceCenter, _produceRadius, Paint()..color = sage);

    // Crate front.
    c.drawPath(_crate, Paint()..color = cream);

    // Rim interior band: hints that the tub is open and has depth.
    c.save();
    c.clipPath(_crate);
    c.drawRect(
      const Rect.fromLTRB(160, 430, 864, 484),
      Paint()..color = creamRim,
    );
    c.restore();

    // Handle slot.
    c.drawRRect(_slot, Paint()..color = creamSlot);
  });

  /// Themed-icon source. Flattened to one colour the tote and its contents
  /// merge into an unreadable lump, so every boundary that colour was carrying
  /// is re-cut as a hole: a gap around each item, a gap along the crate's
  /// outline, and the handle slot.
  @override
  void paintMonochrome(Canvas canvas) => _tilted(canvas, (c) {
    const gap = 17.0; // ~1.7% of the icon side; survives to mdpi
    final clear = Paint()..blendMode = BlendMode.clear;

    c.drawRRect(_box, Paint());
    // Each item clears its own margin out of whatever is already there,
    // then fills back the shape itself — a uniform gap, no double-drawing.
    c.drawRRect(_can.inflate(gap), clear);
    c.drawRRect(_can, Paint());
    c.drawOval(_canLid, Paint());
    c.drawCircle(_produceCenter, _produceRadius + gap, clear);
    c.drawCircle(_produceCenter, _produceRadius, Paint());

    // The crate reads as in front: clear a band straddling its outline,
    // then fill the crate back in, leaving the gap outside it only.
    c.drawPath(
      _crate,
      Paint()
        ..blendMode = BlendMode.clear
        ..style = PaintingStyle.stroke
        ..strokeWidth = gap * 2,
    );
    c.drawPath(_crate, Paint());
    c.drawRRect(_slot, clear);
  });
}
