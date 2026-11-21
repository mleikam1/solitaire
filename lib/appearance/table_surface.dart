import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'appearance.dart';

class TableSurface extends StatelessWidget {
  const TableSurface({
    super.key,
    required this.table,
    this.alignment = Alignment.center,
  });

  final TableStyle table;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final path = table.asset;
    return IgnorePointer(
      child: ColoredBox(
        color: const Color(0xFF006400),
        child:
            path == null
                ? const SizedBox.expand()
                : LayoutBuilder(
                  builder: (context, constraints) {
                    // The supplied tables are 1080 × 1920. Decode enough pixels
                    // to cover the longer axis without stretching the original.
                    final width = math.max(
                      constraints.maxWidth,
                      constraints.maxHeight * 1080 / 1920,
                    );
                    final pixels =
                        width * MediaQuery.devicePixelRatioOf(context);
                    return Image.asset(
                      path,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      alignment: alignment,
                      cacheWidth: pixels.ceil().clamp(1, 1080),
                      excludeFromSemantics: true,
                    );
                  },
                ),
      ),
    );
  }
}
