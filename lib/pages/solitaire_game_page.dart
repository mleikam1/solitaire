import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../appearance/appearance.dart';
import '../appearance/appearance_panel.dart';
import '../appearance/table_surface.dart';
import '../models/card_model.dart';
import '../widgets/ad_banner.dart';
import '../game/beat_challenge.dart';
import '../game/deal_spec.dart';
import '../game/help_snapshot.dart';
import '../game/klondike_game.dart';
import '../widgets/card_widget.dart';
import '../widgets/bottom_toolbar.dart';

class SolitaireGamePage extends StatefulWidget {
  const SolitaireGamePage({super.key, this.createGame = KlondikeGame.new})
    : _help = null;

  SolitaireGamePage.fromDeal(DealSpec deal, {super.key})
    : _help = null,
      createGame = (() => KlondikeGame.fromDeal(deal));

  SolitaireGamePage.fromHelp(HelpSnapshot help, {super.key})
    : _help = help,
      createGame = (() => KlondikeGame.fromSnapshot(help.board));

  final KlondikeGame Function() createGame;
  final HelpSnapshot? _help;

  @override
  SolitaireGamePageState createState() => SolitaireGamePageState();
}

/// A share action can sample the board and local clock synchronously using a
/// `GlobalKey<SolitaireGamePageState>`. Open each incoming share on a new route.
class SolitaireGamePageState extends State<SolitaireGamePage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final KlondikeGame game = widget.createGame();
  late final AnimationController _wandFlight;

  final Stopwatch _watch = WidgetsBinding.instance.samplingClock.stopwatch();
  final Stopwatch _freezeWatch = WidgetsBinding.instance.samplingClock
      .stopwatch();
  Timer? _timer;
  Timer? _freezeTimer;

  int _elapsedBase = 0;
  int _freezeBudget = 0;
  bool _hasStarted = false;
  bool _foreground = true;

  int get _elapsedMs => _elapsedBase + _watch.elapsedMilliseconds;
  bool get _isFreezeActive => _freezeBudget > 0;
  int get _remainingFreezeMs =>
      math.max(0, _freezeBudget - _freezeWatch.elapsedMilliseconds);
  int get _freezeCountdown => math.max(0, (_remainingFreezeMs - 1) ~/ 1000);

  HelpSnapshot captureHelp() => HelpSnapshot(
    board: game.snapshot(),
    hasStarted: _hasStarted,
    elapsedMilliseconds: _elapsedMs,
    freezeRemainingMilliseconds: _remainingFreezeMs,
  );

  /// Only a fresh-start victory is eligible for a competition share. This is
  /// a client result. A ranked service must independently verify the attempt.
  CompletedDeal? get completedDeal => !game.startedFromSnapshot && game.isWon
      ? (deal: game.deal, moves: game.moves, elapsedMilliseconds: _elapsedMs)
      : null;

  Timer? _hintTimer;
  HintSuggestion? _activeHint;
  Set<PlayingCard> _hintCards = <PlayingCard>{};
  Set<PlayingCard> _draggingCards = <PlayingCard>{};
  final Map<PlayingCard, Offset> _dragPointers = {};
  final List<GlobalKey> _tableauKeys = List.generate(7, (_) => GlobalKey());
  final List<GlobalKey> _foundationKeys = List.generate(4, (_) => GlobalKey());
  final GlobalKey _foundationRowKey = GlobalKey();
  final GlobalKey _stockKey = GlobalKey();
  final GlobalKey _wasteKey = GlobalKey();

  bool _isWandAnimating = false;
  int _boardRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    final help = widget._help;
    if (help != null) {
      _elapsedBase = help.elapsedMilliseconds;
      _hasStarted = help.hasStarted;
      _setFreeze(help.freezeRemainingMilliseconds);
      _syncClock();
    }
    _wandFlight = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    game.addListener(_onGameChanged);
  }

  void _onGameChanged() {
    _boardRevision++;
    _syncClock();
    _hintTimer?.cancel();
    _hintTimer = null;
    setState(() {
      _activeHint = null;
      _hintCards = <PlayingCard>{};
      _draggingCards = <PlayingCard>{};
      _dragPointers.clear();
    });
  }

  // ===== Timer behavior (start on first move, pause/resume, reset on new deal) =====
  void _startTimerIfNeeded() {
    if (_hasStarted) return;
    _hasStarted = true;
    _syncClock();
  }

  void _syncClock() {
    final running =
        _foreground && _hasStarted && !_isFreezeActive && !game.isWon;
    if (running) {
      _watch.start();
    } else {
      _watch.stop();
    }
    if (_foreground && (running || _isFreezeActive)) {
      _timer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _resetTimer() {
    _hasStarted = false;
    _elapsedBase = 0;
    _setFreeze(0);
    _watch.stop();
    _watch.reset();
    _syncClock();
  }

  String _formatTime() {
    final e = Duration(milliseconds: _elapsedMs);
    final m = e.inMinutes.toString().padLeft(2, '0');
    final s = (e.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ===== Freeze overlay logic =====
  void _activateFreeze() {
    if (_isFreezeActive || game.freezeCount <= 0) return;
    setState(() {
      _setFreeze(HelpSnapshot.fullFreezeMilliseconds);
      _syncClock();
      game.freezeCount--;
      _activeHint = null;
      _hintCards = <PlayingCard>{};
    });
    _hintTimer?.cancel();
    _hintTimer = null;
  }

  // Store the full remaining interval, including the fractional first tick.
  // Sampling a help link neither pauses nor consumes the owner's Freeze.
  void _setFreeze(int milliseconds) {
    _freezeTimer?.cancel();
    _freezeWatch.stop();
    _freezeWatch.reset();
    _freezeBudget = milliseconds;
    if (milliseconds == 0) return;
    _freezeWatch.start();
    _freezeTimer = Timer(Duration(milliseconds: milliseconds), () {
      _freezeBudget = 0;
      _freezeWatch.stop();
      _syncClock();
      setState(() {});
    });
  }

  void _showHint() {
    final hint = game.computeHint();
    if (hint == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No hints available right now.'),
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    _hintTimer?.cancel();
    setState(() {
      _activeHint = hint;
      _hintCards = hint.cards.toSet();
    });
    _hintTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        _activeHint = null;
        _hintCards = <PlayingCard>{};
      });
    });
  }

  Future<void> _handleWandPressed(double cardWidth, double cardHeight) async {
    if (_isWandAnimating) return;

    final plannedRevision = _boardRevision;
    final plan = game.planMagicWand();
    if (plan == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No magic moves available right now.'),
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    _startTimerIfNeeded();

    if (!mounted) return;
    setState(() {
      _isWandAnimating = true;
    });

    try {
      await _animateWandPlan(plan, cardWidth, cardHeight);
      if (!mounted || plannedRevision != _boardRevision) return;
      final success = game.executeMagicWand(plan);
      if (!success) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Magic wand could not find a valid move.'),
              duration: Duration(seconds: 2),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _isWandAnimating = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncClock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _freezeTimer?.cancel();
    _hintTimer?.cancel();
    _wandFlight.dispose();
    game.removeListener(_onGameChanged);
    game.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final table = context.select<AppearanceController, TableStyle>(
      (a) => a.table,
    );
    return Scaffold(
      backgroundColor: const Color(0xFF006400),
      body: Stack(
        fit: StackFit.expand,
        children: [
          TableSurface(table: table),
          SafeArea(
            child: LayoutBuilder(
              builder:
                  (context, constraints) => _buildBoard(constraints, table),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard(BoxConstraints constraints, TableStyle table) {
    final cardWidth = constraints.maxWidth / 8.5;
    final cardHeight = cardWidth * 7 / 5;
    final hintAvailable = game.hasHintAvailable;
    return Column(
      children: [
        const AdBanner(),
        Container(
          color:
              table == TableStyle.originalGreen
                  ? null
                  : Colors.black.withValues(alpha: 0.58),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white, fontSize: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      children: [
                        Text('Time: ${_formatTime()}'),
                        if (_isFreezeActive) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.timer,
                            color: Colors.white,
                            size: 18,
                          ),
                          Text('$_freezeCountdown'),
                        ],
                      ],
                    ),
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Score: ${game.score}'),
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Moves: ${game.moves}'),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                // Stock + Waste + Foundations row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _buildStockSlot(cardWidth, cardHeight),
                        const SizedBox(width: 10),
                        _buildWasteSlot(cardWidth, cardHeight),
                      ],
                    ),
                    Row(
                      key: _foundationRowKey,
                      children: List.generate(
                        4,
                        (i) => Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: _buildFoundationTarget(
                            i,
                            cardWidth,
                            cardHeight,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Tableau (7 columns) with stack dragging
                Expanded(
                  child: SingleChildScrollView(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(7, (colIdx) {
                        final column = game.tableau[colIdx];
                        return DragTarget<List<PlayingCard>>(
                          onWillAcceptWithDetails: (details) =>
                              game.canMoveStackToTableau(details.data, colIdx),
                          onAcceptWithDetails: (details) {
                            _startTimerIfNeeded();
                            _clearDraggingCards();
                            final stack = List<PlayingCard>.from(details.data);
                            final moved = game.moveStackToTableau(
                              stack,
                              colIdx,
                            );
                            if (!moved) {
                              setState(() {});
                            }
                          },
                          builder: (context, candidate, rejected) {
                            final stackHeight =
                                column.isEmpty
                                    ? cardHeight
                                    : cardHeight +
                                        _cardOffset(
                                          column,
                                          column.length - 1,
                                          cardWidth,
                                        );
                            final isHighlighted = candidate.isNotEmpty;
                            final isHintTarget =
                                _activeHint?.destinationTableauIndex == colIdx;

                            return SizedBox(
                              key: _tableauKeys[colIdx],
                              width: cardWidth,
                              height: stackHeight,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(child: _buildEmptySlotBox()),
                                  for (int row = 0; row < column.length; row++)
                                    Positioned(
                                      key: ValueKey<int>(column[row].id),
                                      top: _cardOffset(column, row, cardWidth),
                                      child: _buildDraggableRun(
                                        column,
                                        row,
                                        cardWidth,
                                        cardHeight,
                                      ),
                                    ),
                                  if (isHintTarget)
                                    Positioned.fill(child: _buildHintOverlay()),
                                  if (isHighlighted)
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        ignoring: true,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: Colors.yellowAccent,
                                              width: 2,
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
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        BottomToolbar(
          onNewDeal: () {
            _hintTimer?.cancel();
            _hintTimer = null;
            _activeHint = null;
            _hintCards = <PlayingCard>{};
            _resetTimer();
            game.newDeal();
          },
          onFreeze: game.freezeCount > 0 ? _activateFreeze : null,
          onWand:
              (game.wandCount > 0 && !_isWandAnimating)
                  ? () => _handleWandPressed(cardWidth, cardHeight)
                  : null,
          onHint: _showHint,
          onSettings: () => showAppearancePanel(context),
          onUndo:
              game.canUndo
                  ? () {
                    game.undo();
                  }
                  : null,
          freezeCount: game.freezeCount,
          wandCount: game.wandCount,
          hintAvailable: hintAvailable,
        ),
      ],
    );
  }

  // Face-up cards need room for their corner rank. The same geometry is
  // used by the tableau, drag feedback and Wand travel.
  double _cardOffset(List<PlayingCard> cards, int depth, double width) {
    var offset = 0.0;
    for (var i = 0; i < depth; i++) {
      offset += cards[i].isFaceUp ? math.max(32.0, width * 0.70) : width * 0.26;
    }
    return offset;
  }

  // ===== UI helpers =====
  Widget _buildStockSlot(double w, double h) {
    final card = game.stockTop;
    final bool highlightStock = _activeHint?.highlightStock ?? false;

    final Widget content =
        card != null ? _buildHintableCard(card, w, h) : _buildEmptySlotBox();

    return SizedBox(
      key: _stockKey,
      width: w,
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _startTimerIfNeeded();
              game.drawFromStock();
            },
            child: SizedBox.expand(child: content),
          ),
          if (highlightStock) Positioned.fill(child: _buildHintOverlay()),
        ],
      ),
    );
  }

  Widget _buildWasteSlot(double w, double h) {
    final card = game.wasteTop;
    if (card == null) {
      return SizedBox(
        key: _wasteKey,
        width: w,
        height: h,
        child: _buildEmptySlotBox(),
      );
    }
    return SizedBox(
      key: _wasteKey,
      width: w,
      height: h,
      child: Draggable<List<PlayingCard>>(
        key: ValueKey<int>(card.id),
        data: [card],
        feedback: _buildDragFeedback([card], w, h),
        childWhenDragging: SizedBox(
          width: w,
          height: h,
          child: _buildDraggingGhost(card, w, h),
        ),
        onDragStarted: () => _handleDragStarted([card]),
        onDragUpdate: (details) => _dragPointers[card] = details.globalPosition,
        onDragEnd: (details) {
          _handleDragEnd([card], details, w, h);
        },
        dragAnchorStrategy: childDragAnchorStrategy,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _startTimerIfNeeded();
            game.tapCard(card);
          },
          child: _buildHintableCard(card, w, h),
        ),
      ),
    );
  }

  Widget _buildFoundationTarget(int index, double w, double h) {
    return DragTarget<List<PlayingCard>>(
      onWillAcceptWithDetails: (details) {
        final stack = details.data;
        return stack.length == 1 &&
            game.canMoveCardToFoundation(stack.single, index);
      },
      onAcceptWithDetails: (details) {
        _startTimerIfNeeded();
        _clearDraggingCards();
        game.moveCardToFoundation(details.data.first, index);
      },
      builder: (context, candidate, rejected) {
        final card = game.foundationTop(index);
        final highlight = candidate.isNotEmpty;
        final isHintTarget = _activeHint?.destinationFoundationIndex == index;
        return SizedBox(
          key: _foundationKeys[index],
          width: w,
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildEmptySlotBox(),
              if (card != null)
                Center(child: _buildFoundationDraggable(card, w, h)),
              if (isHintTarget) _buildHintOverlay(),
              if (highlight)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.yellowAccent, width: 2),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFoundationDraggable(PlayingCard card, double w, double h) {
    return Draggable<List<PlayingCard>>(
      key: ValueKey<int>(card.id),
      data: [card],
      feedback: _buildDragFeedback([card], w, h),
      childWhenDragging: SizedBox(
        width: w,
        height: h,
        child: _buildDraggingGhost(card, w, h),
      ),
      onDragStarted: () => _handleDragStarted([card]),
      onDragUpdate: (details) => _dragPointers[card] = details.globalPosition,
      onDragEnd: (details) {
        _handleDragEnd([card], details, w, h);
      },
      dragAnchorStrategy: childDragAnchorStrategy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _startTimerIfNeeded();
          game.tapCard(card);
        },
        child: _buildHintableCard(card, w, h),
      ),
    );
  }

  Widget _buildEmptySlotBox() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white30),
      ),
    );
  }

  Widget _buildDragFeedback(List<PlayingCard> stack, double w, double h) {
    final totalHeight = h + _cardOffset(stack, stack.length - 1, w);
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: w,
          height: totalHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (int i = 0; i < stack.length; i++)
                Positioned(
                  top: _cardOffset(stack, i, w),
                  child: CardWidget(card: stack[i], width: w, height: h),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDraggingGhost(PlayingCard card, double w, double h) {
    return IgnorePointer(
      ignoring: true,
      child: Opacity(
        opacity: 0.7,
        child: CardWidget(card: card, width: w, height: h),
      ),
    );
  }

  Widget _buildHintableCard(PlayingCard card, double w, double h) {
    final bool highlight = _hintCards.contains(card);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow:
            highlight
                ? [
                  BoxShadow(
                    color: Colors.yellowAccent.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
                : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CardWidget(card: card, width: w, height: h),
          if (highlight)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.yellowAccent, width: 3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHintOverlay({double radius = 6}) {
    return IgnorePointer(
      ignoring: true,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.yellowAccent, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.yellowAccent.withValues(alpha: 0.55),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a Draggable run starting from [row] to end of [column] (if face-up).
  Widget _buildDraggableRun(
    List<PlayingCard> column,
    int row,
    double w,
    double h,
  ) {
    final card = column[row];
    final stack = column.sublist(row);
    if (!game.isMovableRun(stack)) {
      return _buildHintableCard(card, w, h);
    }

    return Draggable<List<PlayingCard>>(
      key: ValueKey<int>(card.id),
      data: stack,
      feedback: _buildDragFeedback(stack, w, h),
      childWhenDragging: SizedBox(
        width: w,
        height: h,
        child: _buildDraggingGhost(card, w, h),
      ),
      onDragStarted: () => _handleDragStarted(stack),
      onDragUpdate: (details) => _dragPointers[card] = details.globalPosition,
      onDragEnd: (details) {
        _handleDragEnd(List<PlayingCard>.from(stack), details, w, h);
      },
      dragAnchorStrategy: childDragAnchorStrategy,
      child: GestureDetector(
        onTap: () {
          _startTimerIfNeeded();
          game.tapCard(card);
        },
        child:
            _draggingCards.contains(card)
                ? _buildDraggingGhost(card, w, h)
                : _buildHintableCard(card, w, h),
      ),
    );
  }

  void _handleDragStarted(List<PlayingCard> stack) {
    _startTimerIfNeeded();
    setState(() {
      _draggingCards = stack.toSet();
    });
  }

  bool _clearDraggingCards() {
    if (_draggingCards.isEmpty) {
      return false;
    }
    setState(() {
      _draggingCards.clear();
    });
    return true;
  }

  void _handleDragEnd(
    List<PlayingCard> stack,
    DraggableDetails details,
    double cardWidth,
    double cardHeight,
  ) {
    if (stack.isEmpty) {
      return;
    }

    final pointer = _dragPointers.remove(stack.first);
    final didUpdate = _clearDraggingCards();

    if (details.wasAccepted) {
      return;
    }

    final dropPoint =
        pointer ?? details.offset + Offset(cardWidth / 2, cardHeight / 2);
    final moved = _autoSnapStack(stack, dropPoint, cardWidth, cardHeight);
    if (!moved && !didUpdate) {
      setState(() {});
    }
  }

  bool _autoSnapStack(
    List<PlayingCard> stack,
    Offset dropPoint,
    double cardWidth,
    double cardHeight,
  ) {
    if (stack.isEmpty) return false;
    final tolerance = math.max(24.0, cardWidth * 0.35);
    final maxDistance = math.max(cardWidth, cardHeight) * 0.75;

    _AutoDropTarget? bestTarget;

    for (int i = 0; i < _tableauKeys.length; i++) {
      final rect = _getGlobalRect(_tableauKeys[i]);
      if (rect == null) continue;
      final expanded = rect.inflate(tolerance);
      if (!game.canMoveStackToTableau(stack, i)) {
        // An explicit drop on an illegal pile should return to the source
        // even if an adjacent legal pile is within the near-miss tolerance.
        if (rect.contains(dropPoint)) return false;
        continue;
      }
      final distance = _distanceToRect(expanded, dropPoint);
      if (distance <= maxDistance &&
          (bestTarget == null || distance < bestTarget.distance)) {
        bestTarget = _AutoDropTarget(_AutoDropType.tableau, i, distance);
      }
    }

    for (int i = 0; i < _foundationKeys.length; i++) {
      final rect = _getGlobalRect(_foundationKeys[i]);
      if (rect == null) continue;
      if (stack.length != 1 || !game.canMoveCardToFoundation(stack.single, i)) {
        if (rect.contains(dropPoint)) return false;
        continue;
      }
      final expanded = rect.inflate(tolerance);
      final distance = _distanceToRect(expanded, dropPoint);
      if (distance <= maxDistance &&
          (bestTarget == null || distance < bestTarget.distance)) {
        bestTarget = _AutoDropTarget(_AutoDropType.foundation, i, distance);
      }
    }

    if (bestTarget == null && stack.length == 1) {
      final rowRect = _getGlobalRect(_foundationRowKey);
      if (rowRect != null) {
        final expandedRow = rowRect.inflate(tolerance);
        if (expandedRow.contains(dropPoint)) {
          for (int i = 0; i < _foundationKeys.length; i++) {
            if (game.canMoveCardToFoundation(stack.single, i)) {
              bestTarget = _AutoDropTarget(_AutoDropType.foundation, i, 0);
              break;
            }
          }
        }
      }
    }

    if (bestTarget == null) {
      return false;
    }

    switch (bestTarget.type) {
      case _AutoDropType.tableau:
        final moved = game.moveStackToTableau(
          List<PlayingCard>.from(stack),
          bestTarget.index,
        );
        if (moved) {
          _startTimerIfNeeded();
        }
        return moved;
      case _AutoDropType.foundation:
        final moved = game.moveCardToFoundation(stack.first, bestTarget.index);
        if (moved) {
          _startTimerIfNeeded();
        }
        return moved;
    }
  }

  Future<void> _animateWandPlan(
    MagicWandPlan plan,
    double cardWidth,
    double cardHeight,
  ) async {
    for (final action in plan.actions) {
      final from = action.from;
      final to = action.to;
      if (from == null || to == null || action.cards.isEmpty) continue;
      await _animateWandAction(action, cardWidth, cardHeight);
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }

  Future<void> _animateWandAction(
    MagicWandAction action,
    double cardWidth,
    double cardHeight,
  ) async {
    final overlay = Overlay.of(context);

    final start = _computeGlobalOffset(action.from!, cardWidth);
    final end = _computeGlobalOffset(action.to!, cardWidth);
    if (start == null || end == null) return;

    // Keep the original orientation during travel. The game applies the
    // reveal and the move together when the Wand reaches its destination.
    final cards = action.cards.map((card) => card.clone()).toList();
    final entry = OverlayEntry(
      builder: (overlayContext) {
        return AnimatedBuilder(
          animation: _wandFlight,
          child: _buildDragFeedback(cards, cardWidth, cardHeight),
          builder: (_, child) {
            final progress = Curves.easeInOut.transform(_wandFlight.value);
            final offset = Offset.lerp(start, end, progress)!;
            return Positioned(left: offset.dx, top: offset.dy, child: child!);
          },
        );
      },
    );

    overlay.insert(entry);
    try {
      await _wandFlight.forward(from: 0).orCancel;
    } on TickerCanceled {
      // The board was disposed during the flight.
    } finally {
      entry.remove();
      entry.dispose();
    }
  }

  Offset? _computeGlobalOffset(WandLocation location, double cardWidth) {
    RenderBox? box;
    switch (location.pile) {
      case WandPileType.stock:
        box = _stockKey.currentContext?.findRenderObject() as RenderBox?;
        break;
      case WandPileType.waste:
        box = _wasteKey.currentContext?.findRenderObject() as RenderBox?;
        break;
      case WandPileType.foundation:
        if (location.index < _foundationKeys.length) {
          box =
              _foundationKeys[location.index].currentContext?.findRenderObject()
                  as RenderBox?;
        }
        break;
      case WandPileType.tableau:
        if (location.index < _tableauKeys.length) {
          box =
              _tableauKeys[location.index].currentContext?.findRenderObject()
                  as RenderBox?;
        }
        break;
    }

    if (box == null) return null;
    var offset = box.localToGlobal(Offset.zero);
    if (location.pile == WandPileType.tableau) {
      offset += Offset(
        0,
        _cardOffset(game.tableau[location.index], location.depth, cardWidth),
      );
    }
    return offset;
  }

  Rect? _getGlobalRect(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return null;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return null;
    final offset = renderObject.localToGlobal(Offset.zero);
    return offset & renderObject.size;
  }

  double _distanceToRect(Rect rect, Offset point) {
    final dx =
        point.dx < rect.left
            ? rect.left - point.dx
            : (point.dx > rect.right ? point.dx - rect.right : 0.0);
    final dy =
        point.dy < rect.top
            ? rect.top - point.dy
            : (point.dy > rect.bottom ? point.dy - rect.bottom : 0.0);
    return math.sqrt(dx * dx + dy * dy);
  }
}

class _AutoDropTarget {
  const _AutoDropTarget(this.type, this.index, this.distance);

  final _AutoDropType type;
  final int index;
  final double distance;
}

enum _AutoDropType { tableau, foundation }
