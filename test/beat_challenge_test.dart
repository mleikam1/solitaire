import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:solitaire/game/beat_challenge.dart';
import 'package:solitaire/game/deal_spec.dart';

void main() {
  final start = DealSpec(seed: 325, initialFreezeCount: 1, initialWandCount: 0);
  CompletedDeal finish(int moves, int time, {DealSpec? deal}) =>
      (deal: deal ?? start, moves: moves, elapsedMilliseconds: time);

  test('challenge JSON recreates the opening deal and both owner metrics', () {
    for (final goal in BeatGoal.values) {
      final original = BeatChallenge.fromCompleted(goal, finish(140, 180320));
      final copy = BeatChallenge.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(copy.toJson(), original.toJson());
      expect(copy.goal, goal);
      expect(copy.owner.deal.toJson(), start.toJson());
      expect(copy.owner.moves, 140);
      expect(copy.owner.elapsedMilliseconds, 180320);
    }
  });

  test('Beat My Time compares milliseconds and leaves equal times tied', () {
    final owner = BeatChallenge.fromCompleted(
      BeatGoal.time,
      finish(140, 180320),
    );
    expect(owner.compare(finish(145, 180319)), BeatOutcome.win);
    expect(owner.compare(finish(130, 180320)), BeatOutcome.tie);
    expect(owner.compare(finish(120, 180321)), BeatOutcome.loss);
  });

  test('Beat My Moves ignores elapsed time when deciding the outcome', () {
    final owner = BeatChallenge.fromCompleted(
      BeatGoal.moves,
      finish(140, 180320),
    );
    expect(owner.compare(finish(139, 220000)), BeatOutcome.win);
    expect(owner.compare(finish(140, 90000)), BeatOutcome.tie);
    expect(owner.compare(finish(141, 80000)), BeatOutcome.loss);
  });

  test('rejects a different seed or different opening power-up counts', () {
    final owner = BeatChallenge.fromCompleted(
      BeatGoal.time,
      finish(140, 180320),
    );
    for (final different in [
      DealSpec(seed: 326, initialFreezeCount: 1, initialWandCount: 0),
      DealSpec(seed: 325, initialFreezeCount: 2, initialWandCount: 0),
      DealSpec(seed: 325, initialFreezeCount: 1, initialWandCount: 1),
    ]) {
      expect(
        () => owner.compare(finish(100, 10000, deal: different)),
        throwsArgumentError,
      );
    }
    final sameStart = DealSpec.fromJson(start.toJson());
    expect(owner.compare(finish(100, 10000, deal: sameStart)), BeatOutcome.win);
  });

  test('rejects unsupported or malformed challenge payloads and results', () {
    final owner = BeatChallenge.fromCompleted(
      BeatGoal.time,
      finish(140, 180320),
    );
    final json = owner.toJson();
    for (final malformed in [
      null,
      {...json}..remove('moves'),
      {...json, 'other': 12},
      {...json, 'version': 2},
      {...json, 'goal': 'score'},
      {...json, 'moves': 12.5},
      {...json, 'moves': '12'},
      {...json, 'elapsedMs': -1},
      {...json, 'elapsedMs': 9007199254740992},
      {
        ...json,
        'deal': {...start.toJson(), 'rules': 'draw3'},
      },
    ]) {
      expect(() => BeatChallenge.fromJson(malformed), throwsFormatException);
    }
    expect(
      () => BeatChallenge.fromCompleted(BeatGoal.moves, finish(-1, 100)),
      throwsFormatException,
    );
    expect(() => owner.compare(finish(10, -1)), throwsFormatException);
  });
}
