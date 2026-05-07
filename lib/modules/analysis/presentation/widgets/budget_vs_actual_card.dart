import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/widgets/upgrade_sheet.dart';
import '../../providers/analysis_state.dart';
import 'spend_vs_budget_chart.dart';

class BudgetVsActualCard extends StatelessWidget {
  const BudgetVsActualCard({
    super.key,
    required this.budgets,
    required this.isPremium,
    this.showPaceCharts = true,
  });

  final List<BudgetProgress> budgets;
  final bool isPremium;
  final bool showPaceCharts;

  String _fmtCents(int cents) {
    final rm = cents / 100;
    if (rm >= 10000) return 'RM ${(rm / 1000).toStringAsFixed(1)}K';
    if (rm >= 1000) {
      final formatted = rm.toStringAsFixed(0);
      final buf = StringBuffer();
      final chars = formatted.split('').reversed.toList();
      for (var i = 0; i < chars.length; i++) {
        if (i > 0 && i % 3 == 0) buf.write(',');
        buf.write(chars[i]);
      }
      return 'RM ${buf.toString().split('').reversed.join()}';
    }
    return 'RM ${rm.toStringAsFixed(0)}';
  }

  Color _barColor(double progress) {
    if (progress >= 1.0) return const Color(0xFFD84040);
    if (progress >= 0.8) return AppColors.premiumStatus;
    return AppColors.incomeDark;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: budgets.map((budget) {
        final color = _barColor(budget.progress);
        final overBy = budget.spentCents - budget.limitCents;
        final remaining = budget.limitCents - budget.spentCents;
        final hasPace = budget.pacePoints.isNotEmpty;

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    budget.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${_fmtCents(budget.spentCents)} / ${_fmtCents(budget.limitCents)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: budget.progress.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: AppColors.surfaceMuted,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                budget.progress >= 1.0
                    ? 'Over budget by ${_fmtCents(overBy)}'
                    : '${budget.percentUsed}% used · ${_fmtCents(remaining)} left',
                style: TextStyle(fontSize: 11, color: color),
              ),
              if (hasPace && showPaceCharts) ...[
                const SizedBox(height: AppSpacing.lg),
                if (isPremium)
                  SpendVsBudgetChart(
                    points: budget.pacePoints,
                    spendColor: budget.barColor,
                  )
                else
                  _PaceChartLocked(context: context),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _PaceChartLocked extends StatelessWidget {
  const _PaceChartLocked({required this.context});

  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => UpgradeSheet.show(
        context,
        title: 'Budget pace chart',
        description:
            'See how your daily spend compares to your budget pace — a Premium feature.',
      ),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_rounded, size: 13, color: AppColors.textTertiary),
            SizedBox(width: 6),
            Text(
              'Upgrade to Premium to unlock pace chart',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
