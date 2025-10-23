import 'package:flutter/material.dart';

enum Suit { hearts, diamonds, clubs, spades }

class PlayingCard {
  final int rank;
  final Suit suit;
  bool isFaceUp;

  PlayingCard({
    required this.rank,
    required this.suit,
    this.isFaceUp = false,
  });

  // ===== Display Value =====
  String get displayValue {
    switch (rank) {
      case 1:
        return 'A';
      case 11:
        return 'J';
      case 12:
        return 'Q';
      case 13:
        return 'K';
      default:
        return rank.toString();
    }
  }

  // ===== Suit Color =====
  Color get suitColor {
    switch (suit) {
      case Suit.hearts:
      case Suit.diamonds:
        return Colors.red;
      case Suit.spades:
      case Suit.clubs:
        return Colors.black;
    }
  }

  // ===== Suit Glyph (♥ ♦ ♠ ♣) =====
  String get suitGlyph {
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
}
