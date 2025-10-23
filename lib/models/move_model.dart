import 'card_model.dart';

enum PileKind { stock, waste, foundation, tableau }

class PileRef {
  final PileKind kind;
  final int index; // foundation 0..3, tableau 0..6, stock/waste=0
  const PileRef(this.kind, this.index);
}

class Move {
  final PileRef from;
  final PileRef to;
  final List<PlayingCard> cardsMoved;
  final bool flippedSourceTop; // whether we flipped a face-down after move

  Move({
    required this.from,
    required this.to,
    required this.cardsMoved,
    this.flippedSourceTop = false,
  });
}
