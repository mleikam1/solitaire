import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solitaire/appearance/appearance.dart';
import 'package:solitaire/appearance/appearance_panel.dart';
import 'package:solitaire/appearance/table_surface.dart';
import 'package:solitaire/widgets/card_widget.dart';

Future<AppearanceController> openPanel(
  WidgetTester tester,
  Size viewport,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final appearance = await AppearanceController.load();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: appearance,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings),
                  onPressed: () => showAppearancePanel(context),
                ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
  return appearance;
}

Set<String> artworkPaths(WidgetTester tester, Finder parent) {
  final images = tester.widgetList<Image>(
    find.descendant(of: parent, matching: find.byType(Image)),
  );
  final paths = <String>{};
  for (final image in images) {
    final provider = image.image;
    final original =
        provider is ResizeImage ? provider.imageProvider : provider;
    if (original is AssetImage) paths.add(original.assetName);
  }
  return paths;
}

void expectSample(WidgetTester tester, DeckStyle deck, TableStyle table) {
  final sample = find.bySemanticsLabel(
    'Preview: ${deck.label} on ${table.label}',
  );
  expect(sample, findsOneWidget);
  final cards = find.descendant(of: sample, matching: find.byType(CardWidget));
  final widgets = tester.widgetList<CardWidget>(cards).toList();
  expect(widgets.length, 3);
  expect(widgets.map((c) => c.deck), everyElement(deck));
  expect(widgets.where((c) => !c.card.isFaceUp).length, 1);
  for (var i = 1; i < widgets.length; i++) {
    expect(
      tester.getRect(cards.at(i - 1)).overlaps(tester.getRect(cards.at(i))),
      isTrue,
    );
  }
  expect(
    tester
        .widget<TableSurface>(
          find.descendant(of: sample, matching: find.byType(TableSurface)),
        )
        .table,
    table,
  );
  final art = artworkPaths(tester, sample);
  expect(art, {
    if (table.asset != null) table.asset!,
    if (deck.backAsset != null) ...[
      deck.backAsset!,
      for (final w in widgets.where((c) => c.card.isFaceUp))
        deck.faceAsset(w.card)!,
    ],
  });
}

Future<Finder> choose(
  WidgetTester tester,
  String key, {
  double step = 90,
}) async {
  final tile = find.byKey(ValueKey(key));
  final scroll = find.descendant(
    of: find.byType(GridView),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(tile, step, scrollable: scroll);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
  final semantics = tester.widget<Semantics>(
    find.descendant(of: tile, matching: find.byType(Semantics)).first,
  );
  expect(semantics.properties.selected, isTrue);
  return tile;
}

void main() {
  testWidgets('All choices work independently on a narrow phone', (
    tester,
  ) async {
    final appearance = await openPanel(tester, const Size(320, 568));
    expectSample(tester, DeckStyle.starlineArcade, TableStyle.originalGreen);
    await tester.tap(find.text('Table'));
    await tester.pumpAndSettle();
    await choose(tester, 'table-${TableStyle.silverballArcade.id}');

    await tester.tap(find.text('Deck'));
    await tester.pumpAndSettle();
    for (final deck in DeckStyle.values) {
      final tile = await choose(tester, 'deck-${deck.id}');
      expect(appearance.deck, deck);
      expect(appearance.table, TableStyle.silverballArcade);
      expectSample(tester, deck, TableStyle.silverballArcade);
      final previews = tester.widgetList<CardWidget>(
        find.descendant(of: tile, matching: find.byType(CardWidget)),
      );
      expect(previews.map((c) => c.deck), everyElement(deck));
      final court = previews.singleWhere((c) => c.card.isFaceUp);
      expect(court.card.rank, inInclusiveRange(11, 13));
      expect(previews.where((c) => !c.card.isFaceUp).length, 1);
      expect(artworkPaths(tester, tile), {
        if (deck.backAsset != null) ...[
          deck.backAsset!,
          deck.faceAsset(court.card)!,
        ],
      });
    }

    await choose(tester, 'deck-${DeckStyle.koiKingdom.id}', step: -90);
    await tester.tap(find.text('Table'));
    await tester.pumpAndSettle();
    for (final table in TableStyle.values) {
      final tile = await choose(
        tester,
        'table-${table.id}',
        step: table == TableStyle.originalGreen ? -90 : 90,
      );
      expect(appearance.deck, DeckStyle.koiKingdom);
      expect(appearance.table, table);
      expectSample(tester, DeckStyle.koiKingdom, table);
      expect(artworkPaths(tester, tile), {
        if (table.asset != null) table.asset!,
      });
    }

    await tester.tap(find.text('Restore Defaults'));
    await tester.pumpAndSettle();
    expectSample(tester, DeckStyle.starlineArcade, TableStyle.originalGreen);
    await tester.tap(find.byTooltip('Close Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Play setting is immediate, persists, and is independent of appearance',
    (tester) async {
      final settings = await openPanel(tester, const Size(320, 568));
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(settings.autoCollectFoundations, isTrue);
      await tester.tap(find.text('Auto-collect by suit'));
      await tester.pumpAndSettle();
      expect(settings.autoCollectFoundations, isFalse);

      await tester.tap(find.text('Deck'));
      await tester.pumpAndSettle();
      await choose(tester, 'deck-koi_kingdom');
      await tester.tap(find.text('Restore Defaults'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close Settings'));
      await tester.pumpAndSettle();
      final saved = await AppearanceController.load();
      expect(saved.autoCollectFoundations, isFalse);
      expect(saved.deck, DeckStyle.starlineArcade);
      expect(saved.table, TableStyle.originalGreen);
    },
  );

  testWidgets('Tablet panel shows illustrated tiles and a mixed sample', (
    tester,
  ) async {
    await openPanel(tester, const Size(820, 1180));
    expect(
      find.byKey(ValueKey('deck-${DeckStyle.velvetTempo.id}')).hitTestable(),
      findsOneWidget,
    );
    await choose(tester, 'deck-${DeckStyle.koiKingdom.id}');
    await tester.tap(find.text('Table'));
    await tester.pumpAndSettle();
    await choose(tester, 'table-${TableStyle.silverballArcade.id}');
    expectSample(tester, DeckStyle.koiKingdom, TableStyle.silverballArcade);
    expect(find.byTooltip('Close Settings').hitTestable(), findsOneWidget);
    expect(find.text('Restore Defaults').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
