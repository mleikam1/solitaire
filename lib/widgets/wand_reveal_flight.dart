import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A Wand lifts its selection to a readable size, turns it at the edge and
/// deals it into place. All coordinates are relative to the play area.
class WandRevealFlight extends StatelessWidget {
  const WandRevealFlight({
    super.key,
    required this.animation,
    required this.start,
    required this.end,
    required this.area,
    required this.cardSize,
    required this.before,
    this.after,
  });

  static const duration = Duration(milliseconds: 1000);
  static const focusScale = 1.85;
  static const revealEdge = 0.33;

  final Animation<double> animation;
  final Offset start;
  final Offset end;
  final Size area;
  final Size cardSize;
  final Widget before;
  final Widget? after;

  @override
  Widget build(BuildContext context) {
    final w = cardSize.width;
    final h = cardSize.height;
    final focus = Offset(
      ((start.dx + w / 2) * 0.30 + area.width * 0.35) - w / 2,
      area.height * 0.30 - h / 2,
    );
    final travelArc = math.min(h * 0.42, (end - focus).distance * 0.22);
    Offset positionAt(double t) {
      if (t < 0.34) {
        final lift = Curves.easeOutCubic.transform(t / 0.34);
        return Offset.lerp(start, focus, lift)! +
            Offset(0, -h * 0.32 * math.sin(math.pi * lift));
      }
      final travel = Curves.easeInOut.transform(
        ((t - 0.64) / 0.36).clamp(0.0, 1.0),
      );
      return Offset.lerp(focus, end, travel)! +
          Offset(0, -travelArc * math.sin(math.pi * travel));
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = animation.value;
              final position = positionAt(t);
              final lift = Curves.easeOut.transform((t / 0.32).clamp(0, 1));
              final travel = Curves.easeInOut.transform(
                ((t - 0.64) / 0.36).clamp(0, 1),
              );
              final airborne = lift * (1 - travel);
              final scale = 1 + airborne * (focusScale - 1);
              final turn = Curves.easeInOut.transform(
                ((t - 0.18) / 0.30).clamp(0, 1),
              );
              final turned = t >= revealEdge;
              final tilt =
                  after == null
                      ? 0.22 * math.sin(math.pi * turn)
                      : math.pi * (turned ? turn - 1 : turn);
              final pose =
                  Matrix4.identity()
                    ..setEntry(3, 2, 0.19 / w)
                    ..rotateZ(
                      -0.10 * math.sin(lift * math.pi) +
                          0.08 * math.sin(travel * math.pi),
                    )
                    ..rotateY(tilt)
                    ..multiply(Matrix4.diagonal3Values(scale, scale, 1));

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _WandSparks(
                        progress: t,
                        radius: w * scale,
                        center: position + cardSize.center(Offset.zero),
                        trail: [
                          for (var i = 1; i <= 7; i++)
                            positionAt(math.max(0, t - i * 0.012)) +
                                cardSize.center(Offset.zero),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: position.dx,
                    top: position.dy,
                    width: w,
                    child: Transform(
                      alignment: Alignment.topCenter,
                      origin: Offset(0, h / 2),
                      transform: pose,
                      child:
                          after == null
                              ? before
                              : IndexedStack(
                                index: turned ? 1 : 0,
                                children: [before, after!],
                              ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WandSparks extends CustomPainter {
  const _WandSparks({
    required this.progress,
    required this.radius,
    required this.center,
    required this.trail,
  });

  final double progress;
  final double radius;
  final Offset center;
  final List<Offset> trail;

  @override
  void paint(Canvas canvas, Size size) {
    const gold = Color(0xFFFFDE81);
    const aqua = Color(0xFF93FDF0);
    final paint = Paint();
    final brightness = math.sin(math.pi * progress);
    if (brightness <= 0) return;
    canvas.drawRect(
      Offset.zero & size,
      paint..color = Colors.black.withValues(alpha: 0.18 * brightness),
    );
    paint.color = Colors.white;
    final glowBounds = Rect.fromCircle(center: center, radius: radius * 1.25);
    paint.shader = RadialGradient(
      colors: [
        gold.withValues(alpha: 0.45 * brightness),
        aqua.withValues(alpha: 0.17 * brightness),
        aqua.withValues(alpha: 0),
      ],
    ).createShader(glowBounds);
    canvas.drawOval(glowBounds, paint);
    paint.shader = null;

    for (var i = 0; i < trail.length; i++) {
      final weight = 1 - i / trail.length;
      paint.color = gold.withValues(alpha: weight * brightness * 0.70);
      canvas.drawCircle(trail[i], radius * 0.12 * weight, paint);
    }

    // Two staggered waves of little four-point stars fan out at the reveal.
    for (var i = 0; i < 12; i++) {
      final age = (progress - 0.17 - (i.isOdd ? 0.15 : 0)) / 0.54;
      if (age <= 0 || age >= 1) continue;
      final angle = i * math.pi / 6 + 0.52 * age;
      final drift = Offset(math.cos(angle), math.sin(angle));
      final point = center + drift * (radius * (0.55 + 0.62 * age));
      final r = radius * (i.isOdd ? 0.073 : 0.11) * math.sin(math.pi * age);
      final star =
          Path()
            ..moveTo(point.dx, point.dy - r)
            ..relativeLineTo(r * 0.24, r * 0.72)
            ..relativeLineTo(r * 0.58, r * 0.28)
            ..relativeLineTo(-r * 0.58, r * 0.28)
            ..relativeLineTo(-r * 0.24, r * 0.72)
            ..relativeLineTo(-r * 0.24, -r * 0.72)
            ..relativeLineTo(-r * 0.58, -r * 0.28)
            ..relativeLineTo(r * 0.58, -r * 0.28)
            ..close();
      paint.color = i.isOdd ? aqua : gold;
      canvas.drawPath(star, paint);
    }
  }

  @override
  bool shouldRepaint(_WandSparks oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.center != center;
}
