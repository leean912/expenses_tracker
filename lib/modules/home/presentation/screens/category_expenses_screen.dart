import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/receipt_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../service_locator.dart';
import '../../../expenses/presentation/widgets/edit_expense_sheet.dart';
import '../../providers/home/category_expenses_provider.dart';
import '../../providers/home/home_state.dart';
import '../widgets/expense_tile.dart';

class CategoryExpensesRouteArgs {
  const CategoryExpensesRouteArgs({
    required this.filter,
    required this.budget,
  });

  final HomeFilter filter;
  final BudgetMini budget;
}

class CategoryExpensesScreen extends ConsumerStatefulWidget {
  const CategoryExpensesScreen({
    super.key,
    required this.filter,
    required this.budget,
  });

  final HomeFilter filter;
  final BudgetMini budget;

  @override
  ConsumerState<CategoryExpensesScreen> createState() =>
      _CategoryExpensesScreenState();
}

class _CategoryExpensesScreenState
    extends ConsumerState<CategoryExpensesScreen> {
  (HomeFilter, String?) get _providerKey => (
        widget.filter,
        widget.budget.categoryId,
      );

  String get _periodLabel {
    switch (widget.filter.period) {
      case TimePeriod.today:
        return 'Today';
      case TimePeriod.week:
        return 'This week';
      case TimePeriod.month:
        return 'This month';
      case TimePeriod.year:
        return 'This year';
      case TimePeriod.custom:
        return 'Custom range';
    }
  }

  Future<void> _deleteExpense(String id) async {
    final row = await supabase
        .from('expenses')
        .select('receipt_url')
        .eq('id', id)
        .maybeSingle();
    final receiptUrl = row?['receipt_url'] as String?;
    if (receiptUrl != null) {
      ReceiptUploadService.deleteByUrl(receiptUrl);
    }
    await supabase
        .from('expenses')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
    ref.invalidate(categoryExpensesProvider(_providerKey));
  }

  @override
  Widget build(BuildContext context) {
    final budget = widget.budget;
    final expensesAsync = ref.watch(categoryExpensesProvider(_providerKey));
    final expenses = expensesAsync.valueOrNull;
    final isLoading = expensesAsync.isLoading;
    final hasError = expensesAsync.hasError && expenses == null;

    final progress = budget.progress.clamp(0.0, 1.0);
    final isOver = budget.progress > 1.0;
    const overColor = Color(0xFFD93025);
    final progressColor = isOver ? overColor : budget.barColor;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.accent,
          onRefresh: () async {
            ref.invalidate(categoryExpensesProvider(_providerKey));
            await ref.read(categoryExpensesProvider(_providerKey).future);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.background,
                surfaceTintColor: Colors.transparent,
                scrolledUnderElevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  onPressed: () => context.pop(),
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      budget.label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      _periodLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              if (isLoading)
                const SliverToBoxAdapter(
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: AppColors.surfaceMuted,
                    color: AppColors.accent,
                  ),
                ),

              // Budget summary card
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatAmount(budget.spentCents),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: isOver
                                    ? overColor
                                    : AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'of ${_formatAmount(budget.limitCents)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: AppColors.surfaceMuted,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(progressColor),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isOver
                              ? 'Over budget by ${_formatAmount(budget.spentCents - budget.limitCents)}'
                              : '${_formatAmount(budget.limitCents - budget.spentCents)} remaining · ${budget.percentUsed}% used',
                          style: TextStyle(
                            fontSize: 12,
                            color: isOver
                                ? overColor
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Failed to load expenses.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => ref.invalidate(
                              categoryExpensesProvider(_providerKey)),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (expenses != null && expenses.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No expenses in this period.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else if (expenses != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ExpenseListCard(
                      expenses: expenses,
                      timePeriod: widget.filter.period,
                      onTileTap: (e) {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => EditExpenseSheet(
                            expenseId: e.id,
                            onSaved: () => ref.invalidate(
                                categoryExpensesProvider(_providerKey)),
                          ),
                        );
                      },
                      onDelete: _deleteExpense,
                    ),
                  ),
                )
              else if (isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  String _formatAmount(int cents) {
    final rm = cents / 100;
    final parts = rm.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final decPart = parts[1];
    final buffer = StringBuffer();
    int count = 0;
    for (int i = intPart.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
      count++;
    }
    return 'RM ${buffer.toString().split('').reversed.join()}.$decPart';
  }
}
