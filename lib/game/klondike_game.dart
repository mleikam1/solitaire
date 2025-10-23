import 'dart:math';
import 'package:flutter/material.dart';
import '../models/card_model.dart';

/// Klondike Solitaire core state + rules.
/// Public helpers are exposed for the UI (drag/drop validation & execution).
class KlondikeGame extends ChangeNotifier {
  // Piles
  final List<PlayingCard> _stock = [];
  final List<PlayingCard> _waste = [];
  final List<List<PlayingCard>> _foundations =
  List.generate(4, (_) => <PlayingCard>[]);
  final List<List<PlayingCard>> _tableau =
  List.generate(7, (_) => <PlayingCard>[]);

  // Stats
  int _score = 0;
  int _moves = 0;

  // Power-ups
  int freezeCount = 2;
  int wandCount = 3;

  final List<_GameSnapshot> _history = [];
  static const int _historyLimit = 200;

  // ===== Getters used by UI =====
  int get score => _score;
  int get moves => _moves;
  List<List<PlayingCard>> get tableau => _tableau;
  bool get canUndo => _history.isNotEmpty;

  PlayingCard? get stockTop => _stock.isEmpty ? null : _stock.last;
  PlayingCard? get wasteTop => _waste.isEmpty ? null : _waste.last;

  PlayingCard? foundationTop(int i) {
    final pile = _foundations[i];
    return pile.isEmpty ? null : pile.last;
  }

  KlondikeGame() {
    newDeal();
  }

  // ===== New Deal =====
  void newDeal() {
    _history.clear();
    _stock.clear();
    _waste.clear();
    for (final f in _foundations) f.clear();
    for (final t in _tableau) t.clear();

    final deck = _buildDeck()..shuffle(Random());

    // tableau: col i gets i+1, top is face up
    for (int col = 0; col < 7; col++) {
      for (int j = 0; j <= col; j++) {
        final c = deck.removeLast();
        c.isFaceUp = j == col;
        _tableau[col].add(c);
      }
    }

    // rest to stock (face down)
    while (deck.isNotEmpty) {
      final c = deck.removeLast();
      c.isFaceUp = false;
      _stock.add(c);
    }

    _score = 0;
    _moves = 0;
    notifyListeners();
  }

  List<PlayingCard> _buildDeck() {
    final deck = <PlayingCard>[];
    for (final s in Suit.values) {
      for (int r = 1; r <= 13; r++) {
        deck.add(PlayingCard(rank: r, suit: s));
      }
    }
    return deck;
  }

  // ===== Stock / Waste =====
  void drawFromStock() {
    if (_stock.isNotEmpty) {
      _saveSnapshot();
      final c = _stock.removeLast();
      c.isFaceUp = true;
      _waste.add(c);
      _moves++;
      notifyListeners();
      return;
    }
    if (_stock.isEmpty && _waste.isNotEmpty) {
      _saveSnapshot();
      while (_waste.isNotEmpty) {
        final c = _waste.removeLast();
        c.isFaceUp = false;
        _stock.add(c);
      }
      _moves++;
      notifyListeners();
    }
  }

  // ===== Taps =====
  void tapCard(PlayingCard card) {
    // Flip facedown top in tableau
    final tIdx = _tableauIndexOf(card);
    if (tIdx != null &&
        !card.isFaceUp &&
        identical(_tableau[tIdx].last, card)) {
      _saveSnapshot();
      card.isFaceUp = true;
      _score += 5;
      notifyListeners();
      return;
    }

    // Try foundation first
    if (_tryMoveToFoundation(card, onBeforeMove: _saveSnapshot)) {
      _moves++;
      notifyListeners();
      return;
    }
    // Then tableau
    if (_tryMoveToTableau(card, onBeforeMove: _saveSnapshot)) {
      _moves++;
      notifyListeners();
    }
  }

  // ===== Public drag/drop helpers =====

  /// Rule check for placing [movingTop] (top of a stack) onto [destTop] (may be null).
  bool canPlaceOnTableau(PlayingCard? destTop, PlayingCard movingTop) {
    if (destTop == null) return movingTop.rank == 13; // King on empty
    final altColor = _isRed(destTop.suit) != _isRed(movingTop.suit);
    final desc = movingTop.rank == destTop.rank - 1;
    return altColor && desc;
  }

  /// Execute a stack move to a tableau column.
  /// Handles scoring, flipping, and notifying listeners.
  bool moveStackToTableau(List<PlayingCard> stack, int destCol) {
    if (stack.isEmpty) return false;
    final movingTop = stack.first;
    final dest = _tableau[destCol];
    if (!canPlaceOnTableau(dest.isEmpty ? null : dest.last, movingTop)) {
      return false;
    }
    _saveSnapshot();
    _removeStack(stack);
    dest.addAll(stack);
    _score += 3;
    _moves++;
    _maybeFlipAfterRemoval(stack.first);
    notifyListeners();
    return true;
  }

  // ===== Foundations =====
  bool _tryMoveToFoundation(PlayingCard card,
      {VoidCallback? onBeforeMove}) {
    final idx = _foundationIndexForSuit(card.suit);
    final dest = _foundations[idx];

    if (dest.isEmpty) {
      if (card.rank == 1) {
        onBeforeMove?.call();
        _removeFromSource(card);
        dest.add(card);
        _score += 10;
        _maybeFlipAfterRemoval(card);
        return true;
      }
      return false;
    } else {
      final top = dest.last;
      if (top.suit == card.suit && card.rank == top.rank + 1) {
        onBeforeMove?.call();
        _removeFromSource(card);
        dest.add(card);
        _score += 10;
        _maybeFlipAfterRemoval(card);
        return true;
      }
    }
    return false;
  }

  // ===== Tableau moves (tap auto) =====
  bool _tryMoveToTableau(PlayingCard card,
      {VoidCallback? onBeforeMove}) {
    final stack = _stackFrom(card);
    for (int i = 0; i < 7; i++) {
      final dest = _tableau[i];
      if (canPlaceOnTableau(dest.isEmpty ? null : dest.last, card)) {
        onBeforeMove?.call();
        _removeStack(stack);
        dest.addAll(stack);
        _score += 3;
        _maybeFlipAfterRemoval(card);
        return true;
      }
    }
    return false;
  }

  // ===== Helpers =====
  int? _tableauIndexOf(PlayingCard c) {
    for (int i = 0; i < 7; i++) {
      if (_tableau[i].contains(c)) return i;
    }
    return null;
  }

  List<PlayingCard> _stackFrom(PlayingCard topCard) {
    final tIdx = _tableauIndexOf(topCard);
    if (tIdx == null) return [topCard]; // from waste/foundation (solo)
    final col = _tableau[tIdx];
    final start = col.indexOf(topCard);
    return List<PlayingCard>.from(col.getRange(start, col.length));
  }

  void _removeFromSource(PlayingCard c) {
    final tIdx = _tableauIndexOf(c);
    if (tIdx != null) {
      _tableau[tIdx].remove(c);
      return;
    }
    if (_waste.isNotEmpty && identical(_waste.last, c)) {
      _waste.removeLast();
    }
  }

  void _removeStack(List<PlayingCard> stack) {
    final first = stack.first;
    final tIdx = _tableauIndexOf(first);
    if (tIdx != null) {
      final col = _tableau[tIdx];
      col.removeRange(col.indexOf(first), col.indexOf(first) + stack.length);
      return;
    }
    if (_waste.isNotEmpty && identical(_waste.last, first)) {
      _waste.removeLast();
    }
  }

  void _maybeFlipAfterRemoval(PlayingCard removedTop) {
    final tIdx = _tableauIndexOf(removedTop);
    if (tIdx == null) return;
    final col = _tableau[tIdx];
    if (col.isNotEmpty && !col.last.isFaceUp) {
      col.last.isFaceUp = true;
      _score += 5;
    }
  }

  bool _isRed(Suit s) => s == Suit.hearts || s == Suit.diamonds;

  int _foundationIndexForSuit(Suit s) {
    switch (s) {
      case Suit.hearts:
        return 0;
      case Suit.diamonds:
        return 1;
      case Suit.clubs:
        return 2;
      case Suit.spades:
        return 3;
    }
  }

  // ===== Power-up: Wand (auto-foundation) =====
  void activateWand() {
    if (wandCount <= 0) return;

    bool movedAny = false;
    bool snapshotSaved = false;
    bool moved;
    do {
      moved = false;

      // waste top
      final w = wasteTop;
      if (w != null &&
          _tryMoveToFoundation(w, onBeforeMove: () {
            if (!snapshotSaved) {
              _saveSnapshot();
              snapshotSaved = true;
            }
          })) {
        moved = true;
        movedAny = true;
      }

      // tableau tops
      for (final col in _tableau) {
        if (col.isNotEmpty && col.last.isFaceUp) {
          if (_tryMoveToFoundation(col.last, onBeforeMove: () {
            if (!snapshotSaved) {
              _saveSnapshot();
              snapshotSaved = true;
            }
          })) {
            moved = true;
            movedAny = true;
          }
        }
      }
    } while (moved);

    if (movedAny) {
      wandCount--;
      _moves++;
      notifyListeners();
    }
  }

  bool undo() {
    if (_history.isEmpty) return false;
    final snapshot = _history.removeLast();
    _restoreSnapshot(snapshot);
    notifyListeners();
    return true;
  }

  void _saveSnapshot() {
    _history.add(
      _GameSnapshot(
        stock: _clonePile(_stock),
        waste: _clonePile(_waste),
        tableau: _tableau.map(_clonePile).toList(),
        foundations: _foundations.map(_clonePile).toList(),
        score: _score,
        moves: _moves,
        freezeCount: freezeCount,
        wandCount: wandCount,
      ),
    );
    if (_history.length > _historyLimit) {
      _history.removeAt(0);
    }
  }

  List<PlayingCard> _clonePile(List<PlayingCard> source) =>
      source.map((c) => c.clone()).toList();

  void _restoreSnapshot(_GameSnapshot snapshot) {
    _replacePile(_stock, snapshot.stock);
    _replacePile(_waste, snapshot.waste);

    for (int i = 0; i < _foundations.length; i++) {
      _replacePile(_foundations[i], snapshot.foundations[i]);
    }

    for (int i = 0; i < _tableau.length; i++) {
      _replacePile(_tableau[i], snapshot.tableau[i]);
    }

    _score = snapshot.score;
    _moves = snapshot.moves;
    freezeCount = snapshot.freezeCount;
    wandCount = snapshot.wandCount;
  }

  void _replacePile(List<PlayingCard> target, List<PlayingCard> source) {
    target
      ..clear()
      ..addAll(source.map((c) => c.clone()));
  }
}

class _GameSnapshot {
  final List<PlayingCard> stock;
  final List<PlayingCard> waste;
  final List<List<PlayingCard>> tableau;
  final List<List<PlayingCard>> foundations;
  final int score;
  final int moves;
  final int freezeCount;
  final int wandCount;

  _GameSnapshot({
    required this.stock,
    required this.waste,
    required this.tableau,
    required this.foundations,
    required this.score,
    required this.moves,
    required this.freezeCount,
    required this.wandCount,
  });
}
