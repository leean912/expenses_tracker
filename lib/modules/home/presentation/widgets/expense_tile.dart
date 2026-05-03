import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../providers/home/home_state.dart';

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
                    : AppColors.expenseLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders expenses grouped by date, each group in its own rounded card.
/// Supports swipe-to-delete with a confirmation dialog.
class ExpenseListCard extends StatelessWidget {
  const ExpenseListCard({
    super.key,
    required this.expenses,
    this.timePeriod = TimePeriod.month,
    this.onTileTap,
    this.onDelete,
  });

  final List<ExpenseTileData> expenses;
  final TimePeriod timePeriod;
  final void Function(ExpenseTileData expense)? onTileTap;
  final Future<void> Function(String id)? onDelete;

  bool get _groupByMonth => timePeriod == TimePeriod.year;

  String _formatHeader(DateTime date) {
    if (_groupByMonth) {
      return DateFormat('MMMM yyyy').format(date);
    }
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final yesterday = todayDate.subtract(const Duration(days: 1));
    if (date == todayDate) return 'Today';
    if (date == yesterday) return 'Yesterday';
    return DateFormat('EEE, d MMM').format(date);
  }

  /// Groups expenses preserving the existing sort order.
  List<(DateTime, List<ExpenseTileData>)> _group(List<ExpenseTileData> list) {
    final Map<DateTime, List<ExpenseTileData>> map = {};
    final List<DateTime> order = [];
    for (final e in list) {
      final key = _groupByMonth
          ? DateTime(e.date.year, e.date.month)
          : DateTime(e.date.year, e.date.month, e.date.day);
      if (!map.containsKey(key)) {
        order.add(key);
        map[key] = [];
      }
      map[key]!.add(e);
    }
    return [for (final d in order) (d, map[d]!)];
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: SizedBox(
          height: 100,
          child: Center(
            child: Text(
              'No expenses',
              style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final groups = _group(expenses);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (date, group) in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.sm,
            ),
            child: Text(
              _formatHeader(date),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Padding(
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
                  for (int i = 0; i < group.length; i++) ...[
                    Dismissible(
                      key: Key(group[i].id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => _confirmDelete(context),
                      onDismissed: (_) => onDelete?.call(group[i].id),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: AppSpacing.xl),
                        color: Colors.red,
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                        ),
                      ),
                      child: ExpenseTile(
                        expense: group[i],
                        onTap: onTileTap == null
                            ? null
                            : () => onTileTap!(group[i]),
                      ),
                    ),
                    if (i < group.length - 1)
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
          ),
        ],
      ],
    );
  }
}
