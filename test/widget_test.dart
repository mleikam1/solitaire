import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solitaire/appearance/appearance.dart';
import 'package:solitaire/appearance/table_surface.dart';
import 'package:solitaire/main.dart';
import 'package:solitaire/pages/solitaire_game_page.dart';
import 'package:solitaire/widgets/bottom_toolbar.dart';
import 'package:solitaire/widgets/card_widget.dart';

void main() {
  testWidgets(
    'change appearance mid-deal and undo the preceding stock draw',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      final appearance = await AppearanceController.load();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: appearance,
          child: const SolitaireApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      final board = find.byType(SolitaireGamePage);
      final originalBoard = tester.state(board);
      final cards = find.descendant(
        of: board,
        matching: find.byType(CardWidget),
      );
      BottomToolbar toolbar() =>
          tester.widget<BottomToolbar>(find.byType(BottomToolbar));
      List<Object> snapshot() => [
        for (final element in cards.evaluate())
          (
            (element.widget as CardWidget).card.id,
            (element.widget as CardWidget).card.isFaceUp,
            tester.getTopLeft(find.byElementPredicate((e) => e == element)),
          ),
      ];
      final score = find.textContaining('Score: ');
      final time = find.textContaining('Time: ');

      expect(appearance.deck, DeckStyle.originalClassic);
      expect(appearance.table, TableStyle.originalGreen);
      expect(find.byIcon(Icons.star), findsNWidgets(22));
      expect(find.text('Time: 00:00'), findsOneWidget);
      expect(find.text('Moves: 0'), findsOneWidget);
      // Spend one of each power-up to make resets detectable.
      await tester.tap(find.byTooltip('Wand'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(toolbar().wandCount, 2);
      await tester.tap(find.byTooltip('Freeze'));
      await tester.pump();
      expect(toolbar().freezeCount, 1);
      final frozenTime = tester.widget<Text>(time).data;
      final previous = snapshot();
      final previousScore = tester.widget<Text>(score).data;

      await tester.tap(cards.first); // Stock.
      await tester.pumpAndSettle(); // Compare the settled card positions.
      expect(find.text('Moves: 2'), findsOneWidget);
      final afterDraw = snapshot();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsOneWidget);
      final koi = find.byKey(const ValueKey('deck-koi_kingdom'));
      await tester.ensureVisible(koi);
      await tester.tap(koi);
      await tester.pump();
      await tester.tap(find.text('Table'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('table-silverball_arcade')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byTooltip('Close Appearance'));
      await tester.pumpAndSettle();

      expect(tester.state(board), same(originalBoard));
      expect(snapshot(), afterDraw);
      expect(tester.widget<Text>(score).data, previousScore);
      expect(tester.widget<Text>(time).data, frozenTime);
      expect(find.byIcon(Icons.timer), findsOneWidget);
      expect(toolbar().freezeCount, 1);
      expect(toolbar().wandCount, 2);
      expect(
        tester.widget<TableSurface>(find.byType(TableSurface)).table,
        TableStyle.silverballArcade,
      );
      for (final element in cards.evaluate()) {
        final card = (element.widget as CardWidget).card;
        final image = tester.widget<Image>(
          find.descendant(
            of: find.byElementPredicate((e) => e == element),
            matching: find.byType(Image),
          ),
        );
        final provider =
            (image.image as ResizeImage).imageProvider as AssetImage;
        final expected =
            card.isFaceUp
                ? appearance.deck.faceAsset(card)
                : appearance.deck.backAsset;
        expect(provider.assetName, expected);
      }

      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(snapshot(), previous);
      expect(find.text('Moves: 1'), findsOneWidget);
      expect(appearance.deck, DeckStyle.koiKingdom);
      expect(appearance.table, TableStyle.silverballArcade);
      expect(toolbar().freezeCount, 1);
      expect(toolbar().wandCount, 2);
      await tester.pump(const Duration(seconds: 12));
      expect(find.byIcon(Icons.timer), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
