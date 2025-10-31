import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../models/card_model.dart';
import '../game/klondike_game.dart';
import '../widgets/card_widget.dart';
import '../widgets/bottom_toolbar.dart';

class SolitaireGamePage extends StatefulWidget {
  const SolitaireGamePage({super.key});

  @override
  State<SolitaireGamePage> createState() => _SolitaireGamePageState();
}

class _SolitaireGamePageState extends State<SolitaireGamePage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final KlondikeGame game = KlondikeGame();
  static const double _tableauSpacing = 30.0;
  BannerAd? _bannerAd;

  late final Stopwatch _watch;
  Timer? _timer;

  bool _hasStarted = false;
  bool _isPaused = false;
  bool _isFreezeActive = false;
  int _freezeCountdown = 0;
  Timer? _freezeTimer;
  Timer? _hintTimer;
  HintSuggestion? _activeHint;
  Set<PlayingCard> _hintCards = <PlayingCard>{};
  Set<PlayingCard> _draggingCards = <PlayingCard>{};
  final List<GlobalKey> _tableauKeys = List.generate(7, (_) => GlobalKey());
  final List<GlobalKey> _foundationKeys = List.generate(4, (_) => GlobalKey());
  final GlobalKey _foundationRowKey = GlobalKey();
  final GlobalKey _stockKey = GlobalKey();
  final GlobalKey _wasteKey = GlobalKey();

  bool _isWandAnimating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watch = Stopwatch();
    _loadAd();
    game.addListener(_onGameChanged);
  }

  void _onGameChanged() {
    _hintTimer?.cancel();
    _hintTimer = null;
    setState(() {
      _activeHint = null;
      _hintCards = <PlayingCard>{};
      _draggingCards = <PlayingCard>{};
    });
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111', // Google test banner
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() {}),
        onAdFailedToLoad: (_, __) => _bannerAd = null,
      ),
    )..load();
  }

  // ===== Timer behavior (start on first move, pause/resume, reset on new deal) =====
  void _startTimerIfNeeded() {
    if (!_hasStarted && !_watch.isRunning) {
      _hasStarted = true;
      _watch.start();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    }
  }

  void _pauseTimer() {
    if (_watch.isRunning) {
      _isPaused = true;
      _watch.stop();
      _timer?.cancel();
    }
  }

  void _resumeTimer() {
    if (_isPaused && !_isFreezeActive) {
      _isPaused = false;
      _watch.start();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    }
  }

  void _resetTimer() {
    _hasStarted = false;
    _watch.stop();
    _watch.reset();
    _timer?.cancel();
    setState(() {});
  }

  String _formatTime() {
    final e = _watch.elapsed;
    final m = e.inMinutes.toString().padLeft(2, '0');
    final s = (e.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ===== Freeze overlay logic =====
  void _activateFreeze() {
    if (_isFreezeActive || game.freezeCount <= 0) return;
    setState(() {
      _isFreezeActive = true;
      _freezeCountdown = 10;
      game.freezeCount--;
      _activeHint = null;
      _hintCards = <PlayingCard>{};
    });
    _hintTimer?.cancel();
    _hintTimer = null;
    _pauseTimer();

    _freezeTimer?.cancel();
    _freezeTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_freezeCountdown > 0) {
        setState(() => _freezeCountdown--);
      } else {
        t.cancel();
        setState(() {
          _isFreezeActive = false;
          _freezeCountdown = 0;
        });
        _resumeTimer();
      }
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
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _isWandAnimating = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _pauseTimer();
    } else if (state == AppLifecycleState.resumed) {
      _resumeTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _freezeTimer?.cancel();
    _hintTimer?.cancel();
    _bannerAd?.dispose();
    game.removeListener(_onGameChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardWidth = MediaQuery.of(context).size.width / 8.5;
    final cardHeight = cardWidth * 1.4;
    final hintAvailable = game.hasHintAvailable;

    return Scaffold(
      backgroundColor: const Color(0xFF006400),
      body: SafeArea(
        child: Column(
          children: [
            if (_bannerAd != null)
              SizedBox(
                height: _bannerAd!.size.height.toDouble(),
                width: _bannerAd!.size.width.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text('Time: ${_formatTime()}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18)),
                      if (_isFreezeActive)
                        Row(
                          children: [
                            const SizedBox(width: 8),
                            const Icon(Icons.timer,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 4),
                            Text('$_freezeCountdown',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 18)),
                          ],
                        ),
                    ],
                  ),
                  Text('Score: ${game.score}',
                      style: const TextStyle(color: Colors.white, fontSize: 18)),
                  Text('Moves: ${game.moves}',
                      style: const TextStyle(color: Colors.white, fontSize: 18)),
                ],
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
                              child:
                                  _buildFoundationTarget(i, cardWidth, cardHeight),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Tableau (7 columns) with stack dragging
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List.generate(7, (colIdx) {
                          final column = game.tableau[colIdx];
                          return DragTarget<List<PlayingCard>>(
                            onWillAcceptWithDetails: (details) {
                              final stack = details.data;
                              if (stack.isEmpty) return false;
                              final movingTop = stack.first;
                              final destTop =
                              column.isEmpty ? null : column.last;
                              return game.canPlaceOnTableau(destTop, movingTop);
                            },
                            onAcceptWithDetails: (details) {
                              _startTimerIfNeeded();
                              _clearDraggingCards();
                              final stack = List<PlayingCard>.from(details.data);
                              final moved = game.moveStackToTableau(stack, colIdx);
                              if (!moved) {
                                setState(() {});
                              }
                            },
                            builder: (context, candidate, rejected) {
                              final stackHeight = column.isEmpty
                                  ? cardHeight
                                  : cardHeight + (column.length - 1) * _tableauSpacing;
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
                                    Positioned.fill(
                                      child: _buildEmptySlotBox(),
                                    ),
                                    for (int row = 0;
                                        row < column.length;
                                        row++)
                                      Positioned(
                                        key: ValueKey<int>(column[row].id),
                                        top: row * _tableauSpacing,
                                        child: _buildDraggableRun(
                                          column,
                                          row,
                                          cardWidth,
                                          cardHeight,
                                        ),
                                      ),
                                    if (isHintTarget)
                                      Positioned.fill(
                                        child: _buildHintOverlay(),
                                      ),
                                    if (isHighlighted)
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          ignoring: true,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                  color: Colors.yellowAccent,
                                                  width: 2),
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
              onWand: (game.wandCount > 0 && !_isWandAnimating)
                  ? () => _handleWandPressed(cardWidth, cardHeight)
                  : null,
              onHint: _showHint,
              onSettings: () {},
              onUndo: game.canUndo
                  ? () {
                      game.undo();
                    }
                  : null,
              freezeCount: game.freezeCount,
              wandCount: game.wandCount,
              hintAvailable: hintAvailable,
            ),
          ],
        ),
      ),
    );
  }

  // ===== UI helpers =====
  Widget _buildStockSlot(double w, double h) {
    final card = game.stockTop;
    final bool highlightStock = _activeHint?.highlightStock ?? false;

    final Widget content = card != null
        ? _buildHintableCard(card, w, h)
        : _buildEmptySlotBox();

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
          if (highlightStock)
            Positioned.fill(
              child: _buildHintOverlay(),
            ),
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
    if (_draggingCards.contains(card)) {
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
        childWhenDragging:
            SizedBox(width: w, height: h, child: _buildEmptySlotBox()),
        onDragStarted: () => _handleDragStarted([card]),
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
        if (stack.isEmpty || stack.length != 1) return false;
        return game.canPlaceOnFoundation(index, stack.first);
      },
      onAcceptWithDetails: (details) {
        _startTimerIfNeeded();
        _clearDraggingCards();
        game.moveCardToFoundation(details.data.first, index);
      },
      builder: (context, candidate, rejected) {
        final card = game.foundationTop(index);
        final highlight = candidate.isNotEmpty;
        final isHintTarget =
            _activeHint?.destinationFoundationIndex == index;
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
    if (_draggingCards.contains(card)) {
      return SizedBox(width: w, height: h);
    }
    return Draggable<List<PlayingCard>>(
      key: ValueKey<int>(card.id),
      data: [card],
      feedback: _buildDragFeedback([card], w, h),
      childWhenDragging: SizedBox(width: w, height: h, child: _buildEmptySlotBox()),
      onDragStarted: () => _handleDragStarted([card]),
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
    final double totalHeight =
        h + (_tableauSpacing * (stack.length <= 1 ? 0 : stack.length - 1));
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
                  top: i * _tableauSpacing,
                  child: CardWidget(card: stack[i], width: w, height: h),
                ),
            ],
          ),
        ),
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
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: Colors.yellowAccent.withOpacity(0.45),
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
              color: Colors.yellowAccent.withOpacity(0.55),
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
      List<PlayingCard> column, int row, double w, double h) {
    final card = column[row];
    if (_draggingCards.contains(card)) {
      return SizedBox(width: w, height: h);
    }
    if (!card.isFaceUp) {
      return _buildHintableCard(card, w, h);
    }

    final stack = column.sublist(row); // inclusive stack (run)

    return Draggable<List<PlayingCard>>(
      key: ValueKey<int>(card.id),
      data: stack,
      feedback: _buildDragFeedback(stack, w, h),
      childWhenDragging: SizedBox(width: w, height: h),
      onDragStarted: () => _handleDragStarted(stack),
      onDragEnd: (details) {
        _handleDragEnd(List<PlayingCard>.from(stack), details, w, h);
      },
      dragAnchorStrategy: childDragAnchorStrategy,
      child: GestureDetector(
        onTap: () {
          _startTimerIfNeeded();
          game.tapCard(card);
        },
        child: _buildHintableCard(card, w, h),
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

  void _handleDragEnd(List<PlayingCard> stack, DraggableDetails details,
      double cardWidth, double cardHeight) {
    if (stack.isEmpty) {
      return;
    }

    bool didUpdate = _clearDraggingCards();

    if (details.wasAccepted) {
      return;
    }

    final dropPoint =
        details.offset + Offset(cardWidth / 2, cardHeight / 2);
    final moved =
        _autoSnapStack(stack, dropPoint, cardWidth, cardHeight);
    if (!moved && !didUpdate) {
      setState(() {});
    }
  }

  bool _autoSnapStack(List<PlayingCard> stack, Offset dropPoint,
      double cardWidth, double cardHeight) {
    if (stack.isEmpty) return false;
    final topCard = stack.first;
    final tolerance = math.max(24.0, cardWidth * 0.35);
    final maxDistance = math.max(cardWidth, cardHeight) * 0.75;

    _AutoDropTarget? bestTarget;

    for (int i = 0; i < _tableauKeys.length; i++) {
      final rect = _getGlobalRect(_tableauKeys[i]);
      if (rect == null) continue;
      final expanded = rect.inflate(tolerance);
      final column = game.tableau[i];
      if (!game.canPlaceOnTableau(
          column.isEmpty ? null : column.last, topCard)) {
        continue;
      }
      final distance = _distanceToRect(expanded, dropPoint);
      if (distance <= maxDistance &&
          (bestTarget == null || distance < bestTarget.distance)) {
        bestTarget =
            _AutoDropTarget(_AutoDropType.tableau, i, distance);
      }
    }

    if (stack.length == 1) {
      for (int i = 0; i < _foundationKeys.length; i++) {
        if (!game.canPlaceOnFoundation(i, topCard)) {
          continue;
        }
        final rect = _getGlobalRect(_foundationKeys[i]);
        if (rect == null) continue;
        final expanded = rect.inflate(tolerance);
        final distance = _distanceToRect(expanded, dropPoint);
        if (distance <= maxDistance &&
            (bestTarget == null || distance < bestTarget.distance)) {
          bestTarget =
              _AutoDropTarget(_AutoDropType.foundation, i, distance);
        }
      }
    }

    if (bestTarget == null && stack.length == 1) {
      final rowRect = _getGlobalRect(_foundationRowKey);
      if (rowRect != null) {
        final expandedRow = rowRect.inflate(tolerance);
        if (expandedRow.contains(dropPoint)) {
          for (int i = 0; i < _foundationKeys.length; i++) {
            if (game.canPlaceOnFoundation(i, topCard)) {
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
            List<PlayingCard>.from(stack), bestTarget.index);
        if (moved) {
          _startTimerIfNeeded();
        }
        return moved;
      case _AutoDropType.foundation:
        final moved =
            game.moveCardToFoundation(stack.first, bestTarget.index);
        if (moved) {
          _startTimerIfNeeded();
        }
        return moved;
    }
  }

  Future<void> _animateWandPlan(
      MagicWandPlan plan, double cardWidth, double cardHeight) async {
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
      MagicWandAction action, double cardWidth, double cardHeight) async {
    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final start = _computeGlobalOffset(action.from!, cardWidth, cardHeight);
    final end = _computeGlobalOffset(action.to!, cardWidth, cardHeight);
    if (start == null || end == null) return;

    final controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOut,
    );

    final cards = action.cards
        .map((card) {
          final clone = card.clone();
          if (action.revealOnPickup && !clone.isFaceUp) {
            clone.isFaceUp = true;
          }
          return clone;
        })
        .toList(growable: false);

    final stackHeight =
        cardHeight + math.max(0, cards.length - 1) * _tableauSpacing;

    late OverlayEntry entry;
    entry = OverlayEntry(builder: (context) {
      final offset = Offset.lerp(start, end, animation.value) ?? start;
      return Positioned(
        left: offset.dx,
        top: offset.dy,
        child: IgnorePointer(
          ignoring: true,
          child: SizedBox(
            width: cardWidth,
            height: stackHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (int i = 0; i < cards.length; i++)
                  Positioned(
                    top: i * _tableauSpacing,
                    child: CardWidget(
                      card: cards[i],
                      width: cardWidth,
                      height: cardHeight,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });

    overlay.insert(entry);
    await controller.forward();
    entry.remove();
    controller.dispose();
  }

  Offset? _computeGlobalOffset(
      WandLocation location, double cardWidth, double cardHeight) {
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
      offset += Offset(0, location.depth * _tableauSpacing);
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
    final dx = point.dx < rect.left
        ? rect.left - point.dx
        : (point.dx > rect.right ? point.dx - rect.right : 0.0);
    final dy = point.dy < rect.top
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
