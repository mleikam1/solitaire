import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solitaire/appearance/appearance.dart';
import 'package:solitaire/game/deal_spec.dart';
import 'package:solitaire/game/help_snapshot.dart';
import 'package:solitaire/game/klondike_game.dart';
import 'package:solitaire/models/card_model.dart';
import 'package:solitaire/pages/solitaire_game_page.dart';
import 'package:solitaire/widgets/bottom_toolbar.dart';
import 'package:solitaire/widgets/card_widget.dart';

Future<SolitaireGamePageState> _open(
  WidgetTester tester,
  SolitaireGamePage page,
) async {
  const phone = Size(390, 844);
  if (tester.view.physicalSize != phone || tester.view.devicePixelRatio != 1) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = phone;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }
  SharedPreferences.setMockInitialValues({});
  final appearance = await AppearanceController.load();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: appearance,
      child: MaterialApp(home: page),
    ),
  );
  return tester.state<SolitaireGamePageState>(find.byType(SolitaireGamePage));
}

Future<void> _tapCard(WidgetTester tester, PlayingCard card) async {
  await tester.tap(
    find.byWidgetPredicate((w) => w is CardWidget && identical(w.card, card)),
  );
  await tester.pump();
}

void main() {
  test('help JSON preserves the clock and rejects ill-formed sessions', () {
    final game = KlondikeGame.fromDeal(DealSpec(seed: 3))..drawFromStock();
    final help = HelpSnapshot(
      board: game.snapshot(),
      hasStarted: true,
      elapsedMilliseconds: 65432,
      freezeRemainingMilliseconds: 1750,
    );
    expect(HelpSnapshot.decode(help.encode()).toJson(), help.toJson());
    final mutations = <void Function(Map<String, dynamic>)>[
      (m) => m['version'] = 2,
      (m) => m.remove('elapsedMs'),
      (m) => m['elapsedMs'] = -1,
      (m) => m['elapsedMs'] = 1.25,
      (m) => m['elapsedMs'] = 9000000000001,
      (m) => m['freezeRemainingMs'] = HelpSnapshot.fullFreezeMilliseconds + 1,
      (m) => m['freezeRemainingMs'] = '100',
      (m) => m['hasStarted'] = false, // 65,432 ms already elapsed.
      (m) => m['hasStarted'] = 1,
      (m) => m['board']['version'] = 2,
    ];
    for (final mutate in mutations) {
      final json = jsonDecode(help.encode()) as Map<String, dynamic>;
      mutate(json);
      expect(() => HelpSnapshot.fromJson(json), throwsFormatException);
    }
  });

  final platform = TargetPlatformVariant.only(TargetPlatform.macOS);
  testWidgets('freeze before the first move survives a help handoff', (
    tester,
  ) async {
    final owner = await _open(
      tester,
      SolitaireGamePage.fromDeal(DealSpec(seed: 3), key: UniqueKey()),
    );
    expect(owner.completedDeal, isNull);
    await tester.tap(find.widgetWithIcon(ElevatedButton, Icons.ac_unit));
    await tester.pump(const Duration(milliseconds: 1250));
    final saved = owner.captureHelp();
    expect(saved.hasStarted, isFalse);
    expect(saved.elapsedMilliseconds, 0);
    expect(saved.freezeRemainingMilliseconds, 9750);
    expect(saved.board.freezeCount, 1);

    final helper = await _open(
      tester,
      SolitaireGamePage.fromHelp(
        HelpSnapshot.decode(saved.encode()),
        key: UniqueKey(),
      ),
    );
    expect(helper.game.canUndo, isFalse);
    expect(helper.captureHelp().toJson(), saved.toJson());
    await _tapCard(tester, helper.game.stockTop!);
    await tester.pump(const Duration(milliseconds: 250));
    expect(helper.captureHelp().hasStarted, isTrue);
    expect(helper.captureHelp().elapsedMilliseconds, 0);
    expect(helper.captureHelp().freezeRemainingMilliseconds, 9500);
    helper.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 10));
    expect(helper.captureHelp().elapsedMilliseconds, 0);
    expect(helper.captureHelp().freezeRemainingMilliseconds, 0);
    helper.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 1234));
    expect(helper.captureHelp().elapsedMilliseconds, 1234);
    expect(helper.game.moves, 1);
    expect(saved.board.moves, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platform);

  testWidgets('owner elapsed time is copied only on Help Me Finish', (
    tester,
  ) async {
    final deal = DealSpec(seed: 1);
    final owner = await _open(
      tester,
      SolitaireGamePage.fromDeal(deal, key: UniqueKey()),
    );
    await _tapCard(tester, owner.game.stockTop!);
    await tester.pump(const Duration(milliseconds: 12500));
    await tester.tap(find.widgetWithIcon(ElevatedButton, Icons.ac_unit));
    await tester.pump(const Duration(milliseconds: 4500));
    final handoff = owner.captureHelp();
    expect(handoff.elapsedMilliseconds, 12500);
    expect(handoff.freezeRemainingMilliseconds, 6500);
    expect(owner.game.canUndo, isTrue);

    final helper = await _open(
      tester,
      SolitaireGamePage.fromHelp(handoff, key: UniqueKey()),
    );
    expect(helper.captureHelp().toJson(), handoff.toJson());
    expect(helper.game.undo(), isFalse);
    await tester.pump(const Duration(milliseconds: 7000));
    expect(helper.captureHelp().elapsedMilliseconds, 13000);
    helper.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 2));
    expect(helper.captureHelp().elapsedMilliseconds, 13000);
    helper.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 250));
    expect(helper.captureHelp().elapsedMilliseconds, 13250);

    final challenger = await _open(
      tester,
      SolitaireGamePage.fromDeal(handoff.board.deal, key: UniqueKey()),
    );
    final fresh = challenger.captureHelp();
    expect(fresh.elapsedMilliseconds, 0);
    expect(fresh.hasStarted, isFalse);
    expect(fresh.freezeRemainingMilliseconds, 0);
    expect(fresh.board.moves, 0);
    expect(fresh.board.freezeCount, 2);
    expect(fresh.board.stock, hasLength(24));
    expect(challenger.game.canUndo, isFalse);
    expect(challenger.completedDeal, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platform);

  testWidgets(
    'a stock draw during Wand flight invalidates its pending move',
    (tester) async {
      final page = await _open(
        tester,
        SolitaireGamePage.fromDeal(DealSpec(seed: 3), key: UniqueKey()),
      );
      BottomToolbar toolbar() =>
          tester.widget<BottomToolbar>(find.byType(BottomToolbar));
      // Seed 3 offers the exposed ace of clubs, independent of stock order.
      expect(page.game.planMagicWand()!.actions.single.cards.single.id, 26);
      await tester.tap(
        find.widgetWithIcon(ElevatedButton, Icons.auto_fix_high),
      );
      await tester.pump();
      expect(toolbar().onWand, isNull);
      page.game.drawFromStock();
      final afterDraw = page.captureHelp().board.encode();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(toolbar().onWand, isNotNull);
      expect(page.captureHelp().board.encode(), afterDraw);
      expect(page.game.wandCount, 3);
      expect(page.game.moves, 1);
      expect(page.game.foundationTop(2), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: platform,
  );

  testWidgets('only a completed fresh run exports a competition result', (
    tester,
  ) async {
    final page = await _open(
      tester,
      SolitaireGamePage.fromDeal(DealSpec(seed: 2875), key: UniqueKey()),
    );
    final game = page.game;
    await _tapCard(tester, game.stockTop!);
    await tester.pump(const Duration(milliseconds: 4321));
    // This fixed deal reaches its last king using its three starting Wands.
    // Every action goes through the same move APIs used by the board.
    var drawsWithoutProgress = 0;
    var finishedCards = 0;
    for (var attempts = 0; finishedCards < 51 && attempts < 300; attempts++) {
      final exposed = [
        if (game.wasteTop case final waste?) waste,
        for (final col in game.tableau)
          if (col.isNotEmpty) col.last,
      ];
      var advanced = false;
      for (final card in exposed) {
        if (game.moveCardToFoundation(card, card.suit.index)) {
          advanced = true;
          break;
        }
      }
      if (!advanced &&
          drawsWithoutProgress < 25 &&
          (game.stockTop != null || game.wasteTop != null)) {
        game.drawFromStock();
        drawsWithoutProgress++;
        continue;
      }
      if (!advanced) {
        final plan = game.planMagicWand()!;
        expect(plan.actions.single.type, MagicWandActionType.moveToFoundation);
        expect(game.executeMagicWand(plan), isTrue);
      }
      drawsWithoutProgress = 0;
      finishedCards++;
    }
    expect(finishedCards, 51);
    expect(game.wandCount, 0);
    expect(game.stockTop!.id, 51);
    await tester.pump();
    await _tapCard(tester, game.stockTop!);
    final almostDone = page.captureHelp();
    expect(page.completedDeal, isNull);
    // The waste accepts the next tap even while the drawn king is in flight.
    await tester.tap(find.byKey(ValueKey<int>(game.wasteTop!.id)));
    await tester.pump();
    final result = page.completedDeal!;
    expect(result.deal.seed, 2875);
    expect(result.moves, almostDone.board.moves + 1);
    expect(result.elapsedMilliseconds, 4321);
    await tester.pump(const Duration(seconds: 5));
    expect(page.completedDeal, result);
    await tester.tap(find.widgetWithIcon(ElevatedButton, Icons.undo));
    await tester.pump(const Duration(seconds: 1));
    expect(page.completedDeal, isNull);
    expect(page.captureHelp().elapsedMilliseconds, 5321);
    expect(game.startedFromSnapshot, isFalse);

    final helper = await _open(
      tester,
      SolitaireGamePage.fromHelp(almostDone, key: UniqueKey()),
    );
    expect(helper.game.startedFromSnapshot, isTrue);
    expect(helper.game.canUndo, isFalse);
    await _tapCard(tester, helper.game.wasteTop!);
    expect(helper.game.isWon, isTrue);
    expect(helper.completedDeal, isNull);
    expect(helper.game.undo(), isTrue);
    expect(helper.game.startedFromSnapshot, isTrue);
    await tester.tap(find.widgetWithIcon(ElevatedButton, Icons.shuffle));
    await tester.pump();
    expect(helper.game.startedFromSnapshot, isFalse);
    expect(helper.captureHelp().elapsedMilliseconds, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: platform);
}
