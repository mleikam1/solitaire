import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solitaire/appearance/appearance.dart';
import 'package:solitaire/game/deal_spec.dart';
import 'package:solitaire/pages/solitaire_game_page.dart';
import 'package:solitaire/widgets/bottom_toolbar.dart';
import 'package:solitaire/widgets/card_widget.dart';

void main() {
  testWidgets(
    'reshuffling requires confirmation and only Yes resets the deal',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 720);
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final appearance = await AppearanceController.load();
      addTearDown(appearance.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: appearance,
          child: MaterialApp(
            home: SolitaireGamePage.fromDeal(DealSpec(seed: 3)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final page = tester.state<SolitaireGamePageState>(
        find.byType(SolitaireGamePage),
      );
      final game = page.game;
      final hintControl = find.byTooltip('Hint');
      final hintButton = find.descendant(
        of: hintControl,
        matching: find.byType(ElevatedButton),
      );
      int hintsLeft() => tester
          .widget<BottomToolbar>(find.byType(BottomToolbar))
          .hintsRemaining;
      bool canTapHint() =>
          tester.widget<ElevatedButton>(hintButton).onPressed != null;

      expect(hintsLeft(), 5);
      for (var remaining = 4; remaining >= 0; remaining--) {
        expect(canTapHint(), isTrue);
        await tester.tap(hintControl);
        await tester.pump();
        expect(hintsLeft(), remaining);
      }
      expect(canTapHint(), isFalse);
      await tester.tap(hintControl);
      await tester.pump();
      expect(hintsLeft(), 0);

      await tester.tap(find.byType(CardWidget).first); // Draw from stock.
      await tester.pumpAndSettle();
      expect(game.moves, 1);
      expect(game.canUndo, isTrue);
      expect(hintsLeft(), 0);
      final before = game.snapshot().toJson();

      Future<void> openPrompt() async {
        await tester.tap(find.byTooltip('New Deal'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.text(
            'This will restart your game and you’ll lose your current progress. '
            'Is this what you want to do?',
          ),
          findsOneWidget,
        );
        expect(game.snapshot().toJson(), before);
      }

      await openPrompt();
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(game.snapshot().toJson(), before);
      expect(game.canUndo, isTrue);
      expect(hintsLeft(), 0);

      await openPrompt();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(game.snapshot().toJson(), before);

      await tester.tap(find.byTooltip('Undo'));
      await tester.pumpAndSettle();
      expect(game.moves, 0);
      expect(hintsLeft(), 0);
      await tester.tap(find.byType(CardWidget).first);
      await tester.pumpAndSettle();
      await openPrompt();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(game.moves, 0);
      expect(game.canUndo, isFalse);
      expect(game.snapshot().stock, hasLength(24));
      expect(find.text('Time: 00:00'), findsOneWidget);
      expect(hintsLeft(), 5);
      expect(canTapHint(), isTrue);
      await tester.tap(hintControl);
      await tester.pump();
      expect(hintsLeft(), 4);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
