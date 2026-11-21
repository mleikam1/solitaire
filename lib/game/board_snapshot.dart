import 'dart:convert';

import '../models/card_model.dart';
import 'deal_spec.dart';
import 'src/wire_fields.dart';

/// A card's wire ID is fixed by suit and rank, independent of object identity.
final class SnapshotCard {
  const SnapshotCard._(this.id, this.isFaceUp);

  final int id;
  final bool isFaceUp;

  PlayingCard toPlayingCard() => DealSpec.cardFromId(id, isFaceUp: isFaceUp);

  Map<String, Object?> toJson() => {'id': id, 'up': isFaceUp};
}

/// A detached, immutable board. All piles run from bottom to top.
///
/// The owner of a session stores elapsed time and active Freeze separately.
/// Undo history belongs to one player and never crosses the share boundary.
final class BoardSnapshot {
  const BoardSnapshot._({
    required this.deal,
    required this.stock,
    required this.waste,
    required this.foundations,
    required this.tableau,
    required this.score,
    required this.moves,
    required this.freezeCount,
    required this.wandCount,
  });

  static const int version = 1;
  static const int maxJsonLength = 16384;

  final DealSpec deal;
  final List<SnapshotCard> stock;
  final List<SnapshotCard> waste;
  final List<List<SnapshotCard>> foundations;
  final List<List<SnapshotCard>> tableau;
  final int score;
  final int moves;
  final int freezeCount;
  final int wandCount;

  /// Route locally captured and imported boards through the same validator.
  factory BoardSnapshot.capture({
    required DealSpec deal,
    required List<PlayingCard> stock,
    required List<PlayingCard> waste,
    required List<List<PlayingCard>> foundations,
    required List<List<PlayingCard>> tableau,
    required int score,
    required int moves,
    required int freezeCount,
    required int wandCount,
  }) {
    List<Map<String, Object?>> pack(List<PlayingCard> pile) => [
      for (final card in pile)
        {'id': DealSpec.cardId(card.suit, card.rank), 'up': card.isFaceUp},
    ];

    return BoardSnapshot.fromJson({
      'version': version,
      'deal': deal.toJson(),
      'stock': pack(stock),
      'waste': pack(waste),
      'foundations': foundations.map(pack).toList(),
      'tableau': tableau.map(pack).toList(),
      'score': score,
      'moves': moves,
      'freezeCount': freezeCount,
      'wandCount': wandCount,
    });
  }

  factory BoardSnapshot.decode(String source) {
    if (source.length > maxJsonLength) {
      throw const FormatException('Board snapshot exceeds the size limit.');
    }
    return BoardSnapshot.fromJson(jsonDecode(source));
  }

  factory BoardSnapshot.fromJson(Object? data) {
    final board = wireObject(data, 'board', const [
      'version',
      'deal',
      'stock',
      'waste',
      'foundations',
      'tableau',
      'score',
      'moves',
      'freezeCount',
      'wandCount',
    ]);
    if (wireInteger(board['version'], 'version') != version) {
      throw const FormatException('Unsupported board snapshot version.');
    }

    final deal = DealSpec.fromJson(board['deal']);
    final seen = <int>{};

    List<SnapshotCard> readPile(
      Object? raw,
      String field, {
      bool? faceUp,
      int? foundationIndex,
    }) {
      final maxCards = foundationIndex == null ? 52 : 13;
      if (raw is! List || raw.length > maxCards) {
        throw FormatException('Invalid pile at $field.');
      }
      final cards = <SnapshotCard>[];
      PlayingCard? previousVisible;
      for (var depth = 0; depth < raw.length; depth++) {
        final path = '$field[$depth]';
        final card = wireObject(raw[depth], path, const ['id', 'up']);
        final id = wireInteger(card['id'], '$path.id', max: 51);
        final up = card['up'];
        if (up is! bool || (faceUp != null && up != faceUp)) {
          throw FormatException('Invalid card orientation at $path.');
        }
        if (!seen.add(id)) {
          throw FormatException('Duplicate card ID $id.');
        }
        if (foundationIndex != null && id != foundationIndex * 13 + depth) {
          throw FormatException('Invalid foundation order at $path.');
        }
        if (faceUp == null) {
          // Tableau columns have a hidden prefix followed by one legal run.
          if (up) {
            final current = DealSpec.cardFromId(id, isFaceUp: true);
            if (previousVisible != null &&
                !canBuildTableauPair(
                  previousVisible.rank,
                  previousVisible.suit,
                  current.rank,
                  current.suit,
                )) {
              throw FormatException('Invalid tableau sequence at $path.');
            }
            previousVisible = current;
          } else if (previousVisible != null) {
            throw FormatException('Hidden card above a visible card at $path.');
          }
        }
        cards.add(SnapshotCard._(id, up));
      }
      return List.unmodifiable(cards);
    }

    List<List<SnapshotCard>> readColumns(
      String field,
      int count, {
      required bool foundation,
    }) {
      final raw = board[field];
      if (raw is! List || raw.length != count) {
        throw FormatException('Expected $count columns at $field.');
      }
      return List.unmodifiable([
        for (var i = 0; i < count; i++)
          readPile(
            raw[i],
            '$field[$i]',
            faceUp: foundation ? true : null,
            foundationIndex: foundation ? i : null,
          ),
      ]);
    }

    final stock = readPile(board['stock'], 'stock', faceUp: false);
    final waste = readPile(board['waste'], 'waste', faceUp: true);
    final foundations = readColumns('foundations', 4, foundation: true);
    final tableau = readColumns('tableau', 7, foundation: false);
    if (seen.length != 52) {
      throw const FormatException('A board must contain all 52 cards once.');
    }

    return BoardSnapshot._(
      deal: deal,
      stock: stock,
      waste: waste,
      foundations: foundations,
      tableau: tableau,
      score: wireInteger(board['score'], 'score'),
      moves: wireInteger(board['moves'], 'moves'),
      freezeCount: wireInteger(
        board['freezeCount'],
        'freezeCount',
        max: DealSpec.maxInventory,
      ),
      wandCount: wireInteger(
        board['wandCount'],
        'wandCount',
        max: DealSpec.maxInventory,
      ),
    );
  }

  Map<String, Object?> toJson() {
    List<Map<String, Object?>> pack(List<SnapshotCard> pile) => [
      for (final card in pile) card.toJson(),
    ];

    return {
      'version': version,
      'deal': deal.toJson(),
      'stock': pack(stock),
      'waste': pack(waste),
      'foundations': foundations.map(pack).toList(),
      'tableau': tableau.map(pack).toList(),
      'score': score,
      'moves': moves,
      'freezeCount': freezeCount,
      'wandCount': wandCount,
    };
  }

  String encode() => jsonEncode(toJson());
}
