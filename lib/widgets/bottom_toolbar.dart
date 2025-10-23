import 'package:flutter/material.dart';

class BottomToolbar extends StatelessWidget {
  final VoidCallback onNewDeal;
  final VoidCallback onFreeze;
  final VoidCallback onWand;
  final int freezeCount;
  final int wandCount;

  const BottomToolbar({
    super.key,
    required this.onNewDeal,
    required this.onFreeze,
    required this.onWand,
    required this.freezeCount,
    required this.wandCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildButton('Freeze x$freezeCount', onFreeze),
          _buildButton('Wand x$wandCount', onWand),
          _buildButton('New Deal', onNewDeal),
        ],
      ),
    );
  }

  Widget _buildButton(String text, VoidCallback onPressed) {
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
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
