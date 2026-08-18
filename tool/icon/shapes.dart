// Shared vector helpers for icon candidates.

import 'dart:math' as math;
import 'dart:ui';

/// A closed polygon through [points] with each corner rounded.
///
/// [radius] applies to every corner unless [radii] gives a per-corner value
/// (same length as [points]). Corners are rounded with a quadratic curve, and
/// each radius is clamped so adjacent corners never overlap.
Path roundedPoly(List<Offset> points, double radius, {List<double>? radii}) {
  assert(radii == null || radii.length == points.length);
  final n = points.length;
  final path = Path();
  for (var i = 0; i < n; i++) {
    final prev = points[(i - 1 + n) % n];
    final cur = points[i];
    final next = points[(i + 1) % n];
    final toPrev = prev - cur;
    final toNext = next - cur;
    final dPrev = toPrev.distance;
    final dNext = toNext.distance;
    final r = math.min(
      radii != null ? radii[i] : radius,
      math.min(dPrev, dNext) / 2,
    );
    final a = cur + (toPrev / dPrev) * r;
    final b = cur + (toNext / dNext) * r;
    if (i == 0) {
      path.moveTo(a.dx, a.dy);
    } else {
      path.lineTo(a.dx, a.dy);
    }
    path.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
  }
  path.close();
  return path;
}

/// Symmetric rounded trapezoid: horizontal top edge of [topWidth] at [top],
/// horizontal bottom edge of [bottomWidth] at [bottom], centred on [centerX].
Path roundedTrapezoid({
  required double centerX,
  required double top,
  required double bottom,
  required double topWidth,
  required double bottomWidth,
  required double radius,
}) {
  return roundedPoly([
    Offset(centerX - topWidth / 2, top),
    Offset(centerX + topWidth / 2, top),
    Offset(centerX + bottomWidth / 2, bottom),
    Offset(centerX - bottomWidth / 2, bottom),
  ], radius);
}

/// Vertical linear gradient paint over [rect].
Paint verticalGradient(Rect rect, List<Color> colors, [List<double>? stops]) {
  return Paint()
    ..shader = Gradient.linear(
      rect.topCenter,
      rect.bottomCenter,
      colors,
      stops,
    );
}
