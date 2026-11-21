import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solitaire/appearance/appearance.dart';
import 'package:solitaire/models/card_model.dart';
import 'package:solitaire/widgets/card_widget.dart';
import 'package:solitaire/widgets/victory_celebration.dart';

Future<List<Rect>> showWin(
  WidgetTester tester, {
  required Size size,
  bool reduceMotion = false,
  double textScale = 1,
  VoidCallback? newDeal,
  VoidCallback? undo,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final width = size.width / 8;
  final foundations = List.generate(
    4,
    (suit) =>
        Rect.fromLTWH(size.width * .46 + suit * width, 72, width, width * 1.5),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: VictoryCelebration(
            deck: DeckStyle.koiKingdom,
            foundations: foundations,
            score: 641,
            moves: 91,
            elapsed: '03:27',
            onNewDeal: newDeal ?? () {},
            onUndo: undo,
          ),
        ),
      ),
    ),
  );
  return foundations;
}

void main() {
  testWidgets('all 52 selected faces leave the four actual piles in order', (
    tester,
  ) async {
    final rects = await showWin(tester, size: const Size(320, 568));
    final cards = find.byType(CardWidget);
    expect(cards, findsNWidgets(4));
    for (int suit = 0; suit < 4; suit++) {
      expect(tester.getRect(cards.at(suit)), rects[suit]);
      final king = tester.widget<CardWidget>(cards.at(suit)).card;
      expect((king.suit, king.rank), (Suit.values[suit], 13));
    }
    final launched = {for (final suit in Suit.values) suit: <int>{}};
    for (int frame = 0; frame < 36; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      final inFlight = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is Positioned && w.key is ValueKey<(int, int)>,
        ),
        matching: cards,
      );
      for (final face in tester.widgetList<CardWidget>(inFlight)) {
        expect(face.deck, DeckStyle.koiKingdom);
        expect(face.card.isFaceUp, isTrue);
        launched[face.card.suit]!.add(face.card.rank);
      }
    }
    for (final ranks in launched.values) {
      expect(ranks, orderedEquals(List.generate(13, (i) => 13 - i)));
    }
    expect(cards, findsNothing);
    expect(find.text('Congratulations!'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 568), const Size(768, 1024)]) {
    testWidgets('reduced-motion victory and both actions at ${size.width}', (
      tester,
    ) async {
      var newDeals = 0;
      var undos = 0;
      final rects = await showWin(
        tester,
        size: size,
        reduceMotion: true,
        textScale: 2,
        newDeal: () => newDeals++,
        undo: () => undos++,
      );
      final cards = find.byType(CardWidget);
      for (final elapsed in [Duration.zero, const Duration(seconds: 2)]) {
        await tester.pump(elapsed);
        expect(cards, findsNWidgets(4));
        for (int i = 0; i < 4; i++) {
          expect(tester.getRect(cards.at(i)), rects[i]);
        }
      }
      expect(find.text('Congratulations!'), findsOneWidget);
      expect(find.text('641'), findsOneWidget);
      expect(find.text('91'), findsOneWidget);
      expect(find.text('03:27'), findsOneWidget);
      for (final label in ['New deal', 'Undo']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect((newDeals, undos), (1, 1));
      expect(tester.takeException(), isNull);
    });
  }
}
