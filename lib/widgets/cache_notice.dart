import 'package:flutter/material.dart';

import '../models/dashboard_model.dart';
import '../theme/app_theme.dart';

class CacheNotice extends StatelessWidget {
  final DateTime? cachedAt;
  final String prefix;

  const CacheNotice({
    super.key,
    required this.cachedAt,
    this.prefix = '오프라인 캐시',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.warningBorder),
      ),
      child: Text(
        '$prefix · ${UiFormat.compactDateTime(cachedAt?.toIso8601String())}',
        style: const TextStyle(
          color: AppColors.warningForeground,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
