import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final bool accent;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor =
        accent ? CafeBridgeColors.accentSoft : CafeBridgeColors.surface;
    final borderColor =
        accent ? CafeBridgeColors.accent : CafeBridgeColors.border;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              color: CafeBridgeColors.textFaint,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              color: CafeBridgeColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(
              sub!,
              style: const TextStyle(
                fontSize: 12,
                color: CafeBridgeColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
