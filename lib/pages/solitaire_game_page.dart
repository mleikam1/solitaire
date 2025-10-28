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
    with WidgetsBindingObserver {
  final KlondikeGame game = KlondikeGame();
  BannerAd? _bannerAd;

  late final Stopwatch _watch;
  Timer? _timer;

  bool _hasStarted = false;
  bool _isPaused = false;
  bool _isFreezeActive = false;
  int _freezeCountdown = 0;
  Timer? _freezeTimer;
  final List<GlobalKey> _tableauKeys = List.generate(7, (_) => GlobalKey());
  final List<GlobalKey> _foundationKeys = List.generate(4, (_) => GlobalKey());
  final GlobalKey _foundationRowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watch = Stopwatch();
    _loadAd();
    game.addListener(_onGameChanged);
  }

  void _onGameChanged() => setState(() {});

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
    });
    _pauseTimer();

    _freezeTimer?.cancel();
    _freezeTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_freezeCountdown > 0) {
        setState(() => _freezeCountdown--);
      } else {
        t.cancel();
        setState(() => _isFreezeActive = false);
        _resumeTimer();
      }
    });
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
    _bannerAd?.dispose();
    game.removeListener(_onGameChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardWidth = MediaQuery.of(context).size.width / 8.5;
    final cardHeight = cardWidth * 1.4;

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
                  Text('Time: ${_formatTime()}',
                      style: const TextStyle(color: Colors.white, fontSize: 18)),
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
                              final stack = List<PlayingCard>.from(details.data);
                              final moved = game.moveStackToTableau(stack, colIdx);
                              if (!moved) {
                                setState(() {});
                              }
                            },
                            builder: (context, candidate, rejected) {
                              final stackHeight = column.isEmpty
                                  ? cardHeight
                                  : cardHeight + (column.length - 1) * 30;
                              final isHighlighted = candidate.isNotEmpty;

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
                                        top: row * 30,
                                        child: _buildDraggableRun(
                                          column,
                                          row,
                                          cardWidth,
                                          cardHeight,
                                        ),
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
                _resetTimer();
                game.newDeal();
              },
              onFreeze: _activateFreeze,
              onWand: () {
                _startTimerIfNeeded();
                game.activateWand();
              },
              onSettings: () {},
              onUndo: game.canUndo
                  ? () {
                      game.undo();
                    }
                  : null,
              freezeCount: game.freezeCount,
              wandCount: game.wandCount,
            ),
            if (_isFreezeActive)
              Padding(
                padding: const EdgeInsets.only(bottom: 80),
                child: Text(
                  'Freeze ends in $_freezeCountdown',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===== UI helpers =====
  Widget _buildStockSlot(double w, double h) {
    final card = game.stockTop;
    return SizedBox(
      width: w,
      height: h,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _startTimerIfNeeded();
          game.drawFromStock();
        },
        child: card != null ? CardWidget(card: card, width: w, height: h) : _buildEmptySlotBox(),
      ),
    );
  }

  Widget _buildWasteSlot(double w, double h) {
    final card = game.wasteTop;
    if (card == null) {
      return SizedBox(width: w, height: h, child: _buildEmptySlotBox());
    }
    return SizedBox(
      width: w,
      height: h,
      child: Draggable<List<PlayingCard>>(
        data: [card],
        feedback: _buildDragFeedback([card], w, h),
        childWhenDragging:
            SizedBox(width: w, height: h, child: _buildEmptySlotBox()),
        onDragStarted: _startTimerIfNeeded,
        onDragEnd: (details) {
          if (!details.wasAccepted) {
            _handleDragEnd([card], details, w, h);
          }
        },
        dragAnchorStrategy: childDragAnchorStrategy,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _startTimerIfNeeded();
            game.tapCard(card);
          },
          child: CardWidget(card: card, width: w, height: h),
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
        game.moveCardToFoundation(details.data.first, index);
      },
      builder: (context, candidate, rejected) {
        final card = game.foundationTop(index);
        final highlight = candidate.isNotEmpty;
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
      data: [card],
      feedback: _buildDragFeedback([card], w, h),
      childWhenDragging: SizedBox(width: w, height: h, child: _buildEmptySlotBox()),
      onDragStarted: _startTimerIfNeeded,
      onDragEnd: (details) {
        if (!details.wasAccepted) {
          _handleDragEnd([card], details, w, h);
        }
      },
      dragAnchorStrategy: childDragAnchorStrategy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _startTimerIfNeeded();
          game.tapCard(card);
        },
        child: CardWidget(card: card, width: w, height: h),
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
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in stack) CardWidget(card: c, width: w, height: h),
          ],
        ),
      ),
    );
  }

  /// Builds a Draggable run starting from [row] to end of [column] (if face-up).
  Widget _buildDraggableRun(
      List<PlayingCard> column, int row, double w, double h) {
    final card = column[row];
    if (!card.isFaceUp) {
      return CardWidget(card: card, width: w, height: h);
    }

    final stack = column.sublist(row); // inclusive stack (run)

    return Draggable<List<PlayingCard>>(
      data: stack,
      feedback: _buildDragFeedback(stack, w, h),
      childWhenDragging: SizedBox(width: w, height: h),
      onDragStarted: _startTimerIfNeeded,
      onDragEnd: (details) {
        if (!details.wasAccepted) {
          _handleDragEnd(List<PlayingCard>.from(stack), details, w, h);
        }
      },
      dragAnchorStrategy: childDragAnchorStrategy,
      child: GestureDetector(
        onTap: () {
          _startTimerIfNeeded();
          game.tapCard(card);
        },
        child: CardWidget(card: card, width: w, height: h),
      ),
    );
  }

  void _handleDragEnd(List<PlayingCard> stack, DraggableDetails details,
      double cardWidth, double cardHeight) {
    if (stack.isEmpty) return;
    final dropPoint =
        details.offset + Offset(cardWidth / 2, cardHeight / 2);
    final moved =
        _autoSnapStack(stack, dropPoint, cardWidth, cardHeight);
    if (!moved) {
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
