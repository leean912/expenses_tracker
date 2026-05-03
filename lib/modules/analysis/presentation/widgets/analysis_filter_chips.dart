import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../providers/analysis_state.dart';

class AnalysisFilterChips extends StatelessWidget {
  const AnalysisFilterChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final AnalysisPeriod selected;
  final ValueChanged<AnalysisPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Row(
        children: [
          for (final period in AnalysisPeriod.values) ...[
            _Chip(
              label: period.label,
              isCustom: period == AnalysisPeriod.custom,
              isSelected: period == selected,
              onTap: () => onSelected(period),
            ),
            if (period != AnalysisPeriod.custom)
              const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isCustom = false,
  });

  final String label;
  final bool isSelected;
  final bool isCustom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: isSelected
              ? null
              : Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCustom) ...[
              Icon(
                Icons.calendar_today_rounded,
                size: 11,
                color:
                    isSelected ? AppColors.accentText : AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                color:
                    isSelected ? AppColors.accentText : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
