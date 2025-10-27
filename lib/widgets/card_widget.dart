import 'dart:math';

import 'package:flutter/material.dart';

import '../models/card_model.dart';

class CardWidget extends StatelessWidget {
  final PlayingCard card;
  final double width;
  final double height;

  const CardWidget({
    super.key,
    required this.card,
    required this.width,
    required this.height,
  });

  String _suitGlyph(Suit suit) {
    switch (suit) {
      case Suit.hearts:
        return '♥';
      case Suit.diamonds:
        return '♦';
      case Suit.spades:
        return '♠';
      case Suit.clubs:
        return '♣';
    }
  }

  Color _suitColor(Suit suit) {
    switch (suit) {
      case Suit.hearts:
      case Suit.diamonds:
        return Colors.red;
      case Suit.spades:
      case Suit.clubs:
        return Colors.black;
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(6);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        border: Border.all(
          color: Colors.black.withOpacity(0.18),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            offset: const Offset(1, 2),
            blurRadius: 2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: card.isFaceUp ? _buildFront() : _buildBack(radius),
    );
  }

  Widget _buildFront() {
    final color = _suitColor(card.suit);
    final glyph = _suitGlyph(card.suit);

    // Rank text
    String rankText;
    switch (card.rank) {
      case 1:
        rankText = 'A';
        break;
      case 11:
        rankText = 'J';
        break;
      case 12:
        rankText = 'Q';
        break;
      case 13:
        rankText = 'K';
        break;
      default:
        rankText = card.rank.toString();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final padding = max(4.0, maxWidth * 0.12);
        final innerWidth = max(1.0, maxWidth - padding * 2);
        final innerHeight = max(1.0, maxHeight - padding * 2);
        final largeGlyphSize = min(innerWidth, innerHeight) * 0.55;
        final isWideRank = rankText.length > 1;
        final rankFontSize =
            max(10.0, innerWidth * (isWideRank ? 0.55 : 0.7));
        final cornerSuitFontSize = max(9.0, innerWidth * 0.45);
        final topSpacing = max(4.0, innerHeight * 0.08);
        final cornerBoxWidth = max(innerWidth * 0.45, 18.0);

        return Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
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
                  const SizedBox(width: 4),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: SizedBox(
                        width: cornerBoxWidth,
                        child: FittedBox(
                          alignment: Alignment.topRight,
                          fit: BoxFit.scaleDown,
                          child: Text(
                            glyph,
                            style: TextStyle(
                              color: color.withOpacity(0.8),
                              fontSize: cornerSuitFontSize,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: topSpacing),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      glyph,
                      style: TextStyle(
                        color: color,
                        fontSize: largeGlyphSize,
                        fontWeight: FontWeight.w700,
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
        color: const Color(0xFF3C63FF).withOpacity(0.8),
        borderRadius: radius,
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      child: const Center(
        child: Icon(Icons.star, color: Colors.white, size: 26),
      ),
    );
  }
}
