import 'dart:math';
import 'package:flutter/widgets.dart';

class BoardMetrics {
  final double cardWidth;
  final double cardHeight;
  final double hGap;
  final double vGapFaceUp;
  final double vGapFaceDown;

  BoardMetrics({
    required this.cardWidth,
    required this.cardHeight,
    required this.hGap,
    required this.vGapFaceUp,
    required this.vGapFaceDown,
  });

  static const _columns = 7;
  static const _aspect = 64 / 89; // classic poker card ~0.718

  static BoardMetrics fromConstraints(BoxConstraints c) {
    final w = c.maxWidth;

    // Outer padding inside the game board (keeps distance from sides)
    const outerPad = 12.0;

    // Horizontal gap between columns
    final minGap = 6.0;
    final maxGap = 14.0;

    // Try to pick a nice gap, then clamp
    var guessGap = w * 0.012;
    final hGap = guessGap.clamp(minGap, maxGap);

    // Compute usable width and card width
    final usable = max(0.0, w - outerPad * 2 - hGap * (_columns - 1));
    final rawCardW = usable / _columns;
    // Clamp final card width to sensible min
    final cardWidth = max(44.0, rawCardW);

    final cardHeight = cardWidth / _aspect;

    // Vertical overlaps for stacks
    final vGapFaceUp = (cardHeight * 0.28).clamp(18.0, 36.0);
    final vGapFaceDown = (cardHeight * 0.18).clamp(10.0, 26.0);

    return BoardMetrics(
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      hGap: hGap,
      vGapFaceUp: vGapFaceUp,
      vGapFaceDown: vGapFaceDown,
    );
  }
}
