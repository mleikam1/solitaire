import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../appearance/appearance.dart';
import '../models/card_model.dart';
import 'card_widget.dart';

const _gold = Color(0xFFF3CF81);
const _ivory = Color(0xFFFFF7E5);

/// Full-board overlay. Foundation rectangles are in this overlay's coordinates,
/// ordered hearts, diamonds, clubs, and spades, just like the game foundations.
class VictoryCelebration extends StatefulWidget {
  const VictoryCelebration({
    super.key,
    required this.foundations,
    required this.deck,
    required this.score,
    required this.moves,
    required this.elapsed,
    required this.onNewDeal,
    required this.onUndo,
  });

  final List<Rect> foundations;
  final DeckStyle deck;
  final int score;
  final int moves;
  final String elapsed;
  final VoidCallback onNewDeal;
  final VoidCallback? onUndo;

  @override
  State<VictoryCelebration> createState() => _VictoryCelebrationState();
}

class _VictoryCelebrationState extends State<VictoryCelebration>
    with SingleTickerProviderStateMixin {
  late final _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );
  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion == _reduceMotion) return;
    final firstBuild = _reduceMotion == null;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _clock.value = 1;
    } else if (firstBuild) {
      HapticFeedback.mediumImpact();
      _clock.forward();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flights = <_Flight>[];
    for (int suit = 0; suit < math.min(4, widget.foundations.length); suit++) {
      final source = widget.foundations[suit];
      if (source.isEmpty) continue;
      for (int order = 0; order < 13; order++) {
        flights.add(_Flight(source, suit, order, widget.deck));
      }
    }
    final result = _WinPanel(
      score: widget.score,
      moves: widget.moves,
      elapsed: widget.elapsed,
      onNewDeal: widget.onNewDeal,
      onUndo: widget.onUndo,
    );
    return BlockSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          return AnimatedBuilder(
            animation: _clock,
            child: result,
            builder: (context, child) {
              final t = _clock.value;
              final still = _reduceMotion!;
              final reveal = const Interval(
                .35,
                .54,
                curve: Curves.easeOutCubic,
              ).transform(t);
              final stationary = <Widget>[];
              final airborne = <Widget>[];
              for (final flight in flights) {
                final age = (t - flight.start) / flight.duration;
                // Expose the next face in each stack as its predecessor lifts.
                if (still
                    ? flight.order == 0
                    : age < 0 &&
                        (flight.order == 0 || t >= flight.start - .040)) {
                  stationary.add(
                    Positioned.fromRect(rect: flight.source, child: flight.art),
                  );
                } else if (!still && age >= 0 && age < 1) {
                  airborne.add(flight.inAir(size, age));
                }
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(child: Stack(children: stationary)),
                  ModalBarrier(
                    dismissible: false,
                    color: Color.lerp(
                      const Color(0x180B1817),
                      const Color(0xAD051C19),
                      Curves.easeOut.transform((t / .54).clamp(0, 1)),
                    ),
                  ),
                  if (!still && t < 1)
                    IgnorePointer(
                      child: ExcludeSemantics(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CustomPaint(
                              painter: _Streamers(t, widget.foundations),
                            ),
                            ...airborne,
                          ],
                        ),
                      ),
                    ),
                  if (reveal > 0)
                    SafeArea(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Transform.translate(
                            offset: Offset(0, 20 * (1 - reveal)),
                            child: Opacity(opacity: reveal, child: child),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Flight {
  _Flight(this.source, this.suit, this.order, DeckStyle deck)
    : art = RepaintBoundary(
        child: CardWidget(
          width: source.width,
          height: source.height,
          deck: deck,
          card: PlayingCard(
            rank: 13 - order,
            suit: Suit.values[suit],
            isFaceUp: true,
            id: -1 - suit * 13 - order,
          ),
        ),
      );

  final Rect source;
  final int suit;
  final int order;
  final Widget art;

  double get start => order * .040 + suit * .008 + .012;
  double get duration => .37 + ((order + suit * 2) % 5) * .012;

  Widget inAir(Size size, double age) {
    final seed = order * 7 + suit * 11;
    final direction = (order + suit).isEven ? -1.0 : 1.0;
    final lift = size.height * (.48 + seed % 8 * .045);
    final drop = size.height + source.height - source.center.dy;
    final y = source.center.dy + (drop + lift) * age * age - lift * age;
    // Reflect at the sides, like classic Solitaire's bouncing victory cards.
    final margin = source.width * .32;
    final span = math.max(1.0, size.width - 2 * margin);
    final travel = size.width * (.48 + seed % 9 * .078);
    final distance =
        (source.center.dx - margin + direction * travel * age) % (2 * span);
    final x = margin + (distance <= span ? distance : 2 * span - distance);
    return Positioned(
      key: ValueKey((suit, order)),
      left: x - source.width / 2,
      top: y - source.height / 2,
      width: source.width,
      height: source.height,
      child: Transform.rotate(
        angle: direction * (.75 + seed % 4 * .30) * math.pi * age,
        child: art,
      ),
    );
  }
}

class _Streamers extends CustomPainter {
  const _Streamers(this.t, this.sources);

  final double t;
  final List<Rect> sources;
  static const _colors = [_gold, Color(0xFF9AEACB), Color(0xFFFF9B87), _ivory];

  @override
  void paint(Canvas canvas, Size size) {
    final brush = Paint()..strokeCap = StrokeCap.round;
    for (int s = 0; s < sources.length; s++) {
      final start = sources[s].center;
      for (int i = 0; i < 16; i++) {
        final age = (t - (i ~/ 4) * .125 - s * .008 - .012) / .41;
        if (age < 0 || age >= 1) continue;
        final seed = i * 17 + s * 23;
        final dx = (i.isEven ? 1 : -1) * size.width * (.22 + seed % 7 * .055);
        final lift = size.height * (.36 + seed % 5 * .095);
        final x = start.dx + dx * age + 9 * math.sin(age * 12 + i) * age;
        final y = start.dy - lift * age + size.height * .96 * age * age;
        final angle = seed + age * math.pi * 3;
        final delta =
            Offset(math.cos(angle), math.sin(angle)) *
            (2 + (seed % 4).toDouble());
        brush
          ..color = _colors[(i + s) % _colors.length].withValues(
            alpha: (1 - age) * .9,
          )
          ..strokeWidth = 1.8 + seed % 2;
        canvas.drawLine(Offset(x, y) - delta, Offset(x, y) + delta, brush);
      }
    }
  }

  @override
  bool shouldRepaint(_Streamers oldDelegate) =>
      oldDelegate.t != t || oldDelegate.sources != sources;
}

class _WinPanel extends StatelessWidget {
  const _WinPanel({
    required this.score,
    required this.moves,
    required this.elapsed,
    required this.onNewDeal,
    required this.onUndo,
  });

  final int score;
  final int moves;
  final String elapsed;
  final VoidCallback onNewDeal;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 356),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF234C40), Color(0xFF102C2A)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFB79F69), width: 1.3),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 20,
              offset: Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _Rule(),
                  const SizedBox(width: 10),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _gold),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF426B4B), Color(0xFF214639)],
                      ),
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      size: 36,
                      color: _gold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const _Rule(mirror: true),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              liveRegion: true,
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Congratulations!',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontWeight: FontWeight.w700,
                    fontSize: 34,
                    color: _ivory,
                    height: 1.15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: const BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: Color(0xFF517063)),
                ),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 14,
                runSpacing: 8,
                children: [
                  _Stat('Score', score.toString()),
                  _Stat('Moves', moves.toString()),
                  _Stat('Time', elapsed),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onNewDeal,
                style: FilledButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: const Color(0xFF17372E),
                  minimumSize: const Size(0, 48),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                icon: const Icon(Icons.style_rounded, size: 20),
                label: const Text('New deal'),
              ),
            ),
            if (onUndo != null)
              TextButton.icon(
                onPressed: onUndo,
                style: TextButton.styleFrom(
                  foregroundColor: _ivory,
                  minimumSize: const Size(88, 48),
                ),
                icon: const Icon(Icons.undo_rounded, size: 16),
                label: const Text('Undo'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: _ivory,
              fontWeight: FontWeight.bold,
              fontSize: 19,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Color(0xFFCEE0CE), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({this.mirror = false});
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: mirror ? TextDirection.rtl : TextDirection.ltr,
      children: [
        Container(width: 34, height: 1, color: const Color(0xFF8E996B)),
        const SizedBox(width: 4),
        Transform.rotate(
          angle: math.pi / 4,
          child: Container(width: 5, height: 5, color: _gold),
        ),
      ],
    );
  }
}
