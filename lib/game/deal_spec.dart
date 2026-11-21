import 'dart:math';

import '../models/card_model.dart';
import 'src/wire_fields.dart';

/// Everything needed to recreate a V1 challenge start, including the inventory
/// the owner actually had when starting the deal. A seed is not a share ID.
final class DealSpec {
  static const int version = 1;
  static const String rules = 'klondike-draw1-v1';
  static const int _modulus = 2147483647;
  static const int _range = _modulus - 1;
  static const int maxInventory = 2147483647;
  static const _fields = {
    'version',
    'rules',
    'seed',
    'initialFreezeCount',
    'initialWandCount',
  };
  static const List<Suit> _suits = [
    Suit.hearts,
    Suit.diamonds,
    Suit.clubs,
    Suit.spades,
  ];

  DealSpec({
    required int seed,
    int initialFreezeCount = 2,
    int initialWandCount = 3,
  }) : seed = wireInteger(seed, 'seed', min: 1, max: _range),
       initialFreezeCount = wireInteger(
         initialFreezeCount,
         'initialFreezeCount',
         max: maxInventory,
       ),
       initialWandCount = wireInteger(
         initialWandCount,
         'initialWandCount',
         max: maxInventory,
       );

  final int seed;
  final int initialFreezeCount;
  final int initialWandCount;

  factory DealSpec.random({
    required int initialFreezeCount,
    required int initialWandCount,
  }) => DealSpec(
    // Use the SDK generator only to choose a seed, never to replay a shuffle.
    seed: Random().nextInt(_range) + 1,
    initialFreezeCount: initialFreezeCount,
    initialWandCount: initialWandCount,
  );

  factory DealSpec.fromJson(Object? raw) {
    final value = wireObject(raw, 'deal', _fields);
    if (value['rules'] == 'relaxed-draw1-v1') {
      throw const FormatException(
        'This deal uses retired relaxed rules. Start a new Klondike deal.',
      );
    }
    if (value['version'] != version || value['rules'] != rules) {
      throw const FormatException('Unsupported deal version or rules');
    }
    return DealSpec(
      seed: wireInteger(value['seed'], 'seed', min: 1, max: _range),
      initialFreezeCount: wireInteger(
        value['initialFreezeCount'],
        'initialFreezeCount',
        max: maxInventory,
      ),
      initialWandCount: wireInteger(
        value['initialWandCount'],
        'initialWandCount',
        max: maxInventory,
      ),
    );
  }

  Map<String, Object> toJson() => {
    'version': version,
    'rules': rules,
    'seed': seed,
    'initialFreezeCount': initialFreezeCount,
    'initialWandCount': initialWandCount,
  };

  // Fixed wire IDs. Never derive these from enum.index or display labels.
  static int cardId(Suit suit, int rank) {
    RangeError.checkValueInInterval(rank, 1, 13, 'rank');
    return _suits.indexOf(suit) * 13 + rank - 1;
  }

  static PlayingCard cardFromId(int id, {bool isFaceUp = false}) {
    RangeError.checkValueInInterval(id, 0, 51, 'id');
    return PlayingCard(
      id: id,
      suit: _suits[id ~/ 13],
      rank: id % 13 + 1,
      isFaceUp: isFaceUp,
    );
  }

  /// V1 starts with IDs 0..51. Backward Fisher-Yates uses Park-Miller
  /// (multiplier 48271) with rejection sampling. The largest intermediate
  /// product is below 2^47, exact on Dart VM and JavaScript.
  List<PlayingCard> shuffledDeck() {
    final cards = List.generate(52, (id) => cardFromId(id));
    var state = seed;
    for (var i = cards.length - 1; i > 0; i--) {
      final bound = i + 1;
      final limit = _range - _range % bound;
      int sample;
      do {
        state = (state * 48271) % _modulus;
        sample = state - 1;
      } while (sample >= limit);
      final j = sample % bound;
      final swapped = cards[i];
      cards[i] = cards[j];
      cards[j] = swapped;
    }
    return cards;
  }
}
