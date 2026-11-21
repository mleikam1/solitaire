import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solitaire/appearance/appearance.dart';
import 'package:solitaire/game/board_snapshot.dart';
import 'package:solitaire/game/klondike_game.dart';
import 'package:solitaire/pages/solitaire_game_page.dart';
import 'package:solitaire/widgets/card_flight.dart';
import 'package:solitaire/widgets/card_widget.dart';

import 'klondike_rules_test.dart'
    show position, clubs, hearts, spades, diamonds;

KlondikeGame chainDeal() => KlondikeGame.fromSnapshot(
  BoardSnapshot.fromJson(
    position(
      foundations: [
        [],
        [],
        [clubs(1)],
        [],
      ],
      columns: [
        [clubs(2)], [clubs(3)], [clubs(5), hearts(4)],
        // This ace cannot be exposed by direct collection.
        [hearts(1), hearts(2)],
      ],
      waste: [spades(1), clubs(4)],
      hidden: {hearts(1)},
    ),
  ),
);

KlondikeGame endgame() {
  List<int> run(int count, int Function(int) card) => [
    for (var rank = 1; rank <= count; rank++) card(rank),
  ];
  return KlondikeGame.fromSnapshot(
    BoardSnapshot.fromJson(
      position(
        foundations: [
          run(10, hearts),
          run(13, diamonds),
          run(12, clubs),
          run(12, spades),
        ],
        columns: [
          [spades(13), clubs(13)],
        ],
        hidden: {spades(13)},
        waste: [hearts(11), hearts(13), hearts(12)],
      ),
    ),
  );
}

Future<SolitaireGamePageState> openDeal(
  WidgetTester tester,
  KlondikeGame game, {
  bool chains = true,
  bool reducedMotion = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 568);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final controller = await AppearanceController.load();
  await controller.setAutoCollectFoundations(chains);
  await controller.setDeck(DeckStyle.originalClassic);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reducedMotion),
              child: child!,
            ),
        home: SolitaireGamePage(createGame: () => game),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<SolitaireGamePageState>(find.byType(SolitaireGamePage));
}

Finder card(int id) =>
    find.byWidgetPredicate((w) => w is CardWidget && w.card.id == id);

void main() {
  test(
    'incomplete plans leave the board, history, and inventory untouched',
    () {
      final game = chainDeal();
      final before = game.snapshot().encode();
      var events = 0;
      game.addListener(() => events++);
      expect(game.planAutoFinish(), isNull);
      expect(game.nextFoundationCard(2)!.id, clubs(2));
      expect(game.snapshot().encode(), before);
      expect(events, 0);
      expect(game.canUndo, isFalse);
    },
  );

  test(
    'the full route uses legal flips and a waste recycle and can be undone',
    () {
      final game = endgame();
      final original = game.snapshot().encode();
      final steps = game.planAutoFinish()!;
      expect(
        steps.where((step) => step.action == AutoFinishAction.draw),
        hasLength(3),
      );
      expect(
        steps.where((step) => step.action == AutoFinishAction.recycle),
        hasLength(1),
      );
      expect(game.snapshot().encode(), original);
      expect(game.tableau.first.first.isFaceUp, isFalse);
      expect(game.canUndo, isFalse);
      for (final step in steps) {
        expect(game.playAutoFinishStep(step), isTrue);
      }
      expect(game.isWon, isTrue);
      expect(game.moves, 9);
      expect(game.score, 55);
      expect(game.freezeCount, 2);
      expect(game.wandCount, 3);
      while (game.canUndo) {
        game.undo();
      }
      expect(game.snapshot().encode(), original);
      expect(game.playAutoFinishStep(steps.first), isFalse);
    },
  );

  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);
  testWidgets(
    'a foundation drop chains tableau and waste tops until blocked',
    (tester) async {
      final game = chainDeal();
      await openDeal(tester, game);
      final two = card(clubs(2));
      await tester.drag(
        two,
        tester.getCenter(card(clubs(1))) - tester.getCenter(two),
      );
      await tester.pumpAndSettle();
      expect(game.foundationTop(2)!.id, clubs(4));
      expect(game.wasteTop!.id, spades(1));
      expect(game.score, 30);
      expect(game.moves, 3);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(game.foundationTop(2)!.id, clubs(3));
      expect(game.wasteTop!.id, clubs(4));
      expect(game.moves, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets('disabling chains leaves the next exposed club available', (
    tester,
  ) async {
    final game = chainDeal();
    await openDeal(tester, game, chains: false);
    await tester.tap(card(clubs(2)));
    await tester.pumpAndSettle();
    expect(game.moves, 1);
    expect(game.nextFoundationCard(2)!.id, clubs(3));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: desktop);

  testWidgets(
    'automatic flights wait in background, resume, and stop on undo',
    (tester) async {
      final game = chainDeal();
      final page = await openDeal(tester, game);
      await tester.tap(card(clubs(2)));
      await tester.pump();
      page.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 2));
      expect(game.moves, 1);
      page.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(); // First tick of the flight queued after layout.
      await tester.pump(const Duration(milliseconds: 45));
      final flight = tester.widget<CardFlight>(find.byType(CardFlight));
      expect(flight.cards.single.id, clubs(3));
      expect(flight.progress, inExclusiveRange(0, 1));
      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(game.moves, 1);
      expect(game.foundationTop(2)!.id, clubs(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: desktop,
  );

  testWidgets('fast finish runs with chains off and reduced motion', (
    tester,
  ) async {
    final game = endgame();
    await openDeal(tester, game, chains: false, reducedMotion: true);
    await tester.tap(card(clubs(13)));
    await tester.pumpAndSettle();
    expect(game.isWon, isTrue);
    expect(game.moves, 9);
    expect(find.byType(CardFlight), findsNothing);
    expect(find.text('Congratulations!'), findsOneWidget);
    await tester.tap(find.text('New deal'));
    await tester.pumpAndSettle();
    expect(find.text('Congratulations!'), findsNothing);
    expect(game.isWon, isFalse);
    expect(game.moves, 0);
    expect(game.canUndo, isFalse);
    expect(find.text('Time: 00:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: desktop);
}
