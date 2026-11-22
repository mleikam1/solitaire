import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/card_flight.dart';
import '../widgets/wand_reveal_flight.dart';
import '../widgets/bottom_toolbar.dart';
import '../widgets/victory_celebration.dart';

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
  WandRevealFlight? _wandReveal;
  MagicWandAction? _wandPickup;
  late final AnimationController _travel;
  final _flightLayerKey = GlobalKey();
  final _gameSurfaceKey = GlobalKey();
  bool get _showVictory =>
      game.isWon && _transfers.isEmpty && !_isWandAnimating;
  List<_CardTransfer> _transfers = const [];
  VoidCallback? _pendingAutoPlay;
  bool _settingsOpen = false;
  bool _newDealDialogOpen = false;
  bool _reduceMotion = false;
  Size? _viewSize;

  final Stopwatch _watch = WidgetsBinding.instance.samplingClock.stopwatch();
  final Stopwatch _freezeWatch =
      WidgetsBinding.instance.samplingClock.stopwatch();
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
  CompletedDeal? get completedDeal =>
      !game.startedFromSnapshot && game.isWon
          ? (
            deal: game.deal,
            moves: game.moves,
            elapsedMilliseconds: _elapsedMs,
          )
          : null;

  static const _hintsPerDeal = 5;
  int _hintsRemaining = _hintsPerDeal;
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
      duration: WandRevealFlight.duration,
      vsync: this,
    );
    _travel = AnimationController(vsync: this)..addStatusListener((status) {
      if (status == AnimationStatus.completed && _transfers.isNotEmpty) {
        setState(() => _transfers = const []);
        _scheduleAutoPlay();
      }
    });
    game.addListener(_onGameChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion || size != _viewSize) _clearFlight();
    final routeIsCurrent = ModalRoute.isCurrentOf(context) ?? true;
    if (_reduceMotion || size != _viewSize || !routeIsCurrent) {
      _wandFlight.stop();
    }
    _viewSize = size;
  }

  void _clearFlight() {
    _travel.stop();
    _transfers = const [];
    _scheduleAutoPlay();
  }

  void _onGameChanged() {
    _cancelAutoPlay();
    _clearFlight();
    // A move or Undo invalidates a Wand flight still awaiting its landing.
    if (_wandFlight.isAnimating) _wandFlight.stop();
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

  Future<void> _confirmNewDeal() async {
    if (_newDealDialogOpen) return;
    _newDealDialogOpen = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reshuffle?'),
          content: const Text(
            'This will restart your game and you’ll lose your current progress. '
            'Is this what you want to do?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );
      if (mounted && confirmed == true) _newDeal();
    } finally {
      _newDealDialogOpen = false;
      if (mounted) _scheduleAutoPlay();
    }
  }

  void _newDeal() {
    _hintsRemaining = _hintsPerDeal;
    _resetTimer();
    game.newDeal();
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
    if (_hintsRemaining == 0) return;
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
      _hintsRemaining--;
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
    if (_isWandAnimating || !_foreground) return;

    _cancelAutoPlay();
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
      _clearFlight();
      _isWandAnimating = true;
    });

    try {
      if (!_reduceMotion) {
        for (final action in plan.actions) {
          await _animateWandAction(action, cardWidth, cardHeight);
        }
      }
      if (!mounted ||
          !_foreground ||
          plannedRevision != _boardRevision ||
          ModalRoute.isCurrentOf(context) == false) {
        return;
      }
      final success = game.executeMagicWand(plan);
      if (success) {
        final destination = plan.actions.last.to;
        _continueAfterMove(
          cardWidth,
          cardHeight,
          foundationIndex:
              destination?.pile == WandPileType.foundation
                  ? destination!.index
                  : null,
        );
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Magic wand could not find a valid move.'),
              duration: Duration(seconds: 2),
            ),
          );
      }
    } on TickerCanceled {
      // The board, route or app changed before the Wand could land.
    } finally {
      if (mounted) {
        setState(() {
          _wandReveal = null;
          _wandPickup = null;
          _isWandAnimating = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _wandFlight.stop();
    if (!_foreground && _transfers.isNotEmpty) setState(_clearFlight);
    _syncClock();
    if (_foreground) _scheduleAutoPlay();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _freezeTimer?.cancel();
    _hintTimer?.cancel();
    _travel.dispose();
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
        key: _gameSurfaceKey,
        fit: StackFit.expand,
        children: [
          TableSurface(table: table),
          ExcludeSemantics(
            excluding: _showVictory,
            child: ExcludeFocus(
              excluding: _showVictory,
              child: IgnorePointer(
                ignoring: _showVictory,
                child: SafeArea(
                  child: LayoutBuilder(
                    builder:
                        (context, constraints) =>
                            _buildBoard(constraints, table),
                  ),
                ),
              ),
            ),
          ),
          if (_showVictory) LayoutBuilder(builder: _buildVictory),
        ],
      ),
    );
  }

  // The Stack lays out the board before this sibling, so the foundation
  // positions include the safe area, ad banner and current screen geometry.
  Widget _buildVictory(BuildContext context, BoxConstraints constraints) {
    final surface =
        _gameSurfaceKey.currentContext!.findRenderObject()! as RenderBox;
    final foundations = [
      for (final key in _foundationKeys)
        if (key.currentContext?.findRenderObject() case final RenderBox box)
          box.localToGlobal(Offset.zero, ancestor: surface) & box.size,
    ];
    assert(foundations.length == 4);
    final size = foundations.first.size;
    return VictoryCelebration(
      foundations: foundations,
      deck: context.select<AppearanceController, DeckStyle>((a) => a.deck),
      score: game.score,
      moves: game.moves,
      elapsed: _formatTime(),
      onNewDeal: _newDeal,
      onUndo:
          game.canUndo ? () => _undoWithFlight(size.width, size.height) : null,
    );
  }

  Widget _buildBoard(BoxConstraints constraints, TableStyle table) {
    final cardWidth = constraints.maxWidth / 8.5;
    final cardHeight = cardWidth * 7 / 5;
    final hintAvailable = _hintsRemaining > 0 && game.hasHintAvailable;
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
          child: _buildPlayArea(
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
                          onWillAcceptWithDetails:
                              (details) => game.canMoveStackToTableau(
                                details.data,
                                colIdx,
                              ),
                          onAcceptWithDetails: (details) {
                            _startTimerIfNeeded();
                            _clearDraggingCards();
                            final stack = List<PlayingCard>.from(details.data);
                            final moved = _moveWithFlight(
                              stack.first,
                              cardWidth,
                              cardHeight,
                              () => game.moveStackToTableau(stack, colIdx),
                              release: details.offset,
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
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    width: cardWidth,
                                    height: cardHeight,
                                    child: _buildEmptySlotBox(),
                                  ),
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
          onNewDeal: _confirmNewDeal,
          onFreeze: game.freezeCount > 0 ? _activateFreeze : null,
          onWand:
              (game.wandCount > 0 && !_isWandAnimating)
                  ? () => _handleWandPressed(cardWidth, cardHeight)
                  : null,
          onHint: _hintsRemaining > 0 ? _showHint : null,
          onSettings: _openSettings,
          onUndo:
              game.canUndo
                  ? () => _undoWithFlight(cardWidth, cardHeight)
                  : null,
          freezeCount: game.freezeCount,
          wandCount: game.wandCount,
          hintAvailable: hintAvailable,
          hintsRemaining: _hintsRemaining,
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

  Widget _buildPlayArea({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: NotificationListener<ScrollStartNotification>(
        onNotification: (_) {
          _wandFlight.stop();
          if (_transfers.isNotEmpty) setState(_clearFlight);
          return false;
        },
        child: Stack(
          key: _flightLayerKey,
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            Listener(
              onPointerCancel: (_) => _clearDraggingCards(),
              child: RepaintBoundary(child: child),
            ),
            for (final transfer in _transfers)
              AnimatedBuilder(
                animation: _travel,
                builder:
                    (_, _) => CardFlight(
                      key: transfer.key,
                      progress: _travel.value,
                      start: transfer.start,
                      end: transfer.end,
                      cards: transfer.cards,
                      offsets: transfer.offsets,
                      flip: transfer.flip,
                      packetSize: transfer.packetSize,
                      buildCard:
                          (card, faceUp) => CardWidget(
                            card:
                                faceUp == card.isFaceUp
                                    ? card
                                    : transfer.otherSide!,
                            width: transfer.start.width,
                            height: transfer.start.height,
                          ),
                    ),
              ),
            if (_wandReveal != null) _wandReveal!,
          ],
        ),
      ),
    );
  }

  WandLocation? _locateCard(PlayingCard card) {
    if (identical(game.stockTop, card)) {
      return const WandLocation(pile: WandPileType.stock, index: 0, depth: 0);
    }
    if (identical(game.wasteTop, card)) {
      return const WandLocation(pile: WandPileType.waste, index: 0, depth: 0);
    }
    for (var i = 0; i < _foundationKeys.length; i++) {
      if (identical(game.foundationTop(i), card)) {
        return WandLocation(pile: WandPileType.foundation, index: i, depth: 0);
      }
    }
    for (var i = 0; i < game.tableau.length; i++) {
      final depth = game.tableau[i].indexOf(card);
      if (depth >= 0) {
        return WandLocation(pile: WandPileType.tableau, index: i, depth: depth);
      }
    }
    return null;
  }

  Future<void> _openSettings() async {
    _wandFlight.stop();
    _settingsOpen = true;
    try {
      await showAppearancePanel(context);
    } finally {
      _settingsOpen = false;
      if (mounted) _scheduleAutoPlay();
    }
  }

  void _cancelAutoPlay() => _pendingAutoPlay = null;

  // Wait for the previous landing and its new layout. Undo, a new deal, or
  // another player move invalidates the callback with the old card references.
  void _scheduleAutoPlay() {
    final next = _pendingAutoPlay;
    if (next == null ||
        !_foreground ||
        _settingsOpen ||
        _newDealDialogOpen ||
        _travel.isAnimating) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(next, _pendingAutoPlay) ||
          !_foreground ||
          _settingsOpen ||
          _newDealDialogOpen ||
          _travel.isAnimating) {
        return;
      }
      _pendingAutoPlay = null;
      next();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _continueAfterMove(
    double width,
    double height, {
    int? foundationIndex,
    Iterator<AutoFinishStep>? finish,
  }) {
    if (game.isWon) return;
    _pendingAutoPlay = () {
      final route = finish ?? game.planAutoFinish()?.iterator;
      AutoFinishStep step;
      if (route != null && route.moveNext()) {
        step = route.current;
      } else {
        if (foundationIndex == null ||
            !context.read<AppearanceController>().autoCollectFoundations) {
          return;
        }
        final card = game.nextFoundationCard(foundationIndex);
        if (card == null) return;
        step = (action: AutoFinishAction.collect, card: card);
      }

      // The layout can change during a flight or while Settings is open.
      final size = _getGlobalRect(_stockKey)?.size ?? Size(width, height);
      final moved = _animateMove(
        step.card,
        size.width,
        size.height,
        () => game.playAutoFinishStep(step),
        flip: step.action == AutoFinishAction.draw,
        duration: Duration(milliseconds: route == null ? 145 : 90),
      );
      if (moved) {
        _continueAfterMove(
          size.width,
          size.height,
          foundationIndex: foundationIndex,
          finish: route,
        );
      }
    };
    _scheduleAutoPlay();
  }

  bool _moveWithFlight(
    PlayingCard card,
    double width,
    double height,
    VoidCallback apply, {
    Offset? release,
    bool flip = false,
  }) {
    final moved = _animateMove(
      card,
      width,
      height,
      apply,
      release: release,
      flip: flip,
    );
    if (moved) {
      final index = card.suit.index;
      _continueAfterMove(
        width,
        height,
        foundationIndex:
            identical(game.foundationTop(index), card) ? index : null,
      );
    }
    return moved;
  }

  // Apply the engine command once. Its actual destination and moved suffix
  // determine the artwork in flight.
  bool _animateMove(
    PlayingCard card,
    double width,
    double height,
    VoidCallback apply, {
    Offset? release,
    bool flip = false,
    Duration? duration,
  }) {
    final before = game.moves;
    final layer =
        _flightLayerKey.currentContext?.findRenderObject() as RenderBox?;
    if (_reduceMotion || !_foreground || layer == null || !layer.hasSize) {
      apply();
      return before != game.moves;
    }

    final source = _locateCard(card);
    final origin =
        release ??
        (source == null ? null : _computeGlobalOffset(source, width));
    final previousWaste = game.wasteTop;
    final previousFoundations = List.generate(
      _foundationKeys.length,
      game.foundationTop,
    );
    apply();
    if (game.moves == before) return false;
    final destination = _locateCard(card);
    if (origin == null || destination == null) return true;
    final landing = _computeGlobalOffset(destination, width);
    if (landing == null) return true;

    final cards =
        destination.pile == WandPileType.tableau
            ? game.tableau[destination.index].sublist(destination.depth)
            : [card];
    final size = Size(width, height);
    final transfer = _CardTransfer(
      start: layer.globalToLocal(origin) & size,
      end: layer.globalToLocal(landing) & size,
      destination: destination,
      cards: cards,
      offsets: List.generate(cards.length, (i) => _cardOffset(cards, i, width)),
      covered: switch (destination.pile) {
        WandPileType.waste => previousWaste,
        WandPileType.foundation => previousFoundations[destination.index],
        _ => null,
      },
      flip: flip,
    );
    _startFlights([transfer], layer, duration: duration);
    return true;
  }

  void _startFlights(
    List<_CardTransfer> transfers,
    RenderBox layer, {
    Duration? duration,
  }) {
    if (transfers.isEmpty) return;
    setState(() => _transfers = transfers);
    _travel.duration =
        duration ??
        (transfers.any((t) => t.flip)
            ? CardFlight.drawDuration
            : CardFlight.moveDuration);
    _travel.forward(from: 0);
    // Recheck after layout in case a shorter column clamped the scroll offset.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_transfers, transfers)) return;
      for (final flight in transfers) {
        final offset = _computeGlobalOffset(
          flight.destination,
          flight.end.width,
        );
        if (offset != null) {
          flight.end = layer.globalToLocal(offset) & flight.end.size;
        }
      }
    });
  }

  PlayingCard? _pileCover(WandLocation location) => switch (location.pile) {
    WandPileType.stock => game.stockTop,
    WandPileType.waste => game.wasteTop,
    WandPileType.foundation => game.foundationTop(location.index),
    WandPileType.tableau => null, // Underlying tableau cards are already drawn.
  };

  // When Undo interrupts a flight, depart from its current screen position
  // and visible side, even if the model has already committed the landing.
  (Offset?, bool) _undoOrigin(
    UndoCardChange change,
    RenderBox layer,
    double width,
  ) {
    for (final flight in _transfers) {
      final i = flight.cards.indexWhere((c) => c.id == change.card.id);
      if (i < 0) continue;
      final box = flight.key.currentContext?.findRenderObject() as RenderBox?;
      final local = Offset(0, flight.offsets[i]);
      final origin =
          box?.localToGlobal(local) ??
          layer.localToGlobal(flight.start.topLeft + local);
      final isUp = flight.cards[i].isFaceUp;
      final turned = !flight.flip || CardFlight.showsFinalSide(_travel.value);
      return (origin, turned ? isUp : !isUp);
    }
    return (_computeGlobalOffset(change.from, width), change.card.isFaceUp);
  }

  void _undoWithFlight(double width, double height) {
    final layer =
        _flightLayerKey.currentContext?.findRenderObject() as RenderBox?;
    if (_reduceMotion || !_foreground || layer == null || !layer.hasSize) {
      game.undo();
      return;
    }

    final changes = game.previewUndo();
    final groups = <List<UndoCardChange>>[];
    final moved =
        <(WandPileType, int, WandPileType, int), List<UndoCardChange>>{};
    for (final c in changes) {
      if (c.changesPile) {
        final route = (c.from.pile, c.from.index, c.to.pile, c.to.index);
        (moved[route] ??= []).add(c);
      } else {
        groups.add([c]); // A turned card is painted beneath its returning run.
      }
    }
    groups.addAll(moved.values);
    final origins = {for (final c in changes) c: _undoOrigin(c, layer, width)};
    final covers = {for (final c in changes) c: _pileCover(c.to)};
    if (!game.undo()) return;

    final flights = <_CardTransfer>[];
    for (final group in groups) {
      final packet =
          group.first.from.pile == WandPileType.stock &&
          group.first.to.pile == WandPileType.waste;
      // Waste restores from bottom to top. Its outer face is the packet's
      // final card; individual buried faces aren't exposed while it turns.
      final visible = packet ? [group.last] : group;
      final first = visible.first;
      final (origin, wasFaceUp) = origins[first]!;
      final landing = _computeGlobalOffset(first.to, width);
      if (origin == null || landing == null) continue;
      final cards = [
        for (final c in visible) c.card.clone()..isFaceUp = c.faceUpAfterUndo,
      ];
      final size = Size(width, height);
      flights.add(
        _CardTransfer(
          start: layer.globalToLocal(origin) & size,
          end: layer.globalToLocal(landing) & size,
          destination: first.to,
          cards: cards,
          offsets: List.generate(
            cards.length,
            (i) => _cardOffset(cards, i, width),
          ),
          covered: covers[first],
          flip: cards.length == 1 && wasFaceUp != cards.first.isFaceUp,
          packetSize: packet ? group.length : 1,
        ),
      );
    }
    _startFlights(flights, layer);
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
              final top = game.stockTop;
              if (top == null) {
                if (game.wasteTop != null) {
                  game.drawFromStock();
                  _continueAfterMove(w, h);
                }
              } else {
                _moveWithFlight(top, w, h, game.drawFromStock, flip: true);
              }
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
            _moveWithFlight(card, w, h, () => game.tapCard(card));
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
        final card = details.data.first;
        _moveWithFlight(
          card,
          w,
          h,
          () => game.moveCardToFoundation(card, index),
          release: details.offset,
        );
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
              if (card != null && !_showVictory)
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
          _moveWithFlight(card, w, h, () => game.tapCard(card));
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

  Widget _buildDragFeedback(
    List<PlayingCard> stack,
    double w,
    double h, {
    double artworkScale = 1,
  }) {
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
                  child: CardWidget(
                    card: stack[i],
                    width: w,
                    height: h,
                    artworkScale: artworkScale,
                  ),
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
    final pickup = _wandPickup;
    if (pickup != null) {
      final recycle = pickup.type == MagicWandActionType.recycleWaste;
      if (pickup.cards.contains(card) ||
          (recycle && identical(card, game.wasteTop))) {
        if (recycle || pickup.from!.pile == WandPileType.waste) {
          final below = recycle ? null : game.wasteUnderTop;
          return below == null
              ? _buildEmptySlotBox()
              : CardWidget(card: below, width: w, height: h);
        }
        if (pickup.from!.pile == WandPileType.tableau) {
          return SizedBox(width: w, height: h);
        }
        if (pickup.from!.depth == 0) return _buildEmptySlotBox();
        // The next stock card has the same back.
      }
    }
    for (final transfer in _transfers) {
      if (!transfer.cards.any((c) => c.id == card.id)) continue;
      // Keep the destination's real tap/drag target live during travel.
      final below = transfer.covered;
      return Semantics(
        image: true,
        label:
            card.isFaceUp
                ? '${card.displayValue} of ${card.suit.name}'
                : 'Face-down card',
        excludeSemantics: true,
        child: SizedBox(
          width: w,
          height: h,
          child:
              below == null
                  ? (transfer.destination.pile == WandPileType.stock ||
                          transfer.destination.pile == WandPileType.waste
                      ? _buildEmptySlotBox()
                      : null)
                  : CardWidget(card: below, width: w, height: h),
        ),
      );
    }
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
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _startTimerIfNeeded();
          _moveWithFlight(card, w, h, () => game.tapCard(card));
        },
        child:
            _draggingCards.contains(card)
                ? _buildDraggingGhost(card, w, h)
                : _buildHintableCard(card, w, h),
      ),
    );
  }

  void _handleDragStarted(List<PlayingCard> stack) {
    _wandFlight.stop();
    _cancelAutoPlay();
    _startTimerIfNeeded();
    setState(() {
      _clearFlight();
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

    final active = _draggingCards.contains(stack.first);
    final pointer = _dragPointers.remove(stack.first);
    final didUpdate = _clearDraggingCards();

    // Flutter reports cancellation and an unaccepted release the same way.
    // Only a real release from the active drag may trigger near-miss snapping.
    if (details.wasAccepted || !active) {
      return;
    }

    final dropPoint =
        pointer ?? details.offset + Offset(cardWidth / 2, cardHeight / 2);
    final moved = _autoSnapStack(
      stack,
      dropPoint,
      details.offset,
      cardWidth,
      cardHeight,
    );
    if (!moved && !didUpdate) {
      setState(() {});
    }
  }

  bool _autoSnapStack(
    List<PlayingCard> stack,
    Offset dropPoint,
    Offset release,
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

    final target = bestTarget;
    return _moveWithFlight(
      stack.first,
      cardWidth,
      cardHeight,
      () => switch (target.type) {
        _AutoDropType.tableau => game.moveStackToTableau(stack, target.index),
        _AutoDropType.foundation => game.moveCardToFoundation(
          stack.first,
          target.index,
        ),
      },
      release: release,
    );
  }

  Future<void> _animateWandAction(
    MagicWandAction action,
    double cardWidth,
    double cardHeight,
  ) async {
    final layer =
        _flightLayerKey.currentContext?.findRenderObject() as RenderBox?;
    if (layer == null || !layer.hasSize) return;
    final recycle = action.type == MagicWandActionType.recycleWaste;
    final from =
        recycle
            ? const WandLocation(pile: WandPileType.waste, index: 0, depth: 0)
            : action.from!;
    final to =
        recycle
            ? const WandLocation(pile: WandPileType.stock, index: 0, depth: 0)
            : action.to ??
                from; // A tableau flip lands back in the same column.
    final start = _computeGlobalOffset(from, cardWidth);
    final end = _computeGlobalOffset(to, cardWidth);
    if (start == null || end == null) return;

    final cards =
        recycle
            ? [game.wasteTop!.clone()]
            : action.cards.map((card) => card.clone()).toList();
    final flip = recycle || !cards.first.isFaceUp;
    final after = flip ? (cards.first.clone()..isFaceUp = !recycle) : null;
    setState(() {
      _wandPickup = action;
      _wandReveal = WandRevealFlight(
        animation: _wandFlight,
        start: layer.globalToLocal(start),
        end: layer.globalToLocal(end),
        area: layer.size,
        cardSize: Size(cardWidth, cardHeight),
        before: _buildDragFeedback(
          cards,
          cardWidth,
          cardHeight,
          artworkScale: WandRevealFlight.focusScale,
        ),
        after:
            after == null
                ? null
                : _buildDragFeedback(
                  [after],
                  cardWidth,
                  cardHeight,
                  artworkScale: WandRevealFlight.focusScale,
                ),
      );
    });

    var feltReveal = false;
    void tickAtReveal() {
      if (!feltReveal && _wandFlight.value >= WandRevealFlight.revealEdge) {
        feltReveal = true;
        HapticFeedback.selectionClick();
      }
    }

    _wandFlight.addListener(tickAtReveal);
    try {
      await _wandFlight.forward(from: 0).orCancel;
    } finally {
      _wandFlight.removeListener(tickAtReveal);
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

class _CardTransfer {
  _CardTransfer({
    required this.start,
    required this.end,
    required this.cards,
    required this.offsets,
    required this.covered,
    required this.destination,
    required bool flip,
    this.packetSize = 1,
  }) : otherSide =
           flip
               ? (cards.single.clone()..isFaceUp = !cards.single.isFaceUp)
               : null;

  final Rect start;
  Rect end;
  final List<PlayingCard> cards;
  final List<double> offsets;
  final PlayingCard? covered;
  final WandLocation destination;
  final key = GlobalKey();
  final PlayingCard? otherSide;
  final int packetSize;
  bool get flip => otherSide != null;
}

class _AutoDropTarget {
  const _AutoDropTarget(this.type, this.index, this.distance);

  final _AutoDropType type;
  final int index;
  final double distance;
}

enum _AutoDropType { tableau, foundation }
