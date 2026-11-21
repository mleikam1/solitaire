import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solitaire/appearance/appearance.dart';
import 'package:solitaire/models/card_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every illustrated face, back and table loads from the Flutter bundle',
    () async {
      final paths = <String>{};
      expect(DeckStyle.values, hasLength(6));
      expect(TableStyle.values, hasLength(11));
      for (final deck in DeckStyle.values) {
        for (final suit in Suit.values) {
          for (var rank = 1; rank <= 13; rank++) {
            final card = PlayingCard(rank: rank, suit: suit);
            final path = deck.faceAsset(card);
            if (deck == DeckStyle.originalClassic) {
              expect(path, isNull);
            } else {
              paths.add(path!);
            }
          }
        }
        if (deck.backAsset != null) paths.add(deck.backAsset!);
      }
      for (final table in TableStyle.values) {
        if (table.asset != null) paths.add(table.asset!);
      }
      expect(paths, hasLength(275));
      final bundle = await AssetManifest.loadFromAssetBundle(rootBundle);
      final installed = bundle.listAssets().where(
        (path) =>
            path.startsWith('assets/cards/') ||
            path.startsWith('assets/backgrounds/'),
      );
      expect(installed, unorderedEquals(paths));
      for (final path in paths) {
        final bytes = await rootBundle.load(path);
        final signature = bytes.getUint32(0);
        expect(
          signature,
          path.endsWith('.png') ? 0x89504E47 : 0x52494646,
          reason: path,
        );
      }
    },
  );

  test('first launch, independent selection, reload and reset', () async {
    SharedPreferences.setMockInitialValues({});
    var appearance = await AppearanceController.load();
    expect(appearance.deck, DeckStyle.originalClassic);
    expect(appearance.table, TableStyle.originalGreen);

    await appearance.setTable(TableStyle.silverballArcade);
    expect(appearance.deck, DeckStyle.originalClassic);
    await appearance.setDeck(DeckStyle.koiKingdom);
    appearance = await AppearanceController.load();
    expect(appearance.deck, DeckStyle.koiKingdom);
    expect(appearance.table, TableStyle.silverballArcade);
    await appearance.restoreDefaults();
    appearance = await AppearanceController.load();
    expect(appearance.deck, DeckStyle.originalClassic);
    expect(appearance.table, TableStyle.originalGreen);
  });

  test('unknown IDs recover independently', () async {
    Future<AppearanceController> open(List<String> ids) {
      SharedPreferences.setMockInitialValues({'appearance.deckAndTable': ids});
      return AppearanceController.load();
    }

    final oldDeck = await open(['retired', 'silverball_arcade']);
    expect(oldDeck.deck, DeckStyle.originalClassic);
    expect(oldDeck.table, TableStyle.silverballArcade);
    final oldTable = await open(['koi_kingdom', 'retired']);
    expect(oldTable.deck, DeckStyle.koiKingdom);
    expect(oldTable.table, TableStyle.originalGreen);
    final shortRecord = await open(['koi_kingdom']);
    expect(shortRecord.deck, DeckStyle.koiKingdom);
    expect(shortRecord.table, TableStyle.originalGreen);
  });
}
