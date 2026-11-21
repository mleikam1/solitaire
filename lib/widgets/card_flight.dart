import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/card_model.dart';

/// A presentation-only Stack child. Start and end are the bounds of the
/// leading card in that Stack's coordinates. Offsets keep a tableau run fanned.
class CardFlight extends StatelessWidget {
  const CardFlight({
    super.key,
    required this.progress,
    required this.start,
    required this.end,
    required this.cards,
    required this.offsets,
    required this.flip,
    required this.buildCard,
  }) : assert(cards.length > 0),
       assert(cards.length == offsets.length),
       assert(!flip || cards.length == 1);

  static const moveDuration = Duration(milliseconds: 340);
  static const drawDuration = Duration(milliseconds: 400);

  final double progress;
  final Rect start;
  final Rect end;
  final List<PlayingCard> cards;
  final List<double> offsets;
  final bool flip;
  final Widget Function(PlayingCard card, bool faceUp) buildCard;

  @override
  Widget build(BuildContext context) {
    const contact = 0.72;
    final t = progress.clamp(0.0, 1.0);
    final travel = Curves.easeInOutCubic.transform((t / contact).clamp(0, 1));
    final rect = Rect.lerp(start, end, travel)!;
    final airborne = travel == 1 ? 0.0 : math.sin(math.pi * travel);
    final distance = (end.center - start.center).distance;
    final arc = math.min(
      rect.height * 0.26,
      distance * 0.18 + rect.width * 0.05,
    );

    // Compress once at contact, then rebound with diminishing amplitude.
    final landing = ((t - contact) / (1 - contact)).clamp(0.0, 1.0);
    final impact =
        math.sin(2 * math.pi * landing) *
        math.sin(math.pi * landing) *
        (1 - landing);
    final liftScale = 1 + 0.055 * airborne;
    final offset = Offset(0, -arc * airborne + rect.height * 0.035 * impact);
    final bank =
        ((end.center.dx - start.center.dx) / rect.width).clamp(-1, 1) *
        0.045 *
        airborne;

    // At the edge the visible side changes. The front starts edge-on in the
    // opposite direction and ends upright, so the rank is never mirrored.
    final turn = flip ? Curves.easeInOut.transform((t / 0.8).clamp(0, 1)) : 0.0;
    final showFront = t >= 0.4;
    final angle = flip ? math.pi * (showFront ? turn - 1 : turn) : 0.0;
    final pose =
        Matrix4.identity()
          ..setEntry(3, 2, flip ? 0.12 / rect.width : 0.0)
          ..rotateZ(bank)
          ..rotateY(angle)
          ..multiply(
            Matrix4.diagonal3Values(
              liftScale + impact * 0.045,
              liftScale - impact * 0.075,
              1,
            ),
          );
    final radius = BorderRadius.circular(rect.width * 0.055);

    return Positioned(
      left: rect.left + offset.dx,
      top: rect.top + offset.dy,
      width: rect.width,
      height: rect.height + offsets.last,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Transform(
            alignment: Alignment.topCenter,
            origin: Offset(0, rect.height / 2),
            transform: pose,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28 * airborne),
                    offset: Offset(0, rect.width * 0.10 * airborne),
                    blurRadius: rect.width * 0.16 * airborne,
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < cards.length; i++)
                    Positioned(
                      top: offsets[i],
                      width: rect.width,
                      height: rect.height,
                      child:
                          flip
                              ? DecoratedBox(
                                position: DecorationPosition.foreground,
                                decoration: BoxDecoration(
                                  borderRadius: radius,
                                  color: Colors.black.withValues(
                                    alpha: 0.17 * math.sin(angle).abs(),
                                  ),
                                ),
                                // Mount both sides at takeoff so a themed
                                // face asset can start decoding before the turn.
                                child: IndexedStack(
                                  index: showFront ? 1 : 0,
                                  sizing: StackFit.expand,
                                  children: [
                                    buildCard(cards[i], false),
                                    buildCard(cards[i], true),
                                  ],
                                ),
                              )
                              : buildCard(cards[i], cards[i].isFaceUp),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
