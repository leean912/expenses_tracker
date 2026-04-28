import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../screens/home_state.dart';

/// One expense row.
/// No leading icon — relies on category tag for visual identity.
class ExpenseTile extends StatelessWidget {
  const ExpenseTile({super.key, required this.expense, this.onTap});

  final ExpenseTileData expense;
  final VoidCallback? onTap;

  String _fmtAmount(int cents, {required bool isIncome}) {
    final value = (cents / 100).abs();
    final whole = value.toStringAsFixed(2);
    final parts = whole.split('.');
    final intPart = parts[0];
    final formatted = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) formatted.write(',');
      formatted.write(intPart[i]);
    }
    return '${isIncome ? "+" : "−"}RM $formatted.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: expense.categoryLight,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          expense.categoryName,
                          style: TextStyle(
                            fontSize: 11,
                            color: expense.categoryDark,
                          ),
                        ),
                      ),
                      if (expense.accountName != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            expense.accountName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Text(
              _fmtAmount(expense.amountCents, isIncome: expense.isIncome),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: expense.isIncome
                    ? AppColors.incomeDark
                    : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Container that wraps a list of expense tiles in a single rounded card.
class ExpenseListCard extends StatelessWidget {
  const ExpenseListCard({super.key, required this.expenses, this.onTileTap});

  final List<ExpenseTileData> expenses;
  final void Function(ExpenseTileData expense)? onTileTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (int i = 0; i < expenses.length; i++) ...[
              ExpenseTile(
                expense: expenses[i],
                onTap: onTileTap == null ? null : () => onTileTap!(expenses[i]),
              ),
              if (i < expenses.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Container(height: 0.5, color: AppColors.border),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
