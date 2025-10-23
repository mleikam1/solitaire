// lib/widgets/tableau_piles.dart
import 'package:flutter/material.dart';

class TableauPiles extends StatelessWidget {
  const TableauPiles({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(7, (index) {
            return Container(
              width: constraints.maxWidth / 8,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: List.generate(index + 1, (i) {
                  return Container(
                    // 🔧 removed `const` because `i` is dynamic
                    margin: EdgeInsets.only(top: i == 0 ? 0 : 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(blurRadius: 3, color: Colors.black26)
                      ],
                    ),
                    width: double.infinity,
                    height: 80,
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        );
      },
    );
  }
}
