import 'dart:convert';

import 'board_snapshot.dart';
import 'src/wire_fields.dart';

/// One help handoff. Device lifecycle and wall-clock timestamps are local.
/// Elapsed play and remaining Freeze time are durations, so a link never ages.
final class HelpSnapshot {
  HelpSnapshot({
    required this.board,
    required this.hasStarted,
    required this.elapsedMilliseconds,
    required this.freezeRemainingMilliseconds,
  }) {
    wireInteger(elapsedMilliseconds, 'elapsedMs', max: _maxElapsed);
    wireInteger(
      freezeRemainingMilliseconds,
      'freezeRemainingMs',
      max: fullFreezeMilliseconds,
    );
    if (!hasStarted && elapsedMilliseconds != 0) {
      throw const FormatException(
        'An unstarted clock must have zero elapsed time.',
      );
    }
  }

  static const int version = 1;
  // The existing page displays 10, 9, ..., 0 for one tick each.
  static const int fullFreezeMilliseconds = 11000;
  // Leave room for continued play and for Duration's microsecond conversion
  // to stay exact on web. This is over 280 years of active play.
  static const int _maxElapsed = 9000000000000;
  static const int maxJsonLength = BoardSnapshot.maxJsonLength + 1024;

  final BoardSnapshot board;
  final bool hasStarted;
  final int elapsedMilliseconds;
  final int freezeRemainingMilliseconds;

  factory HelpSnapshot.decode(String source) {
    if (source.length > maxJsonLength) {
      throw const FormatException('Help snapshot exceeds the size limit.');
    }
    return HelpSnapshot.fromJson(jsonDecode(source));
  }

  factory HelpSnapshot.fromJson(Object? raw) {
    const fields = {
      'version',
      'board',
      'hasStarted',
      'elapsedMs',
      'freezeRemainingMs',
    };
    final data = wireObject(raw, 'help', fields);
    if (data['version'] != version) {
      throw const FormatException('Unsupported help snapshot.');
    }
    final started = data['hasStarted'];
    if (started is! bool) {
      throw const FormatException('Invalid clock start flag.');
    }
    return HelpSnapshot(
      board: BoardSnapshot.fromJson(data['board']),
      hasStarted: started,
      elapsedMilliseconds: wireInteger(
        data['elapsedMs'],
        'elapsedMs',
        max: _maxElapsed,
      ),
      freezeRemainingMilliseconds: wireInteger(
        data['freezeRemainingMs'],
        'freezeRemainingMs',
        max: fullFreezeMilliseconds,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'board': board.toJson(),
    'hasStarted': hasStarted,
    'elapsedMs': elapsedMilliseconds,
    'freezeRemainingMs': freezeRemainingMilliseconds,
  };

  String encode() => jsonEncode(toJson());
}
