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
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            offset: const Offset(1, 2),
            blurRadius: 2,
          ),
        ],
      ),
      child: card.isFaceUp ? _buildFront() : _buildBack(),
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

    final largeGlyphSize = min(width, height) * 0.45;

    return Padding(
      padding: const EdgeInsets.all(6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rankText,
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    glyph,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                glyph,
                style: TextStyle(
                  color: color.withOpacity(0.8),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
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
  }

  Widget _buildBack() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF3C63FF).withOpacity(0.8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      child: const Center(
        child: Icon(Icons.star, color: Colors.white, size: 26),
      ),
    );
  }
}
