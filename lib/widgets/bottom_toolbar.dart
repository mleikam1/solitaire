import 'package:flutter/material.dart';

class BottomToolbar extends StatelessWidget {
  final VoidCallback onNewDeal;
  final VoidCallback onFreeze;
  final VoidCallback onWand;
  final VoidCallback onSettings;
  final VoidCallback? onUndo;
  final int freezeCount;
  final int wandCount;

  const BottomToolbar({
    super.key,
    required this.onNewDeal,
    required this.onFreeze,
    required this.onWand,
    required this.onSettings,
    required this.onUndo,
    required this.freezeCount,
    required this.wandCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildIconLabelButton(
                icon: Icons.settings,
                label: 'Settings',
                onPressed: onSettings,
              ),
              _buildIconLabelButton(
                icon: Icons.undo,
                label: 'Undo',
                onPressed: onUndo,
              ),
              _buildTextButton('New Deal', onNewDeal),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildPowerUpButton('Freeze', freezeCount, onFreeze),
              _buildPowerUpButton('Wand', wandCount, onWand),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextButton(String text, VoidCallback onPressed) {
    return _buildToolbarButton(
      onPressed: onPressed,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildIconLabelButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return _buildToolbarButton(
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPowerUpButton(
      String label, int count, VoidCallback onPressed) {
    return _buildToolbarButton(
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'x$count',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required Widget child,
    required VoidCallback? onPressed,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: onPressed,
          child: child,
        ),
      ),
    );
  }
}
