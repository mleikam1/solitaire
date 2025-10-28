import 'package:flutter/material.dart';

class BottomToolbar extends StatelessWidget {
  final VoidCallback onNewDeal;
  final VoidCallback? onFreeze;
  final VoidCallback? onWand;
  final VoidCallback onHint;
  final VoidCallback onSettings;
  final VoidCallback? onUndo;
  final int freezeCount;
  final int wandCount;
  final bool hintAvailable;

  const BottomToolbar({
    super.key,
    required this.onNewDeal,
    required this.onFreeze,
    required this.onWand,
    required this.onHint,
    required this.onSettings,
    required this.onUndo,
    required this.freezeCount,
    required this.wandCount,
    required this.hintAvailable,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 8, top: 6, bottom: 8),
        child: Row(
          children: [
            _buildToolbarIconButton(
              icon: Icons.settings,
              tooltip: 'Settings',
              onPressed: onSettings,
            ),
            _buildToolbarIconButton(
              icon: Icons.undo,
              tooltip: 'Undo',
              onPressed: onUndo,
            ),
            _buildToolbarIconButton(
              icon: Icons.shuffle,
              tooltip: 'New Deal',
              onPressed: onNewDeal,
            ),
            _buildToolbarIconButton(
              icon: Icons.ac_unit,
              tooltip: 'Freeze',
              onPressed: onFreeze,
              badge: 'x$freezeCount',
              showAsEnabled: onFreeze != null,
            ),
            _buildToolbarIconButton(
              icon: Icons.lightbulb_outline,
              tooltip: 'Hint',
              onPressed: onHint,
              showAsEnabled: hintAvailable,
            ),
            _buildToolbarIconButton(
              icon: Icons.auto_fix_high,
              tooltip: 'Wand',
              onPressed: onWand,
              badge: 'x$wandCount',
              showAsEnabled: onWand != null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    String? badge,
    bool? showAsEnabled,
  }) {
    final bool interactable = onPressed != null;
    final bool effectiveEnabled = (showAsEnabled ?? interactable) && interactable;
    final Color backgroundColor = !interactable
        ? const Color(0xFF2E7D32).withOpacity(0.45)
        : effectiveEnabled
            ? const Color(0xFF2E7D32)
            : const Color(0xFF2E7D32).withOpacity(0.75);
    final Color iconColor = !interactable
        ? Colors.white38
        : effectiveEnabled
            ? Colors.white
            : Colors.white70;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Tooltip(
          message: tooltip,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: backgroundColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: onPressed,
                  child: Icon(icon, size: 26, color: iconColor),
                ),
              ),
              if (badge != null)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Color(0xFF2E7D32),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
