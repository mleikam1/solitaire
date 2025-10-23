import 'package:flutter/material.dart';

class FoundationPiles extends StatelessWidget {
  const FoundationPiles({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 60,
          height: 80,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 2),
            borderRadius: BorderRadius.circular(4),
            color: Colors.black.withOpacity(0.2),
          ),
          alignment: Alignment.center,
          child: Text('A', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 26)),
        );
      }),
    );
  }
}
