import 'package:flutter/material.dart';
import '../models/card_model.dart'; // brings in PlayingCard, Suit, etc.
import '../utils/board_metrics.dart';
import 'card_widget.dart';

class TableauPile {
  final List<PlayingCard> cards;
  TableauPile(this.cards);
}

class FoundationPile {
  final List<PlayingCard> cards;
  FoundationPile(this.cards);
}

class StockWaste {
  final List<PlayingCard> stock;
  final List<PlayingCard> waste;
  StockWaste(this.stock, this.waste);
}

class SolitaireBoard extends StatelessWidget {
  final List<TableauPile> tableau; // 7 columns
  final List<FoundationPile> foundation; // 4 piles
  final StockWaste stockWaste;

  const SolitaireBoard({
    super.key,
    required this.tableau,
    required this.foundation,
    required this.stockWaste,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      bottom: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final m = BoardMetrics.fromConstraints(constraints);
          const topRowPad = 12.0;

          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8 + 56),
            child: Column(
              children: [
                // Top row: stock/waste | 4 foundations
                SizedBox(
                  height: m.cardHeight,
                  child: Row(
                    children: [
                      // Stock placeholder
                      _cardSlot(m),
                      SizedBox(width: m.hGap),
                      // Waste (top of waste or placeholder)
                      _wasteSlot(m),
                      const Spacer(),
                      // Foundations (4)
                      for (int i = 0; i < 4; i++) ...[
                        _foundationSlot(m, foundation[i]),
                        if (i != 3) SizedBox(width: m.hGap),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: topRowPad),
                // Tableau
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(7, (col) {
                      return Padding(
                        padding: EdgeInsets.only(right: col == 6 ? 0 : m.hGap),
                        child: _tableauColumn(m, tableau[col]),
                      );
                    }),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _cardSlot(BoardMetrics m) {
    return Container(
      width: m.cardWidth,
      height: m.cardHeight,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }

  Widget _wasteSlot(BoardMetrics m) {
    final top = stockWaste.waste.isNotEmpty ? stockWaste.waste.last : null;
    if (top == null) return _cardSlot(m);
    return CardWidget(card: top, width: m.cardWidth, height: m.cardHeight);
  }

  Widget _foundationSlot(BoardMetrics m, FoundationPile pile) {
    return pile.cards.isEmpty
        ? _cardSlot(m)
        : CardWidget(
      card: pile.cards.last,
      width: m.cardWidth,
      height: m.cardHeight,
    );
  }

  Widget _tableauColumn(BoardMetrics m, TableauPile pile) {
    final cards = pile.cards;

    // Empty column target
    if (cards.isEmpty) return _emptyTableauSlot(m);

    return SizedBox(
      width: m.cardWidth,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < cards.length; i++)
            Positioned(
              top: _offsetForIndex(m, cards[i].isFaceUp, i, cards),
              child: CardWidget(
                card: cards[i],
                width: m.cardWidth,
                height: m.cardHeight,
              ),
            ),
        ],
      ),
    );
  }

  double _offsetForIndex(
      BoardMetrics m,
      bool isFaceUp,
      int index,
      List<PlayingCard> all,
      ) {
    // Offset is cumulative: face-down smaller overlap, face-up larger
    double offset = 0;
    for (int i = 0; i < index; i++) {
      offset += all[i].isFaceUp ? m.vGapFaceUp : m.vGapFaceDown;
    }
    return offset;
  }

  Widget _emptyTableauSlot(BoardMetrics m) {
    return Container(
      width: m.cardWidth,
      height: m.cardHeight,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }
}
