import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../screens/home_state.dart';

/// Horizontal scrollable chips: Today, Week, Month, Year, Custom.
class TimeFilterChips extends StatelessWidget {
  const TimeFilterChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final TimePeriod selected;
  final ValueChanged<TimePeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Row(
          children: [
            for (final period in TimePeriod.values) ...[
              _Chip(
                label: period.label,
                isCustom: period == TimePeriod.custom,
                isSelected: period == selected,
                onTap: () => onSelected(period),
              ),
              if (period != TimePeriod.custom)
                const SizedBox(width: AppSpacing.sm),
            ],
          ],
        ),
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
                color: isSelected
                    ? AppColors.accentText
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                color: isSelected
                    ? AppColors.accentText
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
