// lib/powerups/power_up_manager.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

/// A simple manager for power-ups. Exposes counts, active states,
/// and methods to consume/use them without touching your existing UI.
class PowerUpManager extends ChangeNotifier {
  PowerUpManager({
    int initialTimeStops = 2,
    int initialWands = 2,
    this.timeStopDuration = const Duration(seconds: 10),
  })  : _timeStopCount = initialTimeStops,
        _wandCount = initialWands;

  int _timeStopCount;
  int _wandCount;

  int get timeStopCount => _timeStopCount;
  int get wandCount => _wandCount;

  final Duration timeStopDuration;

  bool _isTimeStopped = false;
  bool get isTimeStopped => _isTimeStopped;

  Timer? _timeStopTimer;

  /// Start a temporary time freeze (timer stops, gameplay continues).
  /// [onFreezeStart] should pause your game clock increment.
  /// [onFreezeEnd] should resume your game clock increment.
  Future<bool> useTimeStop({
    required VoidCallback onFreezeStart,
    required VoidCallback onFreezeEnd,
  }) async {
    if (_timeStopCount <= 0 || _isTimeStopped) return false;

    _timeStopCount--;
    _isTimeStopped = true;
    notifyListeners();

    onFreezeStart();

    _timeStopTimer?.cancel();
    _timeStopTimer = Timer(timeStopDuration, () {
      _isTimeStopped = false;
      _timeStopTimer = null;
      onFreezeEnd();
      notifyListeners();
    });

    return true;
  }

  /// Use a magic wand to auto-solve up to [movesToSolve] moves.
  /// Your game supplies [performOneBestMove] which returns true if a move executed.
  /// We call it up to 3 times with a small delay for animation pacing.
  Future<bool> useMagicWand({
    required Future<bool> Function() performOneBestMove,
    int movesToSolve = 3,
    Duration perMoveDelay = const Duration(milliseconds: 350),
  }) async {
    if (_wandCount <= 0) return false;

    _wandCount--;
    notifyListeners();

    int done = 0;
    while (done < movesToSolve) {
      final ok = await performOneBestMove();
      if (!ok) break; // no legal move found—stop early
      done++;
      await Future.delayed(perMoveDelay);
    }
    return done > 0;
  }

  /// Optional: add ways to award power-ups (IAP/ads/earn).
  void grantTimeStop(int amount) {
    _timeStopCount += amount;
    notifyListeners();
  }

  void grantWand(int amount) {
    _wandCount += amount;
    notifyListeners();
  }

  @override
  void dispose() {
    _timeStopTimer?.cancel();
    super.dispose();
  }
}
