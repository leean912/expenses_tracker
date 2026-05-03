import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../providers/home/home_state.dart';
import 'budget_card.dart';

/// Section showing all budgets in a 3-per-row grid.
/// Wraps to additional rows automatically. Last item is the "+ Add" card.
class BudgetGrid extends StatelessWidget {
  const BudgetGrid({
    super.key,
    required this.budgets,
    this.onManageTap,
    this.onBudgetTap,
    this.onAddTap,
  });

  final List<BudgetMini> budgets;
  final VoidCallback? onManageTap;
  final void Function(BudgetMini budget)? onBudgetTap;
  final VoidCallback? onAddTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text(
                  'Budgets',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                TextButton.icon(
                  onPressed: onManageTap,
                  label: const Text(
                    'Manage',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  icon: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: AppColors.accent,
                  ),
                  iconAlignment: IconAlignment.end,
                ),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: AppSpacing.sm,
              mainAxisSpacing: AppSpacing.sm,
              childAspectRatio: 1.5, // tweak if cards feel too tall/short
            ),
            itemCount: budgets.length + 1, // +1 for the Add tile
            itemBuilder: (context, index) {
              if (index == budgets.length) {
                return AddBudgetCard(onTap: onAddTap);
              }
              final budget = budgets[index];
              return BudgetCard(
                budget: budget,
                onTap: onBudgetTap == null ? null : () => onBudgetTap!(budget),
              );
            },
          ),
        ],
      ),
    );
  }
}
