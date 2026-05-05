import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../providers/home/home_state.dart';

/// A single small budget card. Designed to fit 3-per-row in a grid.
class BudgetCard extends StatelessWidget {
  const BudgetCard({super.key, required this.budget, this.onTap});

  final BudgetMini budget;
  final VoidCallback? onTap;

  String _fmtCents(int cents, {bool prefix = true}) {
    final value = cents / 100;
    final whole = value.truncate();
    final frac = ((value - whole) * 100).round();
    final str = whole.toString();
    final buf = StringBuffer(prefix ? 'RM ' : '');
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write(',');
      buf.write(str[i]);
    }
    buf.write('.');
    buf.write(frac.toString().padLeft(2, '0'));
    return buf.toString();
  }

  String _fmtSpent(int cents) => _fmtCents(cents);
  String _fmtLimit(int cents) => _fmtCents(cents, prefix: false);

  Color get _progressColor {
    final pct = budget.percentUsed;
    if (pct >= 90) return const Color(0xFFE24B4A);
    if (pct >= 75) return const Color(0xFFF59E0B);
    return AppColors.positiveDark;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              budget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: budget.labelColor ?? AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              _fmtSpent(budget.spentCents),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: budget.progress.clamp(0.0, 1.0),
                backgroundColor: AppColors.surfaceMuted,
                valueColor: AlwaysStoppedAnimation<Color>(_progressColor),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${budget.percentUsed}% of ${_fmtLimit(budget.limitCents)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "+ Add" tile that appears at the end of the budget grid.
class AddBudgetCard extends StatelessWidget {
  const AddBudgetCard({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        height: 90,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.borderDashed, width: 0.5),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 14, color: AppColors.textTertiary),
            SizedBox(height: AppSpacing.xs),
            Text(
              'Add',
              style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
