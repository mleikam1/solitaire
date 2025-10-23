import 'dart:async';
import 'package:flutter/material.dart';

class GameTimer extends StatefulWidget {
  final bool running;
  final ValueChanged<Duration>? onTick;
  const GameTimer({super.key, required this.running, this.onTick});

  @override
  State<GameTimer> createState() => _GameTimerState();
}

class _GameTimerState extends State<GameTimer> {
  final _watch = Stopwatch();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  @override
  void didUpdateWidget(covariant GameTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.running && !_watch.isRunning) {
      _watch.start();
    } else if (!widget.running && _watch.isRunning) {
      _watch.stop();
    }
  }

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.running && !_watch.isRunning) _watch.start();
      widget.onTick?.call(_watch.elapsed);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = _watch.elapsed;
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return Text("Time: $mm:$ss",
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ));
  }
}
