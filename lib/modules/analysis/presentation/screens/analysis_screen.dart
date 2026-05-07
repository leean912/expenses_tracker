import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../subscription/providers/subscription_provider.dart';
import '../../providers/analysis_provider.dart';
import '../../providers/analysis_state.dart';
import '../widgets/analysis_filter_chips.dart';
import '../widgets/budget_vs_actual_card.dart';
import '../widgets/category_pie_chart.dart';
import '../widgets/spending_bar_chart.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  AnalysisPeriod _selectedPeriod = AnalysisPeriod.month;
  DateTimeRange? _customRange;
  bool _includeCollabExpenses = true;

  String get _dateRangeLabel {
    final (start, end) = _filter.toDateRange();
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

  AnalysisFilter get _filter => AnalysisFilter(
    period: _selectedPeriod,
    customStart: _customRange?.start,
    customEnd: _customRange?.end,
    includeCollabExpenses: _includeCollabExpenses,
  );

  Future<void> _onPeriodSelected(AnalysisPeriod period) async {
    if (period == AnalysisPeriod.custom) {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2026),
        lastDate: now,
        initialEntryMode: DatePickerEntryMode.calendarOnly,
        initialDateRange:
            _customRange ??
            DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
        builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: AppColors.accent),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: SizedBox(
                  width: double.infinity,
                  height: MediaQuery.sizeOf(context).height * 0.7,
                  child: child!,
                ),
              ),
            ),
          ),
        ),
        saveText: 'Apply',
      );
      if (range == null || !mounted) return;
      setState(() {
        _selectedPeriod = AnalysisPeriod.custom;
        _customRange = range;
      });
    } else {
      setState(() {
        _selectedPeriod = period;
        _customRange = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final analysisAsync = ref.watch(analysisDataProvider(_filter));
    final data = analysisAsync.valueOrNull;
    final isLoading = analysisAsync.isLoading;
    final hasError = analysisAsync.hasError && data == null;
    final isPremium = ref.watch(isPremiumProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(analysisDataProvider(_filter).future),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                backgroundColor: AppColors.background,
                surfaceTintColor: Colors.transparent,
                scrolledUnderElevation: 0,
                flexibleSpace: const FlexibleSpaceBar(
                  title: Text(
                    'Analysis',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  centerTitle: false,
                ),
                pinned: true,
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: AnalysisFilterChips(
                    selected: _selectedPeriod,
                    onSelected: _onPeriodSelected,
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
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dateRangeLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(
                          () =>
                              _includeCollabExpenses = !_includeCollabExpenses,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: Checkbox(
                                value: _includeCollabExpenses,
                                onChanged: (v) => setState(
                                  () => _includeCollabExpenses = v ?? false,
                                ),
                                activeColor: AppColors.accent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                side: const BorderSide(
                                  color: AppColors.textTertiary,
                                  width: 1.5,
                                ),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Include collabs',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
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
                              ref.invalidate(analysisDataProvider(_filter)),
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
              else if (data != null) ...[
                _ChartSection(
                  title: 'Spending by Category',
                  description:
                      'Where your money goes — tap a slice to see the exact amount and share for each category.',
                  child: CategoryPieChart(
                    categories: data.categoryBreakdown,
                    totalCents: data.totalSpentCents,
                  ),
                ),

                _ChartSection(
                  title: 'Spending by Account',
                  description:
                      'Which account you spend from the most — tap a slice to see amount and share.',
                  child: CategoryPieChart(
                    categories: data.accountBreakdown,
                    totalCents: data.totalSpentCents,
                  ),
                ),

                if (_selectedPeriod != AnalysisPeriod.day)
                  _ChartSection(
                    title: switch (_selectedPeriod) {
                      AnalysisPeriod.week => 'Daily Spending',
                      AnalysisPeriod.year => 'Monthly Spending',
                      _ => 'Weekly Spending',
                    },
                    description: 'How much you spent per period bucket.',
                    child: SpendingBarChart(buckets: data.periodBreakdown),
                  ),

                if (data.budgetProgress.isNotEmpty)
                  _ChartSection(
                    title: 'Budget vs Actual',
                    description:
                        'Compare your set budget limits against real spending. Red means over budget.',
                    collapsedChild: BudgetVsActualCard(
                      budgets: data.budgetProgress,
                      isPremium: isPremium,
                      showPaceCharts: false,
                    ),
                    child: BudgetVsActualCard(
                      budgets: data.budgetProgress,
                      isPremium: isPremium,
                    ),
                  ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartSection extends StatefulWidget {
  const _ChartSection({
    required this.title,
    required this.description,
    required this.child,
    this.collapsedChild,
  });

  final String title;
  final String description;
  final Widget child;
  final Widget? collapsedChild;

  @override
  State<_ChartSection> createState() => _ChartSectionState();
}

class _ChartSectionState extends State<_ChartSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: AnimatedRotation(
                      turns: _expanded ? 0 : 0.5,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: 20,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.description,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                  height: 1.4,
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: _expanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: AppSpacing.xl),
                          widget.child,
                        ],
                      )
                    : widget.collapsedChild != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.lg),
                        child: widget.collapsedChild,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
