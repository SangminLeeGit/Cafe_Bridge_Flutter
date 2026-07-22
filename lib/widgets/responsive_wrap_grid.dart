import 'package:flutter/material.dart';

class ResponsiveWrapGrid extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  final double runSpacing;
  final int? maxColumns;

  const ResponsiveWrapGrid({
    super.key,
    required this.children,
    this.minItemWidth = 280,
    this.spacing = 12,
    this.runSpacing = 12,
    this.maxColumns,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (maxWidth <= 0 || children.isEmpty) {
          return const SizedBox.shrink();
        }

        var columns = ((maxWidth + spacing) / (minItemWidth + spacing)).floor();
        if (columns < 1) {
          columns = 1;
        }
        if (maxColumns != null && columns > maxColumns!) {
          columns = maxColumns!;
        }

        final itemWidth = columns == 1
            ? maxWidth
            : (maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: children
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(growable: false),
        );
      },
    );
  }
}
