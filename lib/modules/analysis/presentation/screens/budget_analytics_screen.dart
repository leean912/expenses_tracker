import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/upgrade_sheet.dart';
import '../../../settings/expense_type/providers/expense_type_provider.dart';
import '../../../subscription/providers/subscription_provider.dart';
import '../../providers/analysis_provider.dart';
import '../../providers/analysis_state.dart';
import '../widgets/budget_vs_actual_card.dart';

const _budgetPeriods = [
  AnalysisPeriod.day,
  AnalysisPeriod.week,
  AnalysisPeriod.month,
  AnalysisPeriod.year,
];

class BudgetAnalyticsScreen extends ConsumerStatefulWidget {
  const BudgetAnalyticsScreen({super.key});

  @override
  ConsumerState<BudgetAnalyticsScreen> createState() =>
      _BudgetAnalyticsScreenState();
}

class _BudgetAnalyticsScreenState extends ConsumerState<BudgetAnalyticsScreen> {
  AnalysisPeriod _selectedPeriod = AnalysisPeriod.month;
  bool? _useActualAmount;

  AnalysisFilter _buildFilter(bool useActualAmount) => AnalysisFilter(
    period: _selectedPeriod,
    includeCollabExpenses: true,
    useActualAmount: useActualAmount,
  );

  String _dateRangeLabel(AnalysisFilter filter) {
    final (start, end) = filter.toDateRange();
    final s = DateTime.parse(start);
    final e = DateTime.parse(end);
    String fmt(DateTime d) => '${d.day} ${_monthShort(d.month)} ${d.year}';
    return '${fmt(s)} – ${fmt(e)}';
  }

  String _monthShort(int m) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][m - 1];

  @override
  Widget build(BuildContext context) {
    final expenseTypeAsync = ref.watch(expenseTypeProvider);
    final effectiveUseActual =
        _useActualAmount ?? (expenseTypeAsync.valueOrNull == ExpenseType.actual);
    final filter = _buildFilter(effectiveUseActual);

    final analysisAsync = ref.watch(analysisDataProvider(filter));
    final data = analysisAsync.valueOrNull;
    final isLoading = analysisAsync.isLoading;
    final hasError = analysisAsync.hasError && data == null;
    final isPremium = ref.watch(isPremiumProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.accent,
          onRefresh: () => ref.refresh(analysisDataProvider(filter).future),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                backgroundColor: AppColors.background,
                surfaceTintColor: Colors.transparent,
                scrolledUnderElevation: 0,
                leading: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_rounded,
                    size: 18,
                    color: AppColors.textPrimary,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                flexibleSpace: const FlexibleSpaceBar(
                  title: Text(
                    'Budget Pace',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  centerTitle: true,
                ),
                pinned: true,
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                    ),
                    child: Row(
                      children: [
                        for (final period in _budgetPeriods) ...[
                          _PeriodChip(
                            label: period.label,
                            isSelected: period == _selectedPeriod,
                            isLocked: period == AnalysisPeriod.year && !isPremium,
                            onTap: () {
                              if (period == AnalysisPeriod.year && !isPremium) {
                                UpgradeSheet.show(
                                  context,
                                  title: 'Yearly budget analysis',
                                  description: 'View your yearly budget pace with Premium.',
                                );
                                return;
                              }
                              setState(() => _selectedPeriod = period);
                            },
                          ),
                          if (period != _budgetPeriods.last)
                            const SizedBox(width: AppSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      Text(
                        _dateRangeLabel(filter),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      _AmountToggle(
                        useActualAmount: effectiveUseActual,
                        onChanged: (v) => setState(() => _useActualAmount = v),
                      ),
                    ],
                  ),
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

              if (hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Failed to load data.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(analysisDataProvider(filter)),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (data == null && isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (data != null && data.budgetProgress.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'No budgets set for this period.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Go to Budgets to set spending limits.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (data != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.sm,
                      AppSpacing.xl,
                      0,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(color: AppColors.border, width: 0.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Budget vs Actual',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          const Text(
                            'Compare your set budget limits against real spending. Red means over budget.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          BudgetVsActualCard(
                            budgets: data.budgetProgress,
                            isPremium: isPremium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountToggle extends StatelessWidget {
  const _AmountToggle({required this.useActualAmount, required this.onChanged});

  final bool useActualAmount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToggleChip(
          label: 'Total',
          selected: !useActualAmount,
          onTap: () => onChanged(false),
        ),
        const SizedBox(width: 6),
        _ToggleChip(
          label: 'Actual',
          selected: useActualAmount,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: selected
              ? null
              : Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            color: selected ? AppColors.accentText : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isLocked = false,
  });

  final String label;
  final bool isSelected;
  final bool isLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                color: isLocked
                    ? AppColors.textTertiary
                    : isSelected
                        ? AppColors.accentText
                        : AppColors.textSecondary,
              ),
            ),
            if (isLocked) ...[
              const SizedBox(width: 4),
              const Icon(Icons.lock_rounded, size: 10, color: AppColors.textTertiary),
            ],
          ],
        ),
      ),
    );
  }
}
