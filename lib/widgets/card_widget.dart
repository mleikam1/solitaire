import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../appearance/appearance.dart';
import '../models/card_model.dart';

class CardWidget extends StatelessWidget {
  final PlayingCard card;
  final double width;
  final double height;
  final DeckStyle? deck;

  const CardWidget({
    super.key,
    required this.card,
    required this.width,
    required this.height,
    this.deck,
  });

  @override
  Widget build(BuildContext context) {
    final activeDeck =
        deck ??
        context.select<AppearanceController?, DeckStyle?>(
          (appearance) => appearance?.deck,
        );
    final asset =
        card.isFaceUp ? activeDeck?.faceAsset(card) : activeDeck?.backAsset;
    final radius = BorderRadius.circular(asset == null ? 6 : width * 0.045);
    return Semantics(
      image: true,
      label:
          card.isFaceUp
              ? '${card.displayValue} of ${card.suit.name}'
              : 'Face-down card',
      excludeSemantics: true,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: asset == null ? Colors.white : null,
          borderRadius: radius,
          border:
              asset == null
                  ? Border.all(
                    color: Colors.black.withValues(alpha: 0.18),
                    width: 1.4,
                  )
                  : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              offset: const Offset(1, 2),
              blurRadius: 2,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child:
            asset == null
                ? (card.isFaceUp ? _buildFront() : _buildBack(radius))
                : Image.asset(
                  asset,
                  fit: BoxFit.contain,
                  cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                      .ceil()
                      .clamp(1, 500),
                ),
      ),
    );
  }

  Widget _buildFront() {
    final color = card.suitColor;
    final glyph = card.suitGlyph;
    final rankText = card.displayValue;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final padding = max(4.0, maxWidth * 0.12);
        final innerWidth = max(1.0, maxWidth - padding * 2);
        final innerHeight = max(1.0, maxHeight - padding * 2);
        final centerGlyphSize = min(innerWidth, innerHeight) * 0.34;
        final isWideRank = rankText.length > 1;
        final rankFontSize = max(10.0, innerWidth * (isWideRank ? 0.55 : 0.7));
        final cornerSuitFontSize = max(9.0, innerWidth * 0.45);
        final cornerBoxWidth = max(innerWidth * 0.42, 16.0);
        final topInset = innerHeight * 0.04;

        return Padding(
          padding: EdgeInsets.all(padding),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: topInset,
                left: 0,
                child: SizedBox(
                  width: cornerBoxWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        alignment: Alignment.topLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          rankText,
                          style: TextStyle(
                            color: color,
                            fontSize: rankFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        alignment: Alignment.topLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          glyph,
                          style: TextStyle(
                            color: color,
                            fontSize: cornerSuitFontSize,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: topInset,
                right: 0,
                child: SizedBox(
                  width: cornerBoxWidth,
                  child: FittedBox(
                    alignment: Alignment.topRight,
                    fit: BoxFit.scaleDown,
                    child: Text(
                      glyph,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.8),
                        fontSize: cornerSuitFontSize,
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: centerGlyphSize,
                  height: centerGlyphSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.08),
                  ),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        glyph,
                        style: TextStyle(
                          color: color,
                          fontSize: centerGlyphSize * 0.7,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBack(BorderRadius radius) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF3C63FF).withValues(alpha: 0.8),
        borderRadius: radius,
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      child: const Center(
        child: Icon(Icons.star, color: Colors.white, size: 26),
      ),
    );
  }
}
