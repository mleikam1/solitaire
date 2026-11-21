import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solitaire/appearance/appearance.dart';
import 'package:solitaire/game/board_snapshot.dart';
import 'package:solitaire/game/deal_spec.dart';
import 'package:solitaire/game/klondike_game.dart';
import 'package:solitaire/models/card_model.dart';
import 'package:solitaire/pages/solitaire_game_page.dart';
import 'package:solitaire/widgets/card_widget.dart';

/// Build a legal descending run over a concealed ace, keeping all 52 cards.
KlondikeGame preparedDeal() {
  final deal = DealSpec(seed: 1);
  final deck = deal.shuffledDeck();
  PlayingCard take(int rank, Suit suit, {bool faceUp = true}) {
    final index = deck.indexWhere(
      (card) => card.rank == rank && card.suit == suit,
    );
    return deck.removeAt(index)..isFaceUp = faceUp;
  }

  final columns = [
    [
      take(1, Suit.hearts, faceUp: false),
      take(6, Suit.spades),
      take(5, Suit.diamonds),
    ],
    [take(7, Suit.hearts)],
    [take(6, Suit.clubs)],
    [take(6, Suit.diamonds)],
    [take(5, Suit.spades)],
    [take(9, Suit.diamonds)],
    [take(9, Suit.spades)],
  ];
  for (var i = 0; deck.length > 24; i++) {
    columns[2 + i % 5].insert(0, deck.removeLast());
  }
  return KlondikeGame.fromSnapshot(
    BoardSnapshot.capture(
      deal: deal,
      stock: deck,
      waste: [],
      foundations: List.generate(4, (_) => <PlayingCard>[]),
      tableau: columns,
      score: 0,
      moves: 0,
      freezeCount: deal.initialFreezeCount,
      wandCount: deal.initialWandCount,
    ),
  );
}

Future<KlondikeGame> openBoard(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 568);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final appearance = await AppearanceController.load();
  await appearance.setDeck(DeckStyle.koiKingdom);
  final game = preparedDeal();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: appearance,
      child: MaterialApp(home: SolitaireGamePage(createGame: () => game)),
    ),
  );
  await tester.pumpAndSettle();
  return game;
}

Finder cardWidgets(int id) =>
    find.byWidgetPredicate((w) => w is CardWidget && w.card.id == id);

String assetOf(WidgetTester tester, Finder card) {
  final image = tester.widget<Image>(
    find.descendant(of: card, matching: find.byType(Image)),
  );
  final provider = image.image;
  final source = provider is ResizeImage ? provider.imageProvider : provider;
  return (source as AssetImage).assetName;
}

void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);
  testWidgets(
    'the original drawn rank fits in the exposed strip at phone and tablet sizes',
    (tester) async {
      final game = await openBoard(tester);
      final page = tester.element(find.byType(SolitaireGamePage));
      await page.read<AppearanceController>().setDeck(
        DeckStyle.originalClassic,
      );
      for (final size in [
        const Size(320, 568),
        const Size(390, 844),
        const Size(820, 1180),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        final six = cardWidgets(game.tableau[0][1].id);
        final five = cardWidgets(game.tableau[0][2].id);
        final rank = find.descendant(of: six, matching: find.text('6'));
        expect(
          tester.getBottomRight(rank).dy,
          lessThanOrEqualTo(tester.getTopLeft(five).dy),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets(
    'narrow board renders both the moving run and its ghosts, then accepts a drop and undo',
    (tester) async {
      final game = await openBoard(tester);
      final six = game.tableau[0][1];
      final five = game.tableau[0][2];
      final seven = game.tableau[1].single;
      final before = game.moves;
      final sixRect = tester.getRect(cardWidgets(six.id));
      final fiveRect = tester.getRect(cardWidgets(five.id));
      expect(sixRect.width / sixRect.height, closeTo(5 / 7, 0.001));
      expect(fiveRect.top - sixRect.top, greaterThan(sixRect.height * 0.25));

      final start = sixRect.topLeft + const Offset(7, 7);
      final drag = await tester.startGesture(start);
      await drag.moveBy(const Offset(30, 4));
      await tester.pump();
      for (final card in [six, five]) {
        final drawn = cardWidgets(card.id);
        expect(drawn, findsNWidgets(2));
        for (var i = 0; i < 2; i++) {
          expect(
            assetOf(tester, drawn.at(i)),
            DeckStyle.koiKingdom.faceAsset(card),
          );
        }
        expect(
          find.ancestor(
            of: drawn,
            matching: find.byWidgetPredicate(
              (w) => w is Opacity && w.opacity == 0.7,
            ),
          ),
          findsOneWidget,
        );
      }
      await drag.moveTo(tester.getCenter(cardWidgets(seven.id)));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(game.moves, before + 1);
      expect(game.tableau[1].map((c) => c.id), [seven.id, six.id, five.id]);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(game.moves, before);
      expect(game.tableau[0].skip(1).map((c) => c.id), [six.id, five.id]);
      expect(game.tableau[0].first.isFaceUp, isFalse);
      expect(cardWidgets(six.id), findsOneWidget);

      // A rejected drag must also remove feedback and leave the run interactive.
      await tester.dragFrom(start, const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(cardWidgets(six.id), findsOneWidget);
      expect(
        find.ancestor(
          of: cardWidgets(six.id),
          matching: find.byType(Draggable<List<PlayingCard>>),
        ),
        findsOneWidget,
      );
      expect(game.moves, before);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets(
    'dropping the five of spades rejects the six of clubs and accepts the six of diamonds',
    (tester) async {
      final game = await openBoard(tester);
      final five = game.tableau[4].last;
      final clubs = game.tableau[2].last;
      final diamonds = game.tableau[3].last;
      final original = game.snapshot().encode();

      Future<void> dropOn(PlayingCard target) async {
        // Grab at the left edge and release at the right. The pointer still
        // targets this pile even if the feedback card overlaps its neighbor.
        final from =
            tester.getRect(cardWidgets(five.id)).centerLeft +
            const Offset(3, 0);
        final to =
            tester.getRect(cardWidgets(target.id)).centerRight -
            const Offset(3, 0);
        final drag = await tester.startGesture(from);
        await drag.moveBy(const Offset(0, -25));
        await tester.pump();
        await drag.moveTo(to);
        await tester.pump();
        await drag.up();
        await tester.pumpAndSettle();
      }

      await dropOn(clubs);
      expect(game.snapshot().encode(), original);
      expect(game.canUndo, isFalse);

      await dropOn(diamonds);
      expect(game.tableau[3].last, same(five));
      expect(game.moves, 1);
      expect(game.canUndo, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets(
    'Wand moves the hidden card back frame by frame and reveals its face on the foundation',
    (tester) async {
      final game = await openBoard(tester);
      final ace = game.tableau.first.first;
      final wandCount = game.wandCount;
      final plan = game.planMagicWand()!.actions.single;
      expect(plan.cards.single, same(ace));
      expect(plan.revealOnPickup, isTrue);
      expect(
        assetOf(tester, cardWidgets(ace.id)),
        DeckStyle.koiKingdom.backAsset,
      );

      await tester.tap(find.byTooltip('Wand'));
      await tester.pump();
      final flight = find.byWidgetPredicate(
        (w) =>
            w is CardWidget && w.card.id == ace.id && !identical(w.card, ace),
      );
      expect(flight, findsOneWidget);
      expect(assetOf(tester, flight), DeckStyle.koiKingdom.backAsset);
      final start = tester.getTopLeft(flight);
      await tester.pump(const Duration(milliseconds: 150));
      final middle = tester.getTopLeft(flight);
      expect((middle - start).distance, greaterThan(8));
      expect(assetOf(tester, flight), DeckStyle.koiKingdom.backAsset);
      expect(ace.isFaceUp, isFalse);
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(flight, findsNothing);
      expect(game.foundationTop(plan.to!.index), same(ace));
      expect(ace.isFaceUp, isTrue);
      expect(
        assetOf(tester, cardWidgets(ace.id)),
        DeckStyle.koiKingdom.faceAsset(ace),
      );
      expect(game.wandCount, wandCount - 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );
}
