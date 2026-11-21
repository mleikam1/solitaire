import 'package:flutter_test/flutter_test.dart';
import 'package:solitaire/game/board_snapshot.dart';
import 'package:solitaire/game/deal_spec.dart';
import 'package:solitaire/game/klondike_game.dart';
import 'package:solitaire/models/card_model.dart';

int hearts(int rank) => DealSpec.cardId(Suit.hearts, rank);
int diamonds(int rank) => DealSpec.cardId(Suit.diamonds, rank);
int clubs(int rank) => DealSpec.cardId(Suit.clubs, rank);
int spades(int rank) => DealSpec.cardId(Suit.spades, rank);

/// Construct a complete board. The unlisted cards stay face-down in stock.
Map<String, Object?> position({
  required List<List<int>> columns,
  List<int> waste = const [],
  List<List<int>> foundations = const [[], [], [], []],
  Set<int> hidden = const {},
}) {
  final assigned = {
    ...columns.expand((pile) => pile),
    ...waste,
    ...foundations.expand((pile) => pile),
  };
  List<Map<String, Object>> pack(List<int> pile) => [
    for (final id in pile) {'id': id, 'up': !hidden.contains(id)},
  ];
  return {
    'version': BoardSnapshot.version,
    'deal': DealSpec(seed: 1).toJson(),
    'tableau': [
      for (final pile in columns) pack(pile),
      for (var i = columns.length; i < 7; i++) [],
    ],
    'waste': pack(waste),
    'foundations': foundations.map(pack).toList(),
    'stock': [
      for (var id = 0; id < 52; id++)
        if (!assigned.contains(id)) {'id': id, 'up': false},
    ],
    'score': 0,
    'moves': 0,
    'freezeCount': 2,
    'wandCount': 3,
  };
}

void main() {
  test('5 spades cannot land on 6 clubs via drag, tap, hint or Wand', () {
    final game = KlondikeGame.fromSnapshot(
      BoardSnapshot.fromJson(
        position(
          columns: [
            [clubs(6)],
            [spades(5)],
          ],
        ),
      ),
    );
    final five = game.tableau[1].single;
    final before = game.snapshot().encode();
    var notifications = 0;
    game.addListener(() => notifications++);

    expect(game.moveStackToTableau([five], 0), isFalse);
    game.tapCard(five);
    expect(game.computeHint()!.action, HintActionType.drawFromStock);
    expect(
      game.planMagicWand()!.actions.single.type,
      MagicWandActionType.drawFromStock,
    );
    final illegalPlan = MagicWandPlan([
      MagicWandAction(
        type: MagicWandActionType.moveToTableau,
        cards: [five],
        from: const WandLocation(
          pile: WandPileType.tableau,
          index: 1,
          depth: 0,
        ),
        to: const WandLocation(pile: WandPileType.tableau, index: 0, depth: 1),
      ),
    ]);
    expect(game.executeMagicWand(illegalPlan), isFalse);
    expect(game.snapshot().encode(), before);
    expect(game.canUndo, isFalse);
    expect(notifications, 0);
  });

  test('tap, hint and Wand agree on a legal red five onto a black six', () {
    final wire = position(
      columns: [
        [clubs(6)],
        [hearts(5)],
      ],
    );
    final game = KlondikeGame.fromSnapshot(BoardSnapshot.fromJson(wire));
    final hint = game.computeHint()!;
    expect(hint.action, HintActionType.moveToTableau);
    expect(hint.cards.single.id, hearts(5));
    expect(hint.destinationTableauIndex, 0);
    game.tapCard(game.tableau[1].single);
    expect(game.tableau[0].map((c) => c.id), [clubs(6), hearts(5)]);
    expect(game.undo(), isTrue);
    expect(game.snapshot().toJson(), wire);
    final plan = game.planMagicWand()!;
    expect(plan.actions.single.type, MagicWandActionType.moveToTableau);
    expect(game.executeMagicWand(plan), isTrue);
    expect(game.tableau[0].map((c) => c.id), [clubs(6), hearts(5)]);
    expect(game.snapshot().tableau[1], isEmpty);
  });

  test('tableau accepts one rank down across all red/black suit pairs', () {
    final game = KlondikeGame.fromDeal(DealSpec(seed: 1));
    final redSuits = {Suit.hearts, Suit.diamonds};
    for (final upper in Suit.values) {
      for (final lower in Suit.values) {
        final six = PlayingCard(suit: upper, rank: 6, isFaceUp: true);
        final five = PlayingCard(suit: lower, rank: 5, isFaceUp: true);
        expect(
          game.canPlaceOnTableau(six, five),
          redSuits.contains(upper) != redSuits.contains(lower),
          reason: '5 of ${lower.name} on 6 of ${upper.name}',
        );
        final four = PlayingCard(suit: lower, rank: 4, isFaceUp: true);
        expect(game.canPlaceOnTableau(six, four), isFalse);
      }
    }
  });

  test('only a King or a complete King-led run can fill an empty column', () {
    final wire = position(
      columns: [
        [spades(13), diamonds(12), clubs(11)],
      ],
      waste: [hearts(5)],
    );
    final game = KlondikeGame.fromSnapshot(BoardSnapshot.fromJson(wire));
    final column = game.tableau.first;
    final run = column.toList();
    expect(game.moveStackToTableau([game.wasteTop!], 1), isFalse);
    expect(game.moveStackToTableau(run.sublist(1), 1), isFalse);
    expect(game.moveStackToTableau([run.first], 1), isFalse);
    expect(game.moveStackToTableau([run.first, run.last], 1), isFalse);
    expect(
      game.moveStackToTableau([run.first.clone(), ...run.skip(1)], 1),
      isFalse,
    );
    expect(game.canUndo, isFalse);
    expect(game.moveStackToTableau(run, 1), isTrue);
    expect(game.tableau[0], isEmpty);
    expect(game.tableau[1], run);
    expect(game.undo(), isTrue);
    expect(game.snapshot().toJson(), wire);
  });

  test('a Wand plan can move the live source column and undo the move', () {
    final runIds = [spades(13), diamonds(12), clubs(11)];
    final wire = position(columns: [runIds]);
    final game = KlondikeGame.fromSnapshot(BoardSnapshot.fromJson(wire));
    final plan = MagicWandPlan([
      MagicWandAction(
        type: MagicWandActionType.moveToTableau,
        cards: game.tableau[0],
        from: const WandLocation(
          pile: WandPileType.tableau,
          index: 0,
          depth: 0,
        ),
        to: const WandLocation(pile: WandPileType.tableau, index: 1, depth: 0),
      ),
    ]);
    expect(game.executeMagicWand(plan), isTrue);
    final moved = game.snapshot(); // Also validates all 52 distinct card IDs.
    expect(moved.tableau[0], isEmpty);
    expect(moved.tableau[1].map((card) => card.id), runIds);
    expect(moved.moves, 1);
    expect(moved.wandCount, 2);
    expect(game.undo(), isTrue);
    expect(game.snapshot().toJson(), wire);
  });

  test('only exposed single cards build foundations by suit from the Ace', () {
    final wire = position(
      columns: [
        [hearts(1), clubs(6)],
        [diamonds(1)],
        [diamonds(2)],
        [diamonds(3)],
      ],
      hidden: {hearts(1)},
    );
    final game = KlondikeGame.fromSnapshot(BoardSnapshot.fromJson(wire));
    final hiddenAce = game.tableau[0].first;
    expect(game.moveCardToFoundation(hiddenAce, 0), isFalse);
    game.tapCard(hiddenAce);
    expect(game.moveCardToFoundation(game.tableau[1].last, 0), isFalse);
    expect(game.moveCardToFoundation(game.tableau[2].last, 1), isFalse);
    expect(game.snapshot().toJson(), wire);
    expect(game.canUndo, isFalse);
    expect(game.moveCardToFoundation(game.tableau[1].last, 1), isTrue);
    expect(game.moveCardToFoundation(game.tableau[3].last, 1), isFalse);
    expect(game.moveCardToFoundation(game.tableau[2].last, 1), isTrue);
    expect(game.foundationTop(1)!.id, diamonds(2));
    expect(game.moves, 2);
  });

  test('Wand cannot remove an interior card and leave a broken run', () {
    final wire = position(
      columns: [
        [clubs(7), hearts(6), spades(5)],
      ],
      foundations: [
        [for (var i = 1; i <= 5; i++) hearts(i)],
        [],
        [],
        [],
      ],
    );
    final game = KlondikeGame.fromSnapshot(BoardSnapshot.fromJson(wire));
    final six = game.tableau[0][1];
    expect(game.moveCardToFoundation(six, 0), isFalse);
    expect(
      game.executeMagicWand(
        MagicWandPlan([
          MagicWandAction(
            type: MagicWandActionType.moveToFoundation,
            cards: [six],
            from: const WandLocation(
              pile: WandPileType.tableau,
              index: 0,
              depth: 1,
            ),
            to: const WandLocation(
              pile: WandPileType.foundation,
              index: 0,
              depth: 5,
            ),
          ),
        ]),
      ),
      isFalse,
    );
    expect(game.snapshot().toJson(), wire);
    final plan = game.planMagicWand()!;
    expect(plan.actions.single.type, MagicWandActionType.drawFromStock);
    expect(game.executeMagicWand(plan), isTrue);
    expect(game.snapshot().tableau[0].map((card) => card.id), [
      clubs(7),
      hearts(6),
      spades(5),
    ]);
  });

  test(
    'tableau snapshot rejects same colors and rank gaps in visible runs',
    () {
      expect(DealSpec(seed: 1).toJson()['rules'], 'klondike-draw1-v1');
      for (final bad in [
        [clubs(6), spades(5)],
        [hearts(6), diamonds(5)],
        [clubs(7), diamonds(5)],
      ]) {
        expect(
          () => BoardSnapshot.fromJson(position(columns: [bad])),
          throwsFormatException,
        );
      }
      final wire = position(
        columns: [
          [clubs(6), spades(5)],
        ],
        hidden: {clubs(6)},
      );
      expect(BoardSnapshot.fromJson(wire).toJson(), wire);
    },
  );
}
