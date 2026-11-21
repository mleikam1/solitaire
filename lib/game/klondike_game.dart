import 'package:flutter/material.dart';
import '../models/card_model.dart';
import 'board_snapshot.dart';
import 'deal_spec.dart';

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

  late DealSpec _deal;
  DealSpec get deal => _deal;

  bool _startedFromSnapshot = false;

  /// A helper's finish belongs to the imported position. The origin survives
  /// undo until the player starts a new deal or imports another position.
  bool get startedFromSnapshot => _startedFromSnapshot;

  Object _position = Object();

  @override
  void notifyListeners() {
    _position = Object();
    super.notifyListeners();
  }

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
  bool get isWon => _foundations.every((pile) => pile.length == 13);

  PlayingCard? get stockTop => _stock.isEmpty ? null : _stock.last;
  PlayingCard? get wasteTop => _waste.isEmpty ? null : _waste.last;

  PlayingCard? foundationTop(int i) {
    final pile = _foundations[i];
    return pile.isEmpty ? null : pile.last;
  }

  KlondikeGame() {
    newDeal();
  }

  KlondikeGame.fromDeal(DealSpec deal) {
    startDeal(deal);
  }

  KlondikeGame.fromSnapshot(BoardSnapshot board) {
    restoreBoard(board);
  }

  // ===== New Deal =====
  void newDeal() {
    // Ordinary play carries remaining power-ups into the next deal.
    startDeal(DealSpec.random(
      initialFreezeCount: freezeCount,
      initialWandCount: wandCount,
    ));
  }

  void startDeal(DealSpec deal) {
    final deck = deal.shuffledDeck();
    _deal = deal;
    _startedFromSnapshot = false;
    freezeCount = deal.initialFreezeCount;
    wandCount = deal.initialWandCount;
    _history.clear();
    _stock.clear();
    _waste.clear();
    for (final f in _foundations) {
      f.clear();
    }
    for (final t in _tableau) {
      t.clear();
    }

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

  /// Capture the current position by value. The page owns the play clock.
  BoardSnapshot snapshot() => BoardSnapshot.capture(
    deal: _deal,
    stock: _stock,
    waste: _waste,
    foundations: _foundations,
    tableau: _tableau,
    score: _score,
    moves: _moves,
    freezeCount: freezeCount,
    wandCount: wandCount,
  );

  /// Install a validated position, with this position as the undo boundary.
  void restoreBoard(BoardSnapshot board) {
    List<PlayingCard> cards(List<SnapshotCard> pile) =>
        pile.map((c) => c.toPlayingCard()).toList();

    final position = _GameSnapshot(
      stock: cards(board.stock),
      waste: cards(board.waste),
      foundations: board.foundations.map(cards).toList(),
      tableau: board.tableau.map(cards).toList(),
      score: board.score,
      moves: board.moves,
      freezeCount: board.freezeCount,
      wandCount: board.wandCount,
    );
    _restoreSnapshot(position);
    _deal = board.deal;
    _startedFromSnapshot = true;
    _history.clear();
    notifyListeners();
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
      _recycleWaste();
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

    if (moveCardToFoundation(card, _foundationIndexForSuit(card.suit))) return;
    final stack = _stackFrom(card);
    for (int i = 0; i < _tableau.length; i++) {
      if (moveStackToTableau(stack, i)) return;
    }
  }

  // ===== Public drag/drop helpers =====

  bool _fitsOnTableau(PlayingCard? parent, PlayingCard child) {
    if (parent == null) return child.rank == 13;
    return parent.isFaceUp &&
        canBuildTableauPair(parent.rank, parent.suit, child.rank, child.suit);
  }

  bool canPlaceOnTableau(PlayingCard? destTop, PlayingCard movingTop) =>
      movingTop.isFaceUp && _fitsOnTableau(destTop, movingTop);

  bool _fitsOnFoundation(int index, PlayingCard card) {
    if (index != _foundationIndexForSuit(card.suit)) return false;
    final pile = _foundations[index];
    return card.rank == (pile.isEmpty ? 1 : pile.last.rank + 1);
  }

  bool canPlaceOnFoundation(int foundationIndex, PlayingCard moving) =>
      moving.isFaceUp && _fitsOnFoundation(foundationIndex, moving);

  bool canMoveCardToFoundation(PlayingCard card, int foundationIndex) =>
      canPlaceOnFoundation(foundationIndex, card) &&
      (identical(wasteTop, card) ||
          _tableau.any((col) => col.isNotEmpty && identical(col.last, card)));

  /// The exact exposed suffix of its original column, or one accessible
  /// waste/foundation card. Drag payloads can outlive a move or an undo.
  bool isMovableRun(List<PlayingCard> stack) {
    if (stack.isEmpty || !stack.first.isFaceUp) return false;
    final first = stack.first;
    final src = _tableauIndexOf(first);
    if (src == null) {
      return stack.length == 1 &&
          (identical(wasteTop, first) ||
              _foundations.any(
                (f) => f.isNotEmpty && identical(f.last, first),
              ));
    }
    final col = _tableau[src];
    final start = col.length - stack.length;
    if (start < 0 || !identical(col[start], first)) return false;
    for (int i = 1; i < stack.length; i++) {
      if (!identical(col[start + i], stack[i]) ||
          !canPlaceOnTableau(stack[i - 1], stack[i])) {
        return false;
      }
    }
    return true;
  }

  bool canMoveStackToTableau(List<PlayingCard> stack, int destCol) {
    if (destCol < 0 || destCol >= _tableau.length || !isMovableRun(stack)) {
      return false;
    }
    final dest = _tableau[destCol];
    return !dest.contains(stack.first) &&
        canPlaceOnTableau(dest.isEmpty ? null : dest.last, stack.first);
  }

  bool moveCardToFoundation(PlayingCard card, int foundationIndex) {
    if (!canMoveCardToFoundation(card, foundationIndex)) return false;
    _saveSnapshot();
    final source = _removeStack([card]);
    _foundations[foundationIndex].add(card);
    _score += 10;
    _moves++;
    _maybeFlipAfterRemoval(source);
    return _finishMove();
  }

  bool moveStackToTableau(List<PlayingCard> stack, int destCol) {
    if (!canMoveStackToTableau(stack, destCol)) return false;
    _saveSnapshot();
    // A caller can pass the source column itself.
    final cards = List<PlayingCard>.of(stack);
    final source = _removeStack(cards);
    _maybeFlipAfterRemoval(source);
    _tableau[destCol].addAll(cards);
    _score += 3;
    _moves++;
    return _finishMove();
  }

  bool _finishMove() {
    if (!_hasConsistentDeckState()) {
      _restoreLastSnapshotAndNotify();
      return false;
    }
    notifyListeners();
    return true;
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

    return MagicWandPlan._atPosition([action], _position);
  }

  bool executeMagicWand(MagicWandPlan plan) {
    if (wandCount <= 0 ||
        plan.actions.isEmpty ||
        (plan._position != null && !identical(plan._position, _position))) {
      return false;
    }
    final first = plan.actions.first;
    if (!_isLegalWandAction(first)) return false;
    final before = _captureSnapshot();
    _applyWandAction(first);
    for (final action in plan.actions.skip(1)) {
      if (!_isLegalWandAction(action)) {
        _restoreSnapshot(before);
        notifyListeners();
        return false;
      }
      _applyWandAction(action);
    }
    _rememberSnapshot(before);
    wandCount--;
    _moves++;
    notifyListeners();
    return true;
  }

  // A hidden card or either end of a visible run may be extracted. Joining
  // visible neighbors after taking a card out of the middle would break it.
  bool _canExtractAt(List<PlayingCard> column, int depth) =>
      depth == 0 || depth == column.length - 1 || !column[depth - 1].isFaceUp;

  bool _isLegalWandAction(MagicWandAction action) {
    final from = action.from;
    final to = action.to;
    final cards = action.cards;
    if (action.type == MagicWandActionType.recycleWaste) {
      return _stock.isEmpty && _waste.isNotEmpty && cards.isEmpty;
    }
    if (from == null || cards.isEmpty) return false;
    final source = switch (from.pile) {
      WandPileType.stock when from.index == 0 => _stock,
      WandPileType.waste when from.index == 0 => _waste,
      WandPileType.tableau
          when from.index >= 0 && from.index < _tableau.length =>
        _tableau[from.index],
      _ => null,
    };
    if (source == null ||
        from.depth < 0 ||
        from.depth > source.length - cards.length) {
      return false;
    }
    for (int i = 0; i < cards.length; i++) {
      if (!identical(source[from.depth + i], cards[i])) return false;
    }
    final single = cards.length == 1;
    final card = cards.first;
    final top = single && from.depth == source.length - 1;
    final inTableau = from.pile == WandPileType.tableau;
    if (action.type == MagicWandActionType.flipTableau) {
      return inTableau && top && !card.isFaceUp;
    }
    if (action.type == MagicWandActionType.drawFromStock) {
      return from.pile == WandPileType.stock &&
          top &&
          action.revealOnPickup &&
          to != null &&
          to.pile == WandPileType.waste &&
          to.index == 0 &&
          to.depth == _waste.length;
    }

    if (to == null) return false;
    if (single) {
      if (inTableau) {
        if (!_canExtractAt(source, from.depth) ||
            (!card.isFaceUp && !action.revealOnPickup)) {
          return false;
        }
      } else if (from.pile != WandPileType.waste || !top || !card.isFaceUp) {
        return false;
      }
    } else if (!inTableau || !isMovableRun(cards)) {
      return false;
    }
    if (action.type == MagicWandActionType.moveToFoundation) {
      return single &&
          to.pile == WandPileType.foundation &&
          _fitsOnFoundation(to.index, card) &&
          to.depth == _foundations[to.index].length;
    }
    if (to.pile != WandPileType.tableau ||
        to.index < 0 ||
        to.index >= _tableau.length ||
        (inTableau && from.index == to.index)) {
      return false;
    }
    final dest = _tableau[to.index];
    return to.depth == dest.length &&
        _fitsOnTableau(dest.isEmpty ? null : dest.last, card);
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
        if ((!isBlocked && !isHidden) || !_canExtractAt(column, depth)) continue;

        final fIdx = _foundationIndexForSuit(card.suit);
        if (_fitsOnFoundation(fIdx, card)) {
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
        if (!isMovableRun(stack)) continue;
        final movingTop = stack.first;
        for (int dest = 0; dest < _tableau.length; dest++) {
          if (dest == src) continue;
          final destPile = _tableau[dest];
          // Moving a whole column to an empty slot cannot uncover a card.
          if (depth == 0 && destPile.isEmpty) continue;
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
        if ((!isBlocked && !isHidden) || !_canExtractAt(column, depth)) continue;

        for (int dest = 0; dest < _tableau.length; dest++) {
          if (dest == src) continue;
          final destPile = _tableau[dest];
          final destTop = destPile.isEmpty ? null : destPile.last;
          if (_fitsOnTableau(destTop, card)) {
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

  /// Only called after checking this action against the current position.
  void _applyWandAction(MagicWandAction action) {
    switch (action.type) {
      case MagicWandActionType.moveToFoundation:
      case MagicWandActionType.moveToTableau:
        final from = action.from!;
        final to = action.to!;
        // A supplied run may be the actual source column.
        final cards = List<PlayingCard>.of(action.cards);
        if (from.pile == WandPileType.tableau) {
          _tableau[from.index].removeRange(
            from.depth,
            from.depth + cards.length,
          );
          _maybeFlipAfterRemoval(from.index);
        } else {
          _waste.removeLast();
        }
        if (!cards.first.isFaceUp) {
          cards.first.isFaceUp = true;
          _score += 5;
        }
        if (to.pile == WandPileType.foundation) {
          _foundations[to.index].add(cards.single);
          _score += 10;
        } else {
          _tableau[to.index].addAll(cards);
          _score += 3;
        }
      case MagicWandActionType.drawFromStock:
        _waste.add(_stock.removeLast()..isFaceUp = true);
      case MagicWandActionType.recycleWaste:
        _recycleWaste();
      case MagicWandActionType.flipTableau:
        action.cards.single.isFaceUp = true;
        _score += 5;
    }
  }

  void _recycleWaste() {
    while (_waste.isNotEmpty) {
      _stock.add(_waste.removeLast()..isFaceUp = false);
    }
  }

  HintSuggestion? computeHint() => _computeHint();

  bool get hasHintAvailable => _computeHint(previewOnly: true) != null;

  HintSuggestion? _computeHint({bool previewOnly = false}) {
    HintSuggestion buildResult(
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
        return buildResult(
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
        return buildResult(
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
        return buildResult(
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
          return buildResult(
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
        if (!isMovableRun(stack)) continue;
        final movingTop = stack.first;
        for (int dest = 0; dest < _tableau.length; dest++) {
          if (dest == src) continue;
          final destPile = _tableau[dest];
          // Moving a whole column to an empty slot cannot uncover a card.
          if (row == 0 && destPile.isEmpty) continue;
          if (canPlaceOnTableau(
              destPile.isEmpty ? null : destPile.last, movingTop)) {
            final cards = previewOnly
                ? const <PlayingCard>[]
                : List<PlayingCard>.from(stack);
            return buildResult(
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
      return buildResult(
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

  _GameSnapshot _captureSnapshot() => _GameSnapshot(
    stock: _clonePile(_stock),
    waste: _clonePile(_waste),
    tableau: _tableau.map(_clonePile).toList(),
    foundations: _foundations.map(_clonePile).toList(),
    score: _score,
    moves: _moves,
    freezeCount: freezeCount,
    wandCount: wandCount,
  );

  void _saveSnapshot() => _rememberSnapshot(_captureSnapshot());

  void _rememberSnapshot(_GameSnapshot snapshot) {
    _history.add(snapshot);
    if (_history.length > _historyLimit) _history.removeAt(0);
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

  bool _hasConsistentDeckState() {
    if (_boardCardCount != _deckSize) {
      return false;
    }

    final Map<String, int> counts = <String, int>{};

    void tally(Iterable<PlayingCard> cards) {
      for (final card in cards) {
        final key = '${card.suit.index}-${card.rank}';
        counts.update(key, (value) => value + 1, ifAbsent: () => 1);
      }
    }

    tally(_stock);
    tally(_waste);
    for (final pile in _foundations) {
      tally(pile);
    }
    for (final column in _tableau) {
      tally(column);
    }

    if (counts.length != _deckSize) {
      return false;
    }
    return counts.values.every((count) => count == 1);
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
  const MagicWandPlan(this.actions) : _position = null;
  const MagicWandPlan._atPosition(this.actions, this._position);

  final Object? _position;

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
