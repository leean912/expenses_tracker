import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../providers/analysis_state.dart';

class BudgetVsActualCard extends StatelessWidget {
  const BudgetVsActualCard({super.key, required this.budgets});

  final List<BudgetProgress> budgets;

  String _fmtCents(int cents) {
    final rm = cents / 100;
    if (rm >= 1000) return 'RM ${(rm / 1000).toStringAsFixed(1)}K';
    return 'RM ${rm.toStringAsFixed(0)}';
  }

  Color _barColor(double progress) {
    if (progress >= 1.0) return const Color(0xFFD84040);
    if (progress >= 0.8) return const Color(0xFFBA7517);
    return AppColors.incomeDark;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: budgets.map((budget) {
        final color = _barColor(budget.progress);
        final overBy = budget.spentCents - budget.limitCents;
        final remaining = budget.limitCents - budget.spentCents;

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
            ],
          ),
        );
      }).toList(),
    );
  }
}
