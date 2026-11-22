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
import 'package:solitaire/widgets/card_flight.dart';
import 'package:solitaire/widgets/card_widget.dart';
import 'package:solitaire/widgets/wand_reveal_flight.dart';

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
      final original = game.snapshot().encode();
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
      final released = tester.getTopLeft(cardWidgets(six.id).last);
      await drag.up();
      await tester.pump();
      final flight = find.byType(CardFlight);
      final flyingSix = find.descendant(
        of: flight,
        matching: cardWidgets(six.id),
      );
      final flyingFive = find.descendant(
        of: flight,
        matching: cardWidgets(five.id),
      );
      expect((tester.getTopLeft(flyingSix) - released).distance, lessThan(1));
      expect(
        (tester.getTopLeft(flyingFive) - tester.getTopLeft(flyingSix)).dy,
        closeTo(fiveRect.top - sixRect.top, 1),
      );
      await tester.pumpAndSettle();
      expect(game.moves, before + 1);
      expect(game.tableau[1].map((c) => c.id), [seven.id, six.id, five.id]);
      final dropped = tester.getRect(cardWidgets(six.id));
      final revealedAce = game.tableau[0].single;
      final aceFlip = find.descendant(
        of: flight,
        matching: cardWidgets(revealedAce.id),
      );
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(game.snapshot().encode(), original);
      expect(
        assetOf(tester, aceFlip),
        DeckStyle.koiKingdom.faceAsset(revealedAce),
      );
      expect(tester.getRect(flyingSix), rectMoreOrLessEquals(dropped));
      expect(
        tester.getTopLeft(flyingFive).dy - tester.getTopLeft(flyingSix).dy,
        closeTo(fiveRect.top - sixRect.top, 1),
      );
      expect(assetOf(tester, flyingFive), DeckStyle.koiKingdom.faceAsset(five));
      await tester.pump(CardFlight.moveDuration * 0.45);
      expect(
        tester.getCenter(flyingSix).dx,
        inExclusiveRange(sixRect.center.dx, dropped.center.dx),
      );
      await tester.pump(CardFlight.drawDuration * 0.25);
      expect(assetOf(tester, aceFlip), DeckStyle.koiKingdom.backAsset);
      await tester.pumpAndSettle();
      expect(flight, findsNothing);
      expect(
        tester.getRect(cardWidgets(six.id)),
        rectMoreOrLessEquals(sixRect),
      );
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

      Future<void> dropOn(PlayingCard target, {bool cancel = false}) async {
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
        if (cancel) {
          await drag.cancel();
        } else {
          await drag.up();
        }
        await tester.pump();
      }

      await dropOn(clubs);
      expect(find.byType(CardFlight), findsNothing);
      expect(game.snapshot().encode(), original);
      expect(game.canUndo, isFalse);

      await dropOn(diamonds, cancel: true);
      expect(find.byType(CardFlight), findsNothing);
      expect(game.snapshot().encode(), original);

      await dropOn(diamonds);
      expect(find.byType(CardFlight), findsOneWidget);
      await tester.pumpAndSettle();
      expect(game.tableau[3].last, same(five));
      expect(game.moves, 1);
      expect(game.canUndo, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets(
    'tapping a run flies both cards to the tableau, then the exposed ace flies to its foundation',
    (tester) async {
      final game = await openBoard(tester);
      final ace = game.tableau[0].first;
      final six = game.tableau[0][1];
      final five = game.tableau[0].last;
      final source = tester.getRect(cardWidgets(six.id));
      // The five covers the lower part of the six.
      await tester.tapAt(source.topLeft + const Offset(7, 7));
      await tester.pump();
      final flight = find.byType(CardFlight);
      final flyingSix = find.descendant(
        of: flight,
        matching: cardWidgets(six.id),
      );
      final flyingFive = find.descendant(
        of: flight,
        matching: cardWidgets(five.id),
      );
      expect(tester.getRect(flyingSix), rectMoreOrLessEquals(source));
      expect(cardWidgets(six.id), findsOneWidget);
      expect(cardWidgets(five.id), findsOneWidget);
      expect(assetOf(tester, flyingFive), DeckStyle.koiKingdom.faceAsset(five));
      expect(game.tableau[1].last, same(five));
      await tester.pump(CardFlight.moveDuration * 0.45);
      final midair = tester.getCenter(flyingSix);
      expect((midair - source.center).distance, greaterThan(5));
      await tester.pump(CardFlight.moveDuration * 0.43);
      final landing = tester.getRect(flyingSix);
      await tester.pumpAndSettle();
      final destination = tester.getRect(cardWidgets(six.id));
      expect((midair - destination.center).distance, greaterThan(1));
      expect(
        (landing.center - destination.center).distance,
        lessThan(source.height / 5),
      );
      // The landing has its own scale accent before the card lies flat.
      expect(
        (landing.width - destination.width).abs() +
            (landing.height - destination.height).abs(),
        greaterThan(0.1),
      );

      final beforeFoundation = game.snapshot().encode();
      final aceSource = tester.getCenter(cardWidgets(ace.id));
      await tester.tap(cardWidgets(ace.id));
      await tester.pump();
      final flyingAce = find.descendant(
        of: flight,
        matching: cardWidgets(ace.id),
      );
      expect(tester.getCenter(flyingAce), offsetMoreOrLessEquals(aceSource));
      await tester.pump(CardFlight.moveDuration * 0.4);
      expect(tester.getCenter(flyingAce).dy, lessThan(aceSource.dy));
      await tester.pumpAndSettle();
      expect(flight, findsNothing);
      expect(game.foundationTop(0), same(ace));
      expect(cardWidgets(ace.id), findsOneWidget);
      expect(game.moves, 2);

      final foundation = tester.getCenter(cardWidgets(ace.id));
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(game.snapshot().encode(), beforeFoundation);
      expect(tester.getCenter(flyingAce), offsetMoreOrLessEquals(foundation));
      await tester.pump(CardFlight.moveDuration * 0.45);
      expect(
        tester.getCenter(flyingAce).dy,
        inExclusiveRange(foundation.dy, aceSource.dy),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(cardWidgets(ace.id)),
        offsetMoreOrLessEquals(aceSource),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets(
    'stock draw and Undo fly in opposite directions and show opposite card sides',
    (tester) async {
      final game = await openBoard(tester);
      final original = game.snapshot().encode();
      final drawn = game.stockTop!;
      final source = tester.getRect(cardWidgets(drawn.id));
      await tester.tapAt(source.center);
      await tester.pump();
      final flight = find.byType(CardFlight);
      final flyingCard = find.descendant(
        of: flight,
        matching: cardWidgets(drawn.id),
      );
      expect(tester.getRect(flyingCard), rectMoreOrLessEquals(source));
      expect(cardWidgets(drawn.id), findsOneWidget);
      expect(assetOf(tester, flyingCard), DeckStyle.koiKingdom.backAsset);
      expect(game.wasteTop, same(drawn));
      expect(game.moves, 1);
      await tester.pump(CardFlight.drawDuration * 0.35);
      final turning = tester.getRect(flyingCard);
      expect(turning.width.abs(), lessThan(source.width * 0.65));
      expect(turning.center.dx, greaterThan(source.center.dx));
      await tester.pump(CardFlight.drawDuration * 0.30);
      expect(
        assetOf(tester, flyingCard),
        DeckStyle.koiKingdom.faceAsset(drawn),
      );
      await tester.pumpAndSettle();
      expect(flight, findsNothing);
      expect(cardWidgets(drawn.id), findsOneWidget);
      expect(
        tester.getCenter(cardWidgets(drawn.id)).dx,
        greaterThan(turning.center.dx),
      );
      expect(game.moves, 1);

      final waste = tester.getRect(cardWidgets(drawn.id));
      final underneath = game.stockTop!;
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(game.snapshot().encode(), original);
      expect(tester.getRect(flyingCard), rectMoreOrLessEquals(waste));
      expect(cardWidgets(drawn.id), findsOneWidget);
      expect(
        tester.getRect(cardWidgets(underneath.id)),
        rectMoreOrLessEquals(source),
      );
      expect(
        assetOf(tester, cardWidgets(underneath.id)),
        DeckStyle.koiKingdom.backAsset,
      );
      expect(
        assetOf(tester, flyingCard),
        DeckStyle.koiKingdom.faceAsset(drawn),
      );
      await tester.pump(CardFlight.drawDuration * 0.35);
      final returning = tester.getRect(flyingCard);
      expect(
        returning.center.dx,
        inExclusiveRange(source.center.dx, waste.center.dx),
      );
      expect(returning.width.abs(), lessThan(waste.width * 0.65));
      await tester.pump(CardFlight.drawDuration * 0.30);
      expect(assetOf(tester, flyingCard), DeckStyle.koiKingdom.backAsset);
      await tester.pumpAndSettle();
      expect(flight, findsNothing);
      expect(
        tester.getRect(cardWidgets(drawn.id)),
        rectMoreOrLessEquals(source),
      );
      expect(
        assetOf(tester, cardWidgets(drawn.id)),
        DeckStyle.koiKingdom.backAsset,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets(
    'rapid draws and repeated Undo replace flights; confirmed New Deal cancels the current flight',
    (tester) async {
      final game = await openBoard(tester);
      final original = game.snapshot().encode();
      final stock = tester.getCenter(cardWidgets(game.stockTop!.id));
      final flight = find.byType(CardFlight);
      await tester.tapAt(stock);
      await tester.pump();
      await tester.pump(CardFlight.drawDuration * 0.25);
      final firstDraw = game.snapshot().encode();
      final first = game.wasteTop!;
      final second = game.stockTop!;
      await tester.tapAt(stock);
      await tester.pump();
      expect(game.moves, 2);
      expect(flight, findsOneWidget);
      expect(
        find.descendant(of: flight, matching: cardWidgets(second.id)),
        findsOneWidget,
      );
      expect(
        assetOf(tester, cardWidgets(first.id)),
        DeckStyle.koiKingdom.faceAsset(first),
      );
      final inFlight = find.descendant(
        of: flight,
        matching: cardWidgets(second.id),
      );
      await tester.pump(CardFlight.drawDuration * 0.35);
      final interrupted = tester.getCenter(inFlight);
      expect(assetOf(tester, inFlight), DeckStyle.koiKingdom.backAsset);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(game.snapshot().encode(), firstDraw);
      expect((tester.getCenter(inFlight) - interrupted).distance, lessThan(2));
      expect(assetOf(tester, inFlight), DeckStyle.koiKingdom.backAsset);
      await tester.pump(CardFlight.drawDuration * 0.25);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(game.snapshot().encode(), original);
      expect(
        find.descendant(of: flight, matching: cardWidgets(first.id)),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(game.snapshot().encode(), original);
      expect(flight, findsNothing);

      await tester.tapAt(stock);
      await tester.pump();
      expect(flight, findsOneWidget);
      await tester.tap(find.byTooltip('New Deal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(game.moves, 1);
      expect(flight, findsOneWidget);
      await tester.tap(find.text('Yes'));
      await tester.pump();
      expect(flight, findsNothing);
      final newDeal = game.snapshot().encode();
      await tester.pump(CardFlight.drawDuration * 2);
      expect(game.snapshot().encode(), newDeal);
      expect(game.moves, 0);
      expect(game.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets(
    'leaving the app mid-Undo keeps the restored board playable on resume',
    (tester) async {
      final game = await openBoard(tester);
      final original = game.snapshot().encode();
      final stock = tester.getCenter(cardWidgets(game.stockTop!.id));
      await tester.tapAt(stock);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      final flight = find.byType(CardFlight);
      expect(flight, findsOneWidget);
      await tester.pump(CardFlight.drawDuration * 0.25);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(flight, findsNothing);
      expect(game.snapshot().encode(), original);
      await tester.tapAt(stock);
      await tester.pumpAndSettle();
      expect(game.moves, 1);
      expect(game.wasteTop, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets(
    'reduced motion skips Undo travel; undoing a recycle restores the waste in order',
    (tester) async {
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);
      final game = await openBoard(tester);
      final five = game.tableau[4].last;
      await tester.tap(cardWidgets(five.id));
      await tester.pump();
      expect(find.byType(CardFlight), findsNothing);
      expect(game.tableau[3].last, same(five));
      final beforeDraw = game.snapshot().encode();
      final drawn = game.stockTop!;
      final stock = tester.getCenter(cardWidgets(drawn.id));
      await tester.tapAt(stock);
      await tester.pump();
      expect(find.byType(CardFlight), findsNothing);
      expect(
        assetOf(tester, cardWidgets(drawn.id)),
        DeckStyle.koiKingdom.faceAsset(drawn),
      );

      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(find.byType(CardFlight), findsNothing);
      expect(game.snapshot().encode(), beforeDraw);

      dispatcher.clearAccessibilityFeaturesTestValue();
      while (game.stockTop != null) {
        game.drawFromStock();
      }
      await tester.pump();
      final moves = game.moves;
      final beforeRecycle = game.snapshot().encode();
      final wasteTop = game.wasteTop!;
      final waste = tester.getCenter(cardWidgets(wasteTop.id));
      await tester.tapAt(stock);
      await tester.pump();
      expect(find.byType(CardFlight), findsNothing);
      expect(game.stockTop!.id, drawn.id);
      expect(game.wasteTop, isNull);
      expect(game.moves, moves + 1);

      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      final flight = find.byType(CardFlight);
      final packet = find.descendant(
        of: flight,
        matching: find.byType(CardWidget),
      );
      expect(packet, findsWidgets);
      expect(assetOf(tester, packet.last), DeckStyle.koiKingdom.backAsset);
      expect((tester.getCenter(packet.last) - stock).distance, lessThan(5));
      await tester.pump(CardFlight.drawDuration * 0.65);
      final topInFlight = find.descendant(
        of: flight,
        matching: cardWidgets(wasteTop.id),
      );
      expect(
        assetOf(tester, topInFlight),
        DeckStyle.koiKingdom.faceAsset(wasteTop),
      );
      await tester.pumpAndSettle();
      expect(flight, findsNothing);
      expect(game.snapshot().encode(), beforeRecycle);
      expect(
        tester.getCenter(cardWidgets(wasteTop.id)),
        offsetMoreOrLessEquals(waste),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets(
    'Undo during a Wand flight cancels the Wand and returns the previous draw',
    (tester) async {
      final game = await openBoard(tester);
      final original = game.snapshot().encode();
      await tester.tap(cardWidgets(game.stockTop!.id));
      await tester.pumpAndSettle();

      final moving = game.planMagicWand()!.actions.single.cards.single;
      await tester.tap(find.byTooltip('Wand'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 95));
      // Its source is covered while the flying copy is visible.
      expect(cardWidgets(moving.id), findsOneWidget);
      expect(find.byType(WandRevealFlight), findsOneWidget);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      await tester.pump();
      expect(cardWidgets(moving.id), findsOneWidget);
      expect(find.byType(CardFlight), findsOneWidget);
      expect(game.snapshot().encode(), original);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.byType(CardFlight), findsNothing);
      expect(game.snapshot().encode(), original);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets(
    'leaving a Wand reveal for Settings or the background cancels the unspent move',
    (tester) async {
      final game = await openBoard(tester);
      final original = game.snapshot().encode();
      Future<void> reveal() async {
        await tester.tap(find.byTooltip('Wand'));
        await tester.pump();
        await tester.pump(WandRevealFlight.duration * 0.55);
        expect(find.byType(WandRevealFlight), findsOneWidget);
      }

      await reveal();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(WandRevealFlight), findsNothing);
      expect(game.snapshot().encode(), original);
      await tester.tap(find.byTooltip('Close Settings'));
      await tester.pumpAndSettle();
      await reveal();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(WandRevealFlight), findsNothing);
      expect(game.snapshot().encode(), original);
      await reveal();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(WandRevealFlight.duration);
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  testWidgets(
    'reduced motion applies a Wand immediately and preserves Undo',
    (tester) async {
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);
      final game = await openBoard(tester);
      final original = game.snapshot().encode();
      final action = game.planMagicWand()!.actions.single;
      await tester.tap(find.byTooltip('Wand'));
      await tester.pump();
      expect(find.byType(WandRevealFlight), findsNothing);
      expect(game.foundationTop(action.to!.index), same(action.cards.single));
      expect(game.wandCount, 2);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(game.snapshot().encode(), original);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets(
    'Wand lifts, reveals and holds the selected ace before landing; Undo conceals it',
    (tester) async {
      final game = await openBoard(tester);
      final original = game.snapshot().encode();
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
      await tester.pump(const Duration(milliseconds: 350));
      final held = tester.getRect(flight);
      expect(held.width, greaterThan(55));
      expect(assetOf(tester, flight), DeckStyle.koiKingdom.faceAsset(ace));
      // Only the flying copy turns. The real deal and all other backs stay put.
      expect(game.snapshot().encode(), original);
      for (final widget in tester.widgetList<CardWidget>(
        find.byType(CardWidget),
      )) {
        if (widget.card.id != ace.id && !widget.card.isFaceUp) {
          expect(
            assetOf(tester, cardWidgets(widget.card.id)),
            DeckStyle.koiKingdom.backAsset,
          );
        }
      }
      await tester.pump(const Duration(milliseconds: 110));
      expect(tester.getRect(flight), held);
      await tester.pump(const Duration(milliseconds: 200));
      final traveling = tester.getCenter(flight);
      final preview = tester.widget<WandRevealFlight>(
        find.byType(WandRevealFlight),
      );
      final destination =
          tester.getTopLeft(find.byType(WandRevealFlight)) +
          preview.end +
          preview.cardSize.center(Offset.zero);
      expect(
        (traveling - destination).distance,
        lessThan((held.center - destination).distance),
      );
      await tester.pumpAndSettle();
      expect(flight, findsNothing);
      expect(game.foundationTop(plan.to!.index), same(ace));
      expect(ace.isFaceUp, isTrue);
      expect(
        assetOf(tester, cardWidgets(ace.id)),
        DeckStyle.koiKingdom.faceAsset(ace),
      );
      expect(game.wandCount, wandCount - 1);
      final foundation = tester.getCenter(cardWidgets(ace.id));

      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      final returning = find.descendant(
        of: find.byType(CardFlight),
        matching: cardWidgets(ace.id),
      );
      expect(tester.getCenter(returning), offsetMoreOrLessEquals(foundation));
      expect(assetOf(tester, returning), DeckStyle.koiKingdom.faceAsset(ace));
      await tester.pump(CardFlight.drawDuration * 0.65);
      expect(assetOf(tester, returning), DeckStyle.koiKingdom.backAsset);
      await tester.pumpAndSettle();
      expect(game.snapshot().encode(), original);
      expect(
        assetOf(tester, cardWidgets(ace.id)),
        DeckStyle.koiKingdom.backAsset,
      );
      expect(game.wandCount, wandCount);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );
}
