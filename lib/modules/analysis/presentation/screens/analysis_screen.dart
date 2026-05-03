import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../providers/analysis_provider.dart';
import '../../providers/analysis_state.dart';
import '../widgets/analysis_filter_chips.dart';
import '../widgets/budget_vs_actual_card.dart';
import '../widgets/category_pie_chart.dart';
import '../widgets/cumulative_line_chart.dart';
import '../widgets/spending_bar_chart.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  AnalysisPeriod _selectedPeriod = AnalysisPeriod.month;
  DateTimeRange? _customRange;

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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              backgroundColor: AppColors.background,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              flexibleSpace: const FlexibleSpaceBar(title: Text('Analysis')),
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
                  AppSpacing.sm,
                  AppSpacing.xl,
                  0,
                ),
                child: Text(
                  _dateRangeLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
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
                title: 'Spending Over Time',
                description:
                    'How much you spent per period bucket. Income bars appear in green when recorded.',
                child: SpendingBarChart(buckets: data.periodBreakdown),
              ),

              if (data.budgetProgress.isNotEmpty)
                _ChartSection(
                  title: 'Budget vs Actual',
                  description:
                      'Compare your set budget limits against real spending. Red means over budget.',
                  child: BudgetVsActualCard(budgets: data.budgetProgress),
                ),

              _ChartSection(
                title: 'Cumulative Trend',
                description:
                    'Your running total spend growing day by day — useful for spotting heavy-spending stretches.',
                child: CumulativeLineChart(points: data.cumulativeTrend),
              ),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _ChartSection extends StatelessWidget {
  const _ChartSection({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
