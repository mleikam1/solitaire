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
  static const int _deckSize = 52;

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
    if (destTop == null) return true; // Relaxed: any card can fill an empty column.
    return movingTop.rank == destTop.rank - 1; // Relaxed: only descending order required.
  }

  bool canPlaceOnFoundation(int foundationIndex, PlayingCard moving) {
    if (foundationIndex < 0 || foundationIndex >= _foundations.length) {
      return false;
    }
    if (_foundationIndexForSuit(moving.suit) != foundationIndex) {
      return false;
    }
    final dest = _foundations[foundationIndex];
    if (dest.isEmpty) return moving.rank == 1;
    final top = dest.last;
    return top.suit == moving.suit && moving.rank == top.rank + 1;
  }

  bool moveCardToFoundation(PlayingCard card, int foundationIndex) {
    if (!canPlaceOnFoundation(foundationIndex, card)) {
      return false;
    }
    _saveSnapshot();
    final expectedTableau = _tableauIndexOf(card);
    final sourceIdx = _removeFromSource(card);
    if ((expectedTableau != null && sourceIdx != expectedTableau) ||
        (expectedTableau == null && sourceIdx != null)) {
      _restoreLastSnapshotAndNotify();
      return false;
    }
    _foundations[foundationIndex].add(card);
    _score += 10;
    _moves++;
    _maybeFlipAfterRemoval(sourceIdx);
    if (!_hasValidCardCount()) {
      _restoreLastSnapshotAndNotify();
      return false;
    }
    notifyListeners();
    return true;
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

    final sourceIdx = _tableauIndexOf(movingTop);
    if (sourceIdx != null && sourceIdx == destCol) {
      // Dropping back onto the same column should leave the stack untouched.
      return false;
    }

    _saveSnapshot();
    final removedFrom = _removeStack(stack);
    if ((sourceIdx != null && removedFrom != sourceIdx) ||
        (sourceIdx != null && removedFrom == null) ||
        (sourceIdx == null && removedFrom != null)) {
      _restoreLastSnapshotAndNotify();
      return false;
    }
    _maybeFlipAfterRemoval(removedFrom);
    dest.addAll(stack);
    _score += 3;
    _moves++;
    if (!_hasValidCardCount()) {
      _restoreLastSnapshotAndNotify();
      return false;
    }
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
        final sourceIdx = _removeFromSource(card);
        dest.add(card);
        _score += 10;
        _maybeFlipAfterRemoval(sourceIdx);
        return true;
      }
      return false;
    } else {
      final top = dest.last;
      if (top.suit == card.suit && card.rank == top.rank + 1) {
        onBeforeMove?.call();
        final sourceIdx = _removeFromSource(card);
        dest.add(card);
        _score += 10;
        _maybeFlipAfterRemoval(sourceIdx);
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
        final sourceIdx = _removeStack(stack);
        dest.addAll(stack);
        _score += 3;
        _maybeFlipAfterRemoval(sourceIdx);
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

  int? _removeFromSource(PlayingCard c) {
    final tIdx = _tableauIndexOf(c);
    if (tIdx != null) {
      _tableau[tIdx].remove(c);
      return tIdx;
    }
    if (_waste.isNotEmpty && identical(_waste.last, c)) {
      _waste.removeLast();
    }
    final fIdx = _foundationIndexOf(c);
    if (fIdx != null && identical(_foundations[fIdx].last, c)) {
      _foundations[fIdx].removeLast();
    }
    return null;
  }

  int? _removeStack(List<PlayingCard> stack) {
    final first = stack.first;
    final tIdx = _tableauIndexOf(first);
    if (tIdx != null) {
      final col = _tableau[tIdx];
      final start = col.indexOf(first);
      col.removeRange(start, start + stack.length);
      return tIdx;
    }
    if (_waste.isNotEmpty && identical(_waste.last, first)) {
      _waste.removeLast();
    }
    final fIdx = _foundationIndexOf(first);
    if (fIdx != null && stack.length == 1 &&
        identical(_foundations[fIdx].last, first)) {
      _foundations[fIdx].removeLast();
    }
    return null;
  }

  void _maybeFlipAfterRemoval(int? tIdx) {
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

  int? _foundationIndexOf(PlayingCard c) {
    for (int i = 0; i < _foundations.length; i++) {
      if (_foundations[i].contains(c)) return i;
    }
    return null;
  }

  // ===== Power-up: Wand (auto-play with magical extraction) =====
  MagicWandPlan? planMagicWand() {
    if (wandCount <= 0) return null;

    final action = _findMagicWandAction();
    if (action == null) return null;

    return MagicWandPlan([action]);
  }

  bool executeMagicWand(MagicWandPlan plan) {
    if (plan.actions.isEmpty || wandCount <= 0) return false;

    bool movedAny = false;
    _saveSnapshot();

    for (final action in plan.actions) {
      movedAny |= _executeWandAction(action);
    }

    if (!movedAny) {
      _history.removeLast();
      return false;
    }

    wandCount--;
    _moves++;
    notifyListeners();
    return true;
  }

  MagicWandAction? _findMagicWandAction() {
    // Prefer straightforward foundation moves from accessible cards.
    final directFoundation = _findAccessibleFoundationMove();
    if (directFoundation != null) return directFoundation;

    // Try extracting a buried card directly to a foundation pile.
    final hiddenFoundation = _findHiddenFoundationMove();
    if (hiddenFoundation != null) return hiddenFoundation;

    // Move a visible card to another tableau column.
    final tableauRebuild = _findAccessibleTableauMove();
    if (tableauRebuild != null) return tableauRebuild;

    // Pull a hidden card out and drop it into a tableau column.
    final hiddenTableau = _findHiddenToTableauMove();
    if (hiddenTableau != null) return hiddenTableau;

    // Flip the top of a tableau column if still face-down.
    final flip = _findFlipAction();
    if (flip != null) return flip;

    // Draw a fresh card or recycle the waste.
    final drawOrRecycle = _findStockOrRecycleAction();
    return drawOrRecycle;
  }

  MagicWandAction? _findAccessibleFoundationMove() {
    final waste = wasteTop;
    if (waste != null) {
      final fIdx = _foundationIndexForSuit(waste.suit);
      if (canPlaceOnFoundation(fIdx, waste)) {
        return MagicWandAction(
          type: MagicWandActionType.moveToFoundation,
          cards: [waste],
          from: WandLocation(
            pile: WandPileType.waste,
            index: 0,
            depth: _waste.isEmpty ? 0 : _waste.length - 1,
          ),
          to: WandLocation(
            pile: WandPileType.foundation,
            index: fIdx,
            depth: _foundations[fIdx].length,
          ),
        );
      }
    }

    for (int col = 0; col < _tableau.length; col++) {
      final column = _tableau[col];
      if (column.isEmpty) continue;
      final top = column.last;
      if (!top.isFaceUp) continue;
      final fIdx = _foundationIndexForSuit(top.suit);
      if (canPlaceOnFoundation(fIdx, top)) {
        return MagicWandAction(
          type: MagicWandActionType.moveToFoundation,
          cards: [top],
          from: WandLocation(
            pile: WandPileType.tableau,
            index: col,
            depth: column.length - 1,
          ),
          to: WandLocation(
            pile: WandPileType.foundation,
            index: fIdx,
            depth: _foundations[fIdx].length,
          ),
        );
      }
    }

    return null;
  }

  MagicWandAction? _findHiddenFoundationMove() {
    for (int col = 0; col < _tableau.length; col++) {
      final column = _tableau[col];
      for (int depth = 0; depth < column.length; depth++) {
        final card = column[depth];
        final isBlocked = depth != column.length - 1;
        final isHidden = !card.isFaceUp;
        if (!isBlocked && !isHidden) continue;

        final fIdx = _foundationIndexForSuit(card.suit);
        if (canPlaceOnFoundation(fIdx, card)) {
          return MagicWandAction(
            type: MagicWandActionType.moveToFoundation,
            cards: [card],
            from: WandLocation(
              pile: WandPileType.tableau,
              index: col,
              depth: depth,
            ),
            to: WandLocation(
              pile: WandPileType.foundation,
              index: fIdx,
              depth: _foundations[fIdx].length,
            ),
            revealOnPickup: !card.isFaceUp,
          );
        }
      }
    }

    return null;
  }

  MagicWandAction? _findAccessibleTableauMove() {
    final waste = wasteTop;
    if (waste != null) {
      for (int dest = 0; dest < _tableau.length; dest++) {
        final destPile = _tableau[dest];
        final destTop = destPile.isEmpty ? null : destPile.last;
        if (canPlaceOnTableau(destTop, waste)) {
          return MagicWandAction(
            type: MagicWandActionType.moveToTableau,
            cards: [waste],
            from: WandLocation(
              pile: WandPileType.waste,
              index: 0,
              depth: _waste.isEmpty ? 0 : _waste.length - 1,
            ),
            to: WandLocation(
              pile: WandPileType.tableau,
              index: dest,
              depth: _tableau[dest].length,
            ),
          );
        }
      }
    }

    for (int src = 0; src < _tableau.length; src++) {
      final column = _tableau[src];
      if (column.isEmpty) continue;
      for (int depth = 0; depth < column.length; depth++) {
        final card = column[depth];
        if (!card.isFaceUp) continue;
        final stack = List<PlayingCard>.from(column.getRange(depth, column.length));
        final movingTop = stack.first;
        for (int dest = 0; dest < _tableau.length; dest++) {
          if (dest == src) continue;
          final destPile = _tableau[dest];
          final destTop = destPile.isEmpty ? null : destPile.last;
          if (canPlaceOnTableau(destTop, movingTop)) {
            return MagicWandAction(
              type: MagicWandActionType.moveToTableau,
              cards: stack,
              from: WandLocation(
                pile: WandPileType.tableau,
                index: src,
                depth: depth,
              ),
              to: WandLocation(
                pile: WandPileType.tableau,
                index: dest,
                depth: _tableau[dest].length,
              ),
            );
          }
        }
      }
    }

    return null;
  }

  MagicWandAction? _findHiddenToTableauMove() {
    for (int src = 0; src < _tableau.length; src++) {
      final column = _tableau[src];
      for (int depth = 0; depth < column.length; depth++) {
        final card = column[depth];
        final isBlocked = depth != column.length - 1;
        final isHidden = !card.isFaceUp;
        if (!isBlocked && !isHidden) continue;

        for (int dest = 0; dest < _tableau.length; dest++) {
          if (dest == src) continue;
          final destPile = _tableau[dest];
          final destTop = destPile.isEmpty ? null : destPile.last;
          if (canPlaceOnTableau(destTop, card)) {
            return MagicWandAction(
              type: MagicWandActionType.moveToTableau,
              cards: [card],
              from: WandLocation(
                pile: WandPileType.tableau,
                index: src,
                depth: depth,
              ),
              to: WandLocation(
                pile: WandPileType.tableau,
                index: dest,
                depth: _tableau[dest].length,
              ),
              revealOnPickup: !card.isFaceUp,
            );
          }
        }
      }
    }

    return null;
  }

  MagicWandAction? _findFlipAction() {
    for (int col = 0; col < _tableau.length; col++) {
      final column = _tableau[col];
      if (column.isEmpty) continue;
      final top = column.last;
      if (!top.isFaceUp) {
        return MagicWandAction(
          type: MagicWandActionType.flipTableau,
          cards: [top],
          from: WandLocation(
            pile: WandPileType.tableau,
            index: col,
            depth: column.length - 1,
          ),
        );
      }
    }
    return null;
  }

  MagicWandAction? _findStockOrRecycleAction() {
    if (_stock.isNotEmpty) {
      final card = _stock.last;
      return MagicWandAction(
        type: MagicWandActionType.drawFromStock,
        cards: [card],
        from: WandLocation(
          pile: WandPileType.stock,
          index: 0,
          depth: _stock.length - 1,
        ),
        to: WandLocation(
          pile: WandPileType.waste,
          index: 0,
          depth: _waste.length,
        ),
        revealOnPickup: true,
      );
    }

    if (_stock.isEmpty && _waste.isNotEmpty) {
      return const MagicWandAction(
        type: MagicWandActionType.recycleWaste,
      );
    }

    return null;
  }

  bool _executeWandAction(MagicWandAction action) {
    switch (action.type) {
      case MagicWandActionType.moveToFoundation:
        return _executeMoveToFoundation(action);
      case MagicWandActionType.moveToTableau:
        return _executeMoveToTableau(action);
      case MagicWandActionType.drawFromStock:
        return _executeDrawFromStock(action);
      case MagicWandActionType.recycleWaste:
        return _executeRecycleWaste();
      case MagicWandActionType.flipTableau:
        return _executeFlip(action);
    }
  }

  bool _executeMoveToFoundation(MagicWandAction action) {
    final from = action.from;
    final to = action.to;
    if (from == null || to == null) return false;
    if (!_removeFromLocation(from, action.cards)) return false;

    for (final card in action.cards) {
      if (action.revealOnPickup && !card.isFaceUp) {
        card.isFaceUp = true;
        _score += 5;
      }
    }

    final dest = _foundations[to.index];
    dest.addAll(action.cards);
    _score += 10 * action.cards.length;
    return true;
  }

  bool _executeMoveToTableau(MagicWandAction action) {
    final from = action.from;
    final to = action.to;
    if (from == null || to == null) return false;
    if (!_removeFromLocation(from, action.cards)) return false;

    for (final card in action.cards) {
      if (action.revealOnPickup && !card.isFaceUp) {
        card.isFaceUp = true;
        _score += 5;
      }
    }

    final dest = _tableau[to.index];
    dest.addAll(action.cards);
    _score += 3;
    return true;
  }

  bool _executeDrawFromStock(MagicWandAction action) {
    if (action.cards.isEmpty) return false;
    final card = action.cards.first;
    if (!_stock.remove(card)) return false;

    if (action.revealOnPickup && !card.isFaceUp) {
      card.isFaceUp = true;
    }

    _waste.add(card);
    return true;
  }

  bool _executeRecycleWaste() {
    if (_waste.isEmpty) return false;
    while (_waste.isNotEmpty) {
      final card = _waste.removeLast();
      card.isFaceUp = false;
      _stock.add(card);
    }
    return true;
  }

  bool _executeFlip(MagicWandAction action) {
    if (action.cards.isEmpty) return false;
    final card = action.cards.first;
    if (card.isFaceUp) return false;
    card.isFaceUp = true;
    _score += 5;
    return true;
  }

  bool _removeFromLocation(WandLocation from, List<PlayingCard> cards) {
    switch (from.pile) {
      case WandPileType.tableau:
        final column = _tableau[from.index];
        if (cards.isEmpty) return false;
        final first = cards.first;
        final startIndex = column.indexOf(first);
        if (startIndex == -1) return false;
        column.removeRange(startIndex, startIndex + cards.length);
        _maybeFlipAfterRemoval(from.index);
        return true;
      case WandPileType.waste:
        if (cards.length != 1) return false;
        if (_waste.isEmpty || !identical(_waste.last, cards.first)) {
          return false;
        }
        _waste.removeLast();
        return true;
      case WandPileType.foundation:
        if (cards.length != 1) return false;
        final pile = _foundations[from.index];
        if (pile.isEmpty || !identical(pile.last, cards.first)) {
          return false;
        }
        pile.removeLast();
        return true;
      case WandPileType.stock:
        if (cards.length != 1) return false;
        return _stock.remove(cards.first);
    }
  }

  HintSuggestion? computeHint() => _computeHint();

  bool get hasHintAvailable => _computeHint(previewOnly: true) != null;

  HintSuggestion? _computeHint({bool previewOnly = false}) {
    HintSuggestion _buildResult(
      HintActionType action, {
      List<PlayingCard> cards = const <PlayingCard>[],
      int? sourceTableau,
      int? destinationTableau,
      int? destinationFoundation,
      bool highlightStock = false,
    }) {
      if (previewOnly) {
        return HintSuggestion(
          action: action,
          sourceTableauIndex: sourceTableau,
          destinationTableauIndex: destinationTableau,
          destinationFoundationIndex: destinationFoundation,
          highlightStock: highlightStock,
        );
      }
      return HintSuggestion(
        action: action,
        cards: cards,
        sourceTableauIndex: sourceTableau,
        destinationTableauIndex: destinationTableau,
        destinationFoundationIndex: destinationFoundation,
        highlightStock: highlightStock,
      );
    }

    final wasteCard = wasteTop;
    if (wasteCard != null) {
      final foundationIndex = _foundationIndexForSuit(wasteCard.suit);
      if (canPlaceOnFoundation(foundationIndex, wasteCard)) {
        final cards =
            previewOnly ? const <PlayingCard>[] : <PlayingCard>[wasteCard];
        return _buildResult(
          HintActionType.moveToFoundation,
          cards: cards,
          destinationFoundation: foundationIndex,
        );
      }
    }

    for (int i = 0; i < _tableau.length; i++) {
      final column = _tableau[i];
      if (column.isEmpty) continue;
      final top = column.last;
      if (!top.isFaceUp) continue;
      final foundationIndex = _foundationIndexForSuit(top.suit);
      if (canPlaceOnFoundation(foundationIndex, top)) {
        final cards =
            previewOnly ? const <PlayingCard>[] : <PlayingCard>[top];
        return _buildResult(
          HintActionType.moveToFoundation,
          cards: cards,
          sourceTableau: i,
          destinationFoundation: foundationIndex,
        );
      }
    }

    for (int i = 0; i < _tableau.length; i++) {
      final column = _tableau[i];
      if (column.isNotEmpty && !column.last.isFaceUp) {
        final facedown = column.last;
        final cards =
            previewOnly ? const <PlayingCard>[] : <PlayingCard>[facedown];
        return _buildResult(
          HintActionType.flipTableauCard,
          cards: cards,
          sourceTableau: i,
        );
      }
    }

    if (wasteCard != null) {
      for (int dest = 0; dest < _tableau.length; dest++) {
        final destPile = _tableau[dest];
        if (canPlaceOnTableau(
            destPile.isEmpty ? null : destPile.last, wasteCard)) {
          final cards =
              previewOnly ? const <PlayingCard>[] : <PlayingCard>[wasteCard];
          return _buildResult(
            HintActionType.moveToTableau,
            cards: cards,
            destinationTableau: dest,
          );
        }
      }
    }

    for (int src = 0; src < _tableau.length; src++) {
      final column = _tableau[src];
      for (int row = 0; row < column.length; row++) {
        final card = column[row];
        if (!card.isFaceUp) continue;
        final stack = column.sublist(row);
        final movingTop = stack.first;
        for (int dest = 0; dest < _tableau.length; dest++) {
          if (dest == src) continue;
          final destPile = _tableau[dest];
          if (canPlaceOnTableau(
              destPile.isEmpty ? null : destPile.last, movingTop)) {
            final cards = previewOnly
                ? const <PlayingCard>[]
                : List<PlayingCard>.from(stack);
            return _buildResult(
              HintActionType.moveToTableau,
              cards: cards,
              sourceTableau: src,
              destinationTableau: dest,
            );
          }
        }
      }
    }

    if (_stock.isNotEmpty || _waste.isNotEmpty) {
      return _buildResult(
        HintActionType.drawFromStock,
        highlightStock: true,
      );
    }

    return null;
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

  void _restoreLastSnapshotAndNotify() {
    if (_history.isEmpty) {
      return;
    }
    final snapshot = _history.removeLast();
    _restoreSnapshot(snapshot);
    notifyListeners();
  }

  int get _boardCardCount {
    final foundationCount =
        _foundations.fold<int>(0, (sum, pile) => sum + pile.length);
    final tableauCount =
        _tableau.fold<int>(0, (sum, column) => sum + column.length);
    return _stock.length + _waste.length + foundationCount + tableauCount;
  }

  bool _hasValidCardCount() => _boardCardCount == _deckSize;

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

enum MagicWandActionType {
  moveToFoundation,
  moveToTableau,
  drawFromStock,
  recycleWaste,
  flipTableau,
}

enum WandPileType { stock, waste, foundation, tableau }

class WandLocation {
  const WandLocation({
    required this.pile,
    required this.index,
    required this.depth,
  });

  final WandPileType pile;
  final int index;
  final int depth;
}

class MagicWandAction {
  const MagicWandAction({
    required this.type,
    this.cards = const <PlayingCard>[],
    this.from,
    this.to,
    this.revealOnPickup = false,
  });

  final MagicWandActionType type;
  final List<PlayingCard> cards;
  final WandLocation? from;
  final WandLocation? to;
  final bool revealOnPickup;
}

class MagicWandPlan {
  const MagicWandPlan(this.actions);

  final List<MagicWandAction> actions;
}

class HintSuggestion {
  HintSuggestion({
    required this.action,
    List<PlayingCard> cards = const <PlayingCard>[],
    this.sourceTableauIndex,
    this.destinationTableauIndex,
    this.destinationFoundationIndex,
    this.highlightStock = false,
  }) : cards = List<PlayingCard>.unmodifiable(cards);

  final HintActionType action;
  final List<PlayingCard> cards;
  final int? sourceTableauIndex;
  final int? destinationTableauIndex;
  final int? destinationFoundationIndex;
  final bool highlightStock;
}

enum HintActionType {
  flipTableauCard,
  moveToFoundation,
  moveToTableau,
  drawFromStock,
}
