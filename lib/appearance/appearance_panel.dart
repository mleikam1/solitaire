import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/card_model.dart';
import '../widgets/card_widget.dart';
import 'appearance.dart';
import 'table_surface.dart';

const _paper = Color(0xFFFAF7F0);
const _ink = Color(0xFF1E3029);
const _pine = Color(0xFF205541);
const _rule = Color(0xFFD4D7CB);

Future<void> showAppearancePanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 600),
    backgroundColor: _paper,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) => const _AppearancePanel(),
  );
}

class _AppearancePanel extends StatefulWidget {
  const _AppearancePanel();

  @override
  State<_AppearancePanel> createState() => _AppearancePanelState();
}

class _AppearancePanelState extends State<_AppearancePanel> {
  bool _showDecks = true;

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppearanceController>();
    final textScaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, bounds) {
        final height = math.min(bounds.maxHeight * 0.92, 720.0);
        final compact = bounds.maxWidth < 380;
        final scrollWholePanel = height < 510 || textScaler.scale(16) > 24;
        final padding = compact ? 16.0 : 20.0;
        final sample = _LiveSample(
          deck: appearance.deck,
          table: appearance.table,
          height: compact ? 120 : 144,
        );
        final picker = Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: SegmentedButton<bool>(
            expandedInsets: EdgeInsets.zero,
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Deck'),
                icon: Icon(Icons.style_outlined),
              ),
              ButtonSegment(
                value: false,
                label: Text('Table'),
                icon: Icon(Icons.landscape_outlined),
              ),
            ],
            selected: {_showDecks},
            onSelectionChanged:
                (choice) => setState(() => _showDecks = choice.single),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              backgroundColor: _paper,
              foregroundColor: _ink,
              selectedBackgroundColor: _pine,
              selectedForegroundColor: Colors.white,
              side: const BorderSide(color: _rule),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
        final areaWidth = bounds.maxWidth - 2 * padding;
        final minTileWidth = math.max(96.0, textScaler.scale(86));
        final columns = math.max(
          1,
          math.min(_showDecks ? 3 : 4, (areaWidth + 8) ~/ (minTileWidth + 8)),
        );
        final grid = GridView.count(
          key: PageStorageKey(
            _showDecks ? 'appearance-decks' : 'appearance-tables',
          ),
          primary: false,
          shrinkWrap: scrollWholePanel,
          physics:
              scrollWholePanel ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.only(bottom: 4),
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          mainAxisExtent:
              (columns < 3 ? 86.0 : 72.0) + textScaler.scale(35) + 8,
          children:
              _showDecks
                  ? [
                    for (final deck in DeckStyle.values)
                      _ChoiceTile(
                        key: ValueKey('deck-${deck.id}'),
                        label: deck.label,
                        selected: deck == appearance.deck,
                        onTap: () => appearance.setDeck(deck),
                        art: Center(child: _CardFan(deck: deck, width: 39)),
                      ),
                  ]
                  : [
                    for (final table in TableStyle.values)
                      _ChoiceTile(
                        key: ValueKey('table-${table.id}'),
                        label: table.label,
                        selected: table == appearance.table,
                        onTap: () => appearance.setTable(table),
                        art: TableSurface(
                          table: table,
                          alignment: Alignment.bottomCenter,
                        ),
                      ),
                  ],
        );
        return SizedBox(
          height: height,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 5),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Appearance',
                            style: TextStyle(
                              fontFamily: 'Georgia',
                              fontFamilyFallback: ['serif'],
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              color: _ink,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close Appearance',
                          icon: const Icon(Icons.close_rounded),
                          color: _ink,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  if (scrollWholePanel)
                    Expanded(child: ListView(children: [sample, picker, grid]))
                  else ...[
                    sample,
                    picker,
                    Expanded(child: grid),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: _pine),
                      onPressed: appearance.restoreDefaults,
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('Restore Defaults'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.art,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget art;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(12);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? const Color(0xFFEDF3ED) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(
            color: selected ? _pine : _rule,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ColoredBox(
                        color: const Color(0xFFEDEAE0),
                        child: SizedBox.expand(child: art),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: MediaQuery.textScalerOf(context).scale(35),
                    child: Center(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                right: 7,
                top: 7,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _pine,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.check, size: 13, color: Colors.white),
                  ),
                ),
              ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap, borderRadius: borderRadius),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveSample extends StatelessWidget {
  const _LiveSample({
    required this.deck,
    required this.table,
    required this.height,
  });

  final DeckStyle deck;
  final TableStyle table;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Preview: ${deck.label} on ${table.label}',
      excludeSemantics: true,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              TableSurface(table: table, alignment: Alignment.bottomCenter),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xCB10271F),
                      Color(0x8F10271F),
                      Color(0x0010271F),
                    ],
                    stops: [0, 0.48, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              deck.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Georgia',
                                fontFamilyFallback: ['serif'],
                                fontSize: 25,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              table.label,
                              style: const TextStyle(
                                color: Color(0xFFF2EFE4),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CardFan(deck: deck, width: height * 0.42, showRun: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardFan extends StatelessWidget {
  const _CardFan({
    required this.deck,
    required this.width,
    this.showRun = false,
  });

  final DeckStyle deck;
  final double width;
  final bool showRun;

  // These samples never participate in the deal or its card-ID sequence.
  static final _back = PlayingCard(rank: 1, suit: Suit.spades, id: -1);
  static final _king = PlayingCard(
    rank: 13,
    suit: Suit.spades,
    isFaceUp: true,
    id: -2,
  );
  static final _queen = PlayingCard(
    rank: 12,
    suit: Suit.hearts,
    isFaceUp: true,
    id: -3,
  );

  @override
  Widget build(BuildContext context) {
    Widget card(PlayingCard sample, double left, double angle) => Positioned(
      left: left,
      top: 4,
      child: Transform.rotate(
        angle: angle,
        child: CardWidget(
          card: sample,
          width: width,
          height: width * 1.4,
          deck: deck,
        ),
      ),
    );
    return SizedBox(
      width: width * (showRun ? 2.2 : 1.7),
      height: width * 1.4 + 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card(_back, width * 0.09, -0.14),
          if (showRun) card(_king, width * 0.62, -0.04),
          card(_queen, width * (showRun ? 1.12 : 0.61), 0.10),
        ],
      ),
    );
  }
}
