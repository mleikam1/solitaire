import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:solitaire/game/board_snapshot.dart';
import 'package:solitaire/game/deal_spec.dart';
import 'package:solitaire/game/klondike_game.dart';
import 'package:solitaire/models/card_model.dart';

typedef WireMap = Map<String, dynamic>;

KlondikeGame _newGame(int seed) => KlondikeGame.fromDeal(DealSpec(seed: seed));

WireMap _wire(KlondikeGame game) =>
    jsonDecode(game.snapshot().encode()) as WireMap;

void main() {
  group('v1 deal replay', () {
    test('seed 1 matches all 52 v1 card positions and initial faces', () {
      final snapshot = _newGame(1).snapshot();
      const expectedTableau = [
        [14],
        [38, 35],
        [17, 0, 8],
        [51, 4, 30, 45],
        [36, 19, 26, 29, 2],
        [41, 44, 28, 12, 23, 3],
        [22, 40, 9, 33, 31, 39, 49],
      ];
      const expectedStock = [
        37,
        42,
        47,
        10,
        6,
        48,
        34,
        13,
        25,
        5,
        21,
        43,
        18,
        50,
        20,
        27,
        7,
        11,
        16,
        32,
        46,
        1,
        15,
        24,
      ];

      for (var i = 0; i < expectedTableau.length; i++) {
        final column = snapshot.tableau[i];
        expect(column.map((c) => c.id), expectedTableau[i]);
        expect(column.take(i).every((c) => !c.isFaceUp), isTrue);
        expect(column.last.isFaceUp, isTrue);
      }
      expect(snapshot.stock.map((c) => c.id), expectedStock);
      expect(snapshot.stock.every((c) => !c.isFaceUp), isTrue);
      expect(snapshot.waste, isEmpty);
      expect(snapshot.foundations, everyElement(isEmpty));
      expect(snapshot.moves, 0);
      expect(snapshot.score, 0);

      // Largest supported seed, including the same card ordering on the web.
      final other = _newGame(2147483646).snapshot();
      expect(other.tableau.first.single.id, 7);
      expect(other.stock.last.id, 51);
    });

    test('v1 rejects a biased random sample before the first swap', () {
      // This seed produces 2147483645 as its first zero-based sample.
      // A simple modulo-52 implementation deals card 21 instead.
      expect(_newGame(247665088).tableau[0].single.id, 7);
    });

    test('sharing the deal after playing reproduces its original baseline', () {
      final owner = KlondikeGame.fromDeal(
        DealSpec(seed: 3, initialWandCount: 2, initialFreezeCount: 1),
      );
      final initial = _wire(owner);
      owner.drawFromStock();
      expect(owner.executeMagicWand(owner.planMagicWand()!), isTrue);
      owner.freezeCount--;
      final challenger = KlondikeGame.fromDeal(
        DealSpec.fromJson(jsonDecode(jsonEncode(owner.deal.toJson()))),
      );
      expect(_wire(challenger), initial);
      expect(challenger.canUndo, isFalse);
      expect(owner.moves, 2);

      // The existing New Deal action carries remaining inventory forward.
      owner.newDeal();
      final ordinaryDeal = KlondikeGame.fromDeal(owner.deal);
      expect(owner.freezeCount, 0);
      expect(owner.wandCount, 1);
      expect(_wire(ordinaryDeal), _wire(owner));
    });

    test('24 stock draws, recycle and undo preserve exact order', () {
      final game = _newGame(1);
      final firstDrawOrder = game.snapshot().stock.reversed.map((c) => c.id);
      final drawn = <int>[];
      for (var i = 0; i < 24; i++) {
        game.drawFromStock();
        drawn.add(game.wasteTop!.id);
      }
      expect(drawn, firstDrawOrder);
      expect(game.stockTop, isNull);
      expect(game.snapshot().waste.every((c) => c.isFaceUp), isTrue);
      final beforeRecycle = _wire(game);
      game.drawFromStock();
      expect(game.snapshot().stock.map((c) => c.id), drawn.reversed);
      expect(game.snapshot().stock.every((c) => !c.isFaceUp), isTrue);
      expect(game.wasteTop, isNull);
      expect(game.moves, 25);
      game.drawFromStock();
      expect(game.wasteTop!.id, drawn.first);
      expect(game.undo(), isTrue);
      expect(game.undo(), isTrue);
      expect(_wire(game), beforeRecycle);
    });

    test(
      'actual drag, stack, foundation, wand and undo replay across a fork',
      () {
        final owner = _newGame(3);
        // Move J hearts onto Q hearts. The next command moves the pair.
        expect(owner.tableau[1].last.id, 10);
        expect(owner.tableau[5].last.id, 11);
        expect(owner.moveStackToTableau([owner.tableau[1].last], 5), isTrue);
        expect(owner.score, 8);
        expect(owner.tableau[1].single.isFaceUp, isTrue);
        final checkpoint = owner.snapshot();
        final wire = checkpoint.encode();
        final friend = KlondikeGame.fromSnapshot(BoardSnapshot.decode(wire));
        expect(friend.canUndo, isFalse);
        expect(owner.canUndo, isTrue);
        expect(
          identical(owner.tableau[1].last, friend.tableau[1].last),
          isFalse,
        );

        List<WireMap> continuePlay(KlondikeGame game) {
          final stages = <WireMap>[];
          final column = game.tableau[5];
          final stack = column.sublist(column.length - 2);
          expect(stack.map((c) => c.id), [11, 10]);
          expect(game.moveStackToTableau(stack, 4), isTrue);
          expect(game.tableau[4].last.id, 10);
          expect(game.score, 16);
          stages.add(_wire(game));

          final ace = game.tableau[2].last;
          expect((ace.suit, ace.rank), (Suit.clubs, 1));
          expect(game.moveCardToFoundation(ace, 2), isTrue);
          expect(game.foundationTop(2)!.id, ace.id);
          expect(game.tableau[2].last.isFaceUp, isTrue);
          expect(game.score, 31);
          stages.add(_wire(game));

          game.drawFromStock();
          stages.add(_wire(game));
          final plan = game.planMagicWand()!;
          expect(game.executeMagicWand(plan), isTrue);
          expect(game.moves, 5);
          expect(game.wandCount, 2);
          stages.add(_wire(game));
          expect(game.undo(), isTrue);
          expect(_wire(game), stages[2]);
          return stages;
        }

        final fromFriend = continuePlay(friend);
        expect(owner.snapshot().encode(), wire);
        expect(checkpoint.encode(), wire);
        expect(continuePlay(owner), fromFriend);
        expect(_wire(friend), _wire(owner));
      },
    );
  });

  group('v1 snapshot import', () {
    test(
      'restoring on an existing game drops only its previous undo history',
      () {
        final target = _newGame(3)..drawFromStock();
        final source = _newGame(1)..drawFromStock();
        final wire = _wire(source);
        var notifications = 0;
        target.addListener(() => notifications++);
        target.restoreBoard(BoardSnapshot.fromJson(wire));

        expect(notifications, 1);
        expect(target.deal.toJson(), source.deal.toJson());
        expect(target.undo(), isFalse);
        expect(target.snapshot().toJson(), wire);
        target.drawFromStock();
        expect(target.undo(), isTrue);
        expect(target.snapshot().toJson(), wire);
        expect(target.undo(), isFalse);
        expect(source.undo(), isTrue);
        expect(target.moves, 1);
      },
    );

    test('mutating decoded JSON cannot mutate the imported snapshot', () {
      final source = _newGame(3)..drawFromStock();
      final wire = _wire(source);
      final snapshot = BoardSnapshot.fromJson(wire);
      wire['stock'][0]['id'] = -1;
      wire['tableau'][2].clear();
      expect(snapshot.encode(), source.snapshot().encode());
    });

    test('relaxed columns accept a non-king, including after restore', () {
      final wire = _wire(_newGame(3));
      // Put col 0's 6 of spades in the waste, leaving an empty column.
      wire['waste'].add(wire['tableau'][0].removeLast());
      final game = KlondikeGame.fromSnapshot(BoardSnapshot.fromJson(wire));
      expect(game.wasteTop!.rank, 6);
      expect(game.moveStackToTableau([game.wasteTop!], 0), isTrue);
      expect(game.tableau[0].single.rank, 6);
      expect(game.moves, 1);
      expect(game.undo(), isTrue);
      expect(game.snapshot().toJson(), wire);
    });

    test('accepts visible rank gaps left by interior wand extraction', () {
      final wire = _wire(_newGame(1));
      // K clubs, 10 clubs. A visible run may have lost interior cards.
      wire['tableau'][1][0]['up'] = true;
      expect(BoardSnapshot.fromJson(wire).toJson(), wire);
    });

    test('restore a late board and play its winning move independently', () {
      final wire = _wire(_newGame(1));
      // Four suit-specific runs. The last black king is in the waste.
      wire['tableau'] = List.generate(7, (_) => <Object>[]);
      wire['stock'] = [];
      wire['waste'] = [
        {'id': 51, 'up': true},
      ];
      wire['foundations'] = [
        for (var suit = 0; suit < 4; suit++)
          [
            for (var rank = 0; rank < (suit == 3 ? 12 : 13); rank++)
              {'id': suit * 13 + rank, 'up': true},
          ],
      ];
      wire['moves'] = 107;
      final copy = KlondikeGame.fromSnapshot(BoardSnapshot.fromJson(wire));
      expect(copy.isWon, isFalse);
      expect(copy.moveCardToFoundation(copy.wasteTop!, 3), isTrue);
      expect(copy.isWon, isTrue);
      expect(copy.snapshot().foundations, everyElement(hasLength(13)));
      expect(copy.moves, 108);
      expect(copy.wasteTop, isNull);
      expect(copy.undo(), isTrue);
      expect(copy.isWon, isFalse);
      expect(copy.snapshot().toJson(), wire);
    });

    final corruptions = <String, void Function(WireMap)>{
      'unknown snapshot version': (m) => m['version'] = 2,
      'unknown generator version': (m) => m['deal']['version'] = 2,
      'unknown game rules': (m) => m['deal']['rules'] = 'strict-draw3',
      'zero seed': (m) => m['deal']['seed'] = 0,
      'out of range seed': (m) => m['deal']['seed'] = 2147483647,
      'missing state field': (m) => m.remove('score'),
      'unknown snapshot field': (m) => m['history'] = [],
      'unknown deal field': (m) => m['deal']['extra'] = false,
      'unknown card field': (m) => m['stock'][0]['extra'] = null,
      'duplicate and missing card': (m) => m['stock'][0] = m['stock'][1],
      'short deck': (m) => m['stock'].removeLast(),
      'unknown card identity': (m) => m['stock'][0]['id'] = 52,
      'untyped face': (m) => m['stock'][0]['up'] = 1,
      'exposed stock': (m) => m['stock'][0]['up'] = true,
      'hidden waste': (m) => m['waste'].add(m['stock'].removeLast()),
      'hidden card above exposed card': (m) => m['tableau'][2][0]['up'] = true,
      'wrong tableau count': (m) => m['tableau'].add([]),
      'wrong foundation count': (m) => m['foundations'].removeLast(),
      'wrong foundation suit': (m) {
        final aceOfHearts = m['tableau'][2].removeAt(1);
        aceOfHearts['up'] = true;
        m['foundations'][1].add(aceOfHearts);
      },
      'foundation skipping ace': (m) {
        m['foundations'][1].add(m['tableau'][0].removeLast()); // 2 diamonds
      },
      'hidden foundation card': (m) {
        final hiddenAce = m['tableau'][2].removeAt(1);
        m['foundations'][0].add(hiddenAce);
      },
      'negative move count': (m) => m['moves'] = -1,
      'fractional score': (m) => m['score'] = 2.5,
      'bad power-up counter': (m) => m['freezeCount'] = '1',
      'wand count outside wire range': (m) => m['wandCount'] = 2147483648,
      'negative freeze charges': (m) => m['freezeCount'] = -1,
    };
    for (final bad in corruptions.entries) {
      test('rejects ${bad.key} before touching a running game', () {
        final target = _newGame(3)..drawFromStock();
        final before = target.snapshot().encode();
        var notifications = 0;
        target.addListener(() => notifications++);
        final malformed = _wire(_newGame(1));
        bad.value(malformed);
        expect(
          () => target.restoreBoard(BoardSnapshot.fromJson(malformed)),
          throwsFormatException,
        );
        expect(target.snapshot().encode(), before);
        expect(target.canUndo, isTrue);
        expect(notifications, 0);
      });
    }

    test('whole-valued JSON numbers normalize equally on mobile and web', () {
      final game = _newGame(1);
      final wire = _wire(game);
      wire['version'] = 1.0;
      wire['deal']['version'] = 1.0;
      wire['deal']['seed'] = 1.0;
      wire['score'] = 0.0;
      expect(BoardSnapshot.fromJson(wire).encode(), game.snapshot().encode());
    });

    test('malformed JSON and unsupported root shapes fail cleanly', () {
      final oversized = ' ' * (BoardSnapshot.maxJsonLength + 1);
      for (final text in ['{', 'null', '42', '[]', '{}', oversized]) {
        expect(() => BoardSnapshot.decode(text), throwsFormatException);
      }
    });
  });
}
