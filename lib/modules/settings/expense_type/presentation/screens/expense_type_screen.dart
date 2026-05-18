import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../providers/expense_type_provider.dart';

class ExpenseTypeScreen extends ConsumerWidget {
  const ExpenseTypeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncType = ref.watch(expenseTypeProvider);
    final current = asyncType.valueOrNull ?? ExpenseType.total;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text(
          'Default Expense Type',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
            child: Text(
              'Choose which expense amount to display across the app.',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _OptionTile(
            title: 'Total Expenses',
            description:
                'Displays the full bill amount across the app. For example, if you split RM100 with friends, the app shows RM100 as your expense.',
            isSelected: current == ExpenseType.total,
            onTap: () => ref
                .read(expenseTypeProvider.notifier)
                .setType(ExpenseType.total),
          ),
          const Divider(height: 1, indent: 56, color: AppColors.border),
          _OptionTile(
            title: 'Actual Expenses',
            description:
                'Displays only your share across the app. For example, if you split RM100 and only owe RM10, the app shows RM10 as your expense.',
            isSelected: current == ExpenseType.actual,
            onTap: () => ref
                .read(expenseTypeProvider.notifier)
                .setType(ExpenseType.actual),
          ),
          const Divider(height: 1, color: AppColors.border),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.sm,
      ),
      leading: Icon(
        isSelected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: isSelected ? AppColors.accent : AppColors.textTertiary,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isSelected ? AppColors.accent : AppColors.textPrimary,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(
          description,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ),
      onTap: onTap,
    );
  }
}
