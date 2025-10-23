// lib/powerups/power_up_bar.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'power_up_manager.dart';

/// A right-side vertical bar (two stacked buttons) that sits
/// above the bottom bar and outside the tableau touch paths.
///
/// IMPORTANT:
/// - It does not use a full-screen GestureDetector, so it won’t block
///   card drag/tap interactions on your game area.
/// - Uses SafeArea + right padding so it never clips.
class PowerUpBar extends StatelessWidget {
  const PowerUpBar({
    super.key,
    required this.onFreezeStart,
    required this.onFreezeEnd,
    required this.performOneBestMove,
    this.bottomBarHeight = 84.0, // adjust to your bottom bar if needed
    this.rightPadding = 8.0,
  });

  /// Callback to pause your game clock increment (not gameplay).
  final VoidCallback onFreezeStart;

  /// Callback to resume your game clock increment.
  final VoidCallback onFreezeEnd;

  /// Your game provides one-best-move executor for the wand.
  final Future<bool> Function() performOneBestMove;

  /// Space we keep above the bottom bar so we never overlap it.
  final double bottomBarHeight;

  /// Tiny spacing from the right edge.
  final double rightPadding;

  @override
  Widget build(BuildContext context) {
    final mgr = context.watch<PowerUpManager>();

    // Visuals are neutral to match your existing UI.
    // You can tweak shapes/sizes without affecting game layout.
    return Positioned(
      right: rightPadding,
      bottom: bottomBarHeight + 8.0, // float just above bottom bar
      child: SafeArea(
        minimum: EdgeInsets.only(right: rightPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PowerUpButton(
              icon: Icons.access_time, // clock
              label: 'Stop Time',
              count: mgr.timeStopCount,
              isActive: mgr.isTimeStopped,
              onPressed: () {
                context.read<PowerUpManager>().useTimeStop(
                  onFreezeStart: onFreezeStart,
                  onFreezeEnd: onFreezeEnd,
                );
              },
              // subtle active glow when time is frozen
              activeIndicator: mgr.isTimeStopped,
            ),
            const SizedBox(height: 10),
            _PowerUpButton(
              iconDataCustom: Icons.auto_fix_high, // magic wand-ish
              label: 'Wand x3',
              count: mgr.wandCount,
              onPressed: () {
                context.read<PowerUpManager>().useMagicWand(
                  performOneBestMove: performOneBestMove,
                  movesToSolve: 3,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PowerUpButton extends StatelessWidget {
  const _PowerUpButton({
    required this.label,
    required this.count,
    required this.onPressed,
    this.icon,
    this.iconDataCustom,
    this.isActive = false,
    this.activeIndicator = false,
  });

  final String label;
  final int count;
  final VoidCallback onPressed;
  final IconData? icon;
  final IconData? iconDataCustom;
  final bool isActive;
  final bool activeIndicator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: activeIndicator ? 6 : 2,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ElevatedButton.icon(
          onPressed: count > 0 ? onPressed : null,
          icon: Icon(icon ?? iconDataCustom, size: 20),
          label: Text(
            label,
            style: theme.textTheme.labelLarge,
          ),
          style: base,
        ),
        // Count pill
        Positioned(
          top: -6,
          right: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: (count > 0)
                  ? theme.colorScheme.primary
                  : theme.disabledColor.withOpacity(0.4),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'x$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        // Subtle glow ring when active (for time stop)
        if (activeIndicator)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 12,
                      spreadRadius: 1,
                      color: theme.colorScheme.primary.withOpacity(0.35),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
