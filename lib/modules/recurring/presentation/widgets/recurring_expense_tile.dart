import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/recurring_expense_model.dart';
import 'frequency_selector.dart';

class RecurringExpenseTile extends StatelessWidget {
  const RecurringExpenseTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
    this.isLocked = false,
  });

  final RecurringExpenseModel item;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    final isIncome = item.type == 'income';
    final color = isIncome ? AppColors.positiveDark : AppColors.expenseLight;

    return Opacity(
      opacity: isLocked ? 0.5 : 1.0,
      child: Dismissible(
        key: Key(item.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async => await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text(
              'Delete recurring?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            content: const Text(
              'Future occurrences will stop. Past expenses are kept.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => ctx.pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => ctx.pop(true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Color(0xFFE24B4A)),
                ),
              ),
            ],
          ),
        ),
        onDismissed: (_) => onDelete(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: AppSpacing.xl),
          color: const Color(0xFFE24B4A),
          child: const Icon(
            Icons.delete_outline_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.lg,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.repeat_rounded,
                    size: 20,
                    color: color,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: item.isActive
                                    ? AppColors.textPrimary
                                    : AppColors.textTertiary,
                              ),
                            ),
                          ),
                          Text(
                            'RM ${(item.amountCents / 100).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: item.isActive ? color : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _FreqBadge(freqLabel(item.frequency)),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'Next: ${_nextRunLabel(item.nextRunAt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                if (isLocked)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: const Text(
                      'Premium',
                      style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                    ),
                  )
                else
                  Switch.adaptive(
                    value: item.isActive,
                    onChanged: onToggle,
                    activeTrackColor: AppColors.accent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FreqBadge extends StatelessWidget {
  const _FreqBadge(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
      ),
    );
  }
}

String _nextRunLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(date.year, date.month, date.day);
  if (d == today) return 'Today';
  if (d == today.add(const Duration(days: 1))) return 'Tomorrow';
  return DateFormat('d MMM yyyy').format(date);
}
