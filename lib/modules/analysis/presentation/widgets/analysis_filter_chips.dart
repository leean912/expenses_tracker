import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/widgets/upgrade_sheet.dart';
import '../../../subscription/providers/subscription_provider.dart';
import '../../providers/analysis_state.dart';

const _premiumPeriods = {AnalysisPeriod.year, AnalysisPeriod.custom};

class AnalysisFilterChips extends ConsumerWidget {
  const AnalysisFilterChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final AnalysisPeriod selected;
  final ValueChanged<AnalysisPeriod> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(isPremiumProvider);

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
              isLocked: !isPremium && _premiumPeriods.contains(period),
              onTap: () {
                if (!isPremium && _premiumPeriods.contains(period)) {
                  UpgradeSheet.show(
                    context,
                    title: 'Premium filter',
                    description:
                        'Year and Custom date range filters are Premium features.',
                  );
                  return;
                }
                onSelected(period);
              },
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
    this.isLocked = false,
  });

  final String label;
  final bool isSelected;
  final bool isCustom;
  final bool isLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isLocked ? 0.45 : 1.0,
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
              if (isLocked) ...[
                Icon(
                  Icons.lock_rounded,
                  size: 10,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: AppSpacing.xs),
              ] else if (isCustom) ...[
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
      ),
    );
  }
}
