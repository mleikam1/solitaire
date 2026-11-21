import 'deal_spec.dart';
import 'src/wire_fields.dart';

typedef CompletedDeal = ({DealSpec deal, int moves, int elapsedMilliseconds});

enum BeatGoal { time, moves }

/// Outcome from the challenger's perspective.
enum BeatOutcome { win, tie, loss }

/// A client-side challenge baseline. The page provides a CompletedDeal only
/// after a fresh-start victory. A service must verify competitive submissions.
final class BeatChallenge {
  const BeatChallenge._(this.goal, this.owner);

  static const int version = 1;
  final BeatGoal goal;
  final CompletedDeal owner;

  factory BeatChallenge.fromCompleted(BeatGoal goal, CompletedDeal owner) {
    _validateResult(owner);
    return BeatChallenge._(goal, owner);
  }

  factory BeatChallenge.fromJson(Object? raw) {
    const fields = {'version', 'goal', 'deal', 'moves', 'elapsedMs'};
    final data = wireObject(raw, 'challenge', fields);
    if (data['version'] != version) {
      throw const FormatException('Unsupported Beat challenge.');
    }
    final goal = switch (data['goal']) {
      'time' => BeatGoal.time,
      'moves' => BeatGoal.moves,
      _ => throw const FormatException('Unknown Beat challenge goal.'),
    };
    return BeatChallenge._(goal, (
      deal: DealSpec.fromJson(data['deal']),
      moves: wireInteger(data['moves'], 'moves'),
      elapsedMilliseconds: wireInteger(data['elapsedMs'], 'elapsedMs'),
    ));
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'goal': goal == BeatGoal.time ? 'time' : 'moves',
    'deal': owner.deal.toJson(),
    'moves': owner.moves,
    'elapsedMs': owner.elapsedMilliseconds,
  };

  /// Compare completions using only the selected metric. Both metrics remain
  /// available for display when the primary metric ties.
  BeatOutcome compare(CompletedDeal challenger) {
    _validateResult(challenger);
    final expected = owner.deal;
    final played = challenger.deal;
    // DealSpec accepts one generator and one rules version in V1.
    if (expected.seed != played.seed ||
        expected.initialFreezeCount != played.initialFreezeCount ||
        expected.initialWandCount != played.initialWandCount) {
      throw ArgumentError('Results belong to different starting deals.');
    }
    final order = switch (goal) {
      BeatGoal.time => challenger.elapsedMilliseconds.compareTo(
        owner.elapsedMilliseconds,
      ),
      BeatGoal.moves => challenger.moves.compareTo(owner.moves),
    };
    if (order == 0) return BeatOutcome.tie;
    return order < 0 ? BeatOutcome.win : BeatOutcome.loss;
  }

  static void _validateResult(CompletedDeal result) {
    wireInteger(result.moves, 'moves');
    wireInteger(result.elapsedMilliseconds, 'elapsedMs');
  }
}
