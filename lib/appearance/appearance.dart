import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/card_model.dart';

enum DeckStyle {
  originalClassic('original_classic', 'Original Classic'),
  silverball('silverball', 'Silverball'),
  moonshot59('moonshot_59', 'Moonshot ’59'),
  koiKingdom('koi_kingdom', 'Koi Kingdom'),
  candyCarnival('candy_carnival', 'Candy Carnival'),
  velvetTempo('velvet_tempo', 'Velvet Tempo');

  const DeckStyle(this.id, this.label);
  final String id;
  final String label;

  String? get backAsset =>
      this == originalClassic ? null : 'assets/cards/$id/back.png';

  String? faceAsset(PlayingCard card) {
    if (this == originalClassic) return null;
    final rank = card.displayValue.toLowerCase();
    return 'assets/cards/$id/${rank}_${card.suit.name}.png';
  }
}

enum TableStyle {
  originalGreen('original_green', 'Original Green'),
  classicGreenFelt(
    'classic_green_felt',
    'Classic Green Felt',
    '01_classic_green',
  ),
  silverballArcade(
    'silverball_arcade',
    'Silverball Arcade',
    '02_silverball_arcade',
  ),
  midnightGrid('midnight_grid', 'Midnight Grid', '03_midnight_grid'),
  lunarPost('lunar_post', 'Lunar Post', '04_lunar_post'),
  koiGarden('koi_garden', 'Koi Garden', '05_koi_garden'),
  peppermintPier('peppermint_pier', 'Peppermint Pier', '06_peppermint_pier'),
  velvetAfterHours(
    'velvet_after_hours',
    'Velvet After Hours',
    '07_velvet_after_hours',
  ),
  sunsetSurf('sunset_surf', 'Sunset Surf', '08_sunset_surf'),
  alpineExpress('alpine_express', 'Alpine Express', '09_alpine_express'),
  fireflyConservatory(
    'firefly_conservatory',
    'Firefly Conservatory',
    '10_firefly_conservatory',
  );

  const TableStyle(this.id, this.label, [this._filename]);
  final String id;
  final String label;
  final String? _filename;

  String? get asset =>
      _filename == null ? null : 'assets/backgrounds/$_filename.webp';
}

class AppearanceController extends ChangeNotifier {
  AppearanceController._(this._preferences, this._deck, this._table);

  // Save the two IDs together so Restore Defaults is also a single write.
  static const _key = 'appearance.deckAndTable';
  final SharedPreferences _preferences;
  DeckStyle _deck;
  TableStyle _table;
  DeckStyle get deck => _deck;
  TableStyle get table => _table;

  static Future<AppearanceController> load() async {
    final preferences = await SharedPreferences.getInstance();
    final ids = preferences.get(_key);
    final deckId = ids is List && ids.isNotEmpty ? ids.first : null;
    final tableId = ids is List && ids.length >= 2 ? ids[1] : null;
    return AppearanceController._(
      preferences,
      DeckStyle.values.firstWhere(
        (d) => d.id == deckId,
        orElse: () => DeckStyle.originalClassic,
      ),
      TableStyle.values.firstWhere(
        (t) => t.id == tableId,
        orElse: () => TableStyle.originalGreen,
      ),
    );
  }

  Future<void> setDeck(DeckStyle value) => _select(value, _table);
  Future<void> setTable(TableStyle value) => _select(_deck, value);
  Future<void> restoreDefaults() =>
      _select(DeckStyle.originalClassic, TableStyle.originalGreen);

  Future<void> _select(DeckStyle deck, TableStyle table) async {
    if (_deck == deck && _table == table) return;
    _deck = deck;
    _table = table;
    final saved = _preferences.setStringList(_key, [deck.id, table.id]);
    notifyListeners();
    if (!await saved) {
      throw StateError('Could not save appearance preferences.');
    }
  }
}
