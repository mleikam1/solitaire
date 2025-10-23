import 'dart:async';
import 'package:flutter/material.dart';
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
    if (state == AppLifecycleState.paused) {
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
                            GestureDetector(
                              onTap: () {
                                _startTimerIfNeeded();
                                game.drawFromStock();
                              },
                              child: _buildCardSlot(
                                  game.stockTop, cardWidth, cardHeight),
                            ),
                            const SizedBox(width: 10),
                            _buildCardSlot(
                                game.wasteTop, cardWidth, cardHeight),
                          ],
                        ),
                        Row(
                          children: List.generate(
                            4,
                                (i) => Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: _buildCardSlot(
                                  game.foundationTop(i), cardWidth, cardHeight),
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
                              final stack = details.data;
                              game.moveStackToTableau(stack, colIdx);
                            },
                            builder: (context, candidate, rejected) {
                              return SizedBox(
                                width: cardWidth,
                                child: Stack(
                                  children: [
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
  Widget _buildCardSlot(PlayingCard? card, double w, double h) {
    if (card != null) return CardWidget(card: card, width: w, height: h);
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white30),
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
      feedback: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final c in stack) CardWidget(card: c, width: w, height: h)],
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.0,
        child: CardWidget(card: card, width: w, height: h),
      ),
      onDragStarted: _startTimerIfNeeded,
      child: GestureDetector(
        onTap: () {
          _startTimerIfNeeded();
          game.tapCard(card);
        },
        child: CardWidget(card: card, width: w, height: h),
      ),
    );
  }
}
