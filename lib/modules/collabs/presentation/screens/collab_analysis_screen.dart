import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/upgrade_sheet.dart';
import '../../../analysis/presentation/widgets/category_pie_chart.dart';
import '../../../subscription/providers/subscription_provider.dart';
import '../../data/models/collab_model.dart';
import '../../providers/collab_analysis_provider.dart';
import '../widgets/collab_cumulative_line_chart.dart';
import '../widgets/collab_spending_bar_chart.dart';

class CollabAnalysisScreen extends ConsumerStatefulWidget {
  const CollabAnalysisScreen({super.key, required this.collab});

  final CollabModel collab;

  @override
  ConsumerState<CollabAnalysisScreen> createState() =>
      _CollabAnalysisScreenState();
}

class _CollabAnalysisScreenState extends ConsumerState<CollabAnalysisScreen> {
  DateTimeRange? _customRange;

  CollabModel get collab => widget.collab;

  DateTime get _defaultStart {
    final now = DateTime.now();
    return collab.startDate ?? DateTime(now.year, now.month, 1);
  }

  DateTime get _defaultEnd {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final candidate = collab.endDate != null && collab.endDate!.isBefore(today)
        ? collab.endDate!
        : today;
    return candidate.isBefore(_defaultStart) ? _defaultStart : candidate;
  }

  CollabAnalysisFilter get _filter => CollabAnalysisFilter(
        collabId: collab.id,
        defaultStart: _defaultStart,
        defaultEnd: _defaultEnd,
        customStart: _customRange?.start,
        customEnd: _customRange?.end,
      );

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String get _dateRangeLabel {
    final start = _filter.effectiveStart;
    final end = _filter.effectiveEnd;
    return '${_fmtDate(start)} – ${_fmtDate(end)}';
  }

  Future<void> _pickCustomDate(bool isPremium) async {
    if (!isPremium) {
      await UpgradeSheet.show(
        context,
        title: 'Custom Date Range',
        description:
            'Upgrade to Premium to filter collab analytics by a custom date range.',
      );
      return;
    }

    final now = DateTime.now();
    final firstDate = DateTime(2020);
    DateTime clamp(DateTime d) =>
        d.isBefore(firstDate) ? firstDate : (d.isAfter(now) ? now : d);
    final safeStart = clamp(_defaultStart);
    final safeEnd =
        clamp(_defaultEnd).isBefore(safeStart) ? safeStart : clamp(_defaultEnd);

    final range = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      initialDateRange:
          _customRange ?? DateTimeRange(start: safeStart, end: safeEnd),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme:
              Theme.of(context).colorScheme.copyWith(primary: AppColors.accent),
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
    setState(() => _customRange = range);
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(isPremiumProvider);
    final analysisAsync = ref.watch(collabAnalysisProvider(_filter));
    final data = analysisAsync.valueOrNull;
    final isLoading = analysisAsync.isLoading;
    final hasError = analysisAsync.hasError && data == null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: AppColors.textPrimary,
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Analytics',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          if (_customRange != null)
            IconButton(
              tooltip: 'Reset date range',
              icon: const Icon(
                Icons.restart_alt_rounded,
                size: 20,
                color: AppColors.textTertiary,
              ),
              onPressed: () => setState(() => _customRange = null),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () => ref.refresh(collabAnalysisProvider(_filter).future),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Date filter chip ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  0,
                ),
                child: _FilterChip(
                  icon: isPremium
                      ? Icons.calendar_today_rounded
                      : Icons.lock_rounded,
                  label: _dateRangeLabel,
                  isActive: _customRange != null,
                  isPremiumLocked: !isPremium,
                  onTap: () => _pickCustomDate(isPremium),
                ),
              ),
            ),

            if (isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: AppSpacing.md),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: AppColors.surfaceMuted,
                    color: AppColors.accent,
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
                        'Failed to load analytics.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(collabAnalysisProvider(_filter)),
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
              if (data.totalSpentCents == 0 && data.totalIncomeCents == 0)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No expenses in this period.',
                      style: TextStyle(color: AppColors.textTertiary),
                    ),
                  ),
                )
              else
                ..._buildAnalysisView(data, collab.homeCurrency),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAnalysisView(CollabAnalysisData data, String currency) {
    return [
      // Summary chips
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            0,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: AppSpacing.md,
              children: [
                _SummaryChip(
                  label: 'Total Spent',
                  value: '$currency ${_fmtCents(data.totalSpentCents)}',
                  color: AppColors.expenseLight,
                ),
                if (data.totalIncomeCents > 0)
                  _SummaryChip(
                    label: 'Income',
                    value: '$currency ${_fmtCents(data.totalIncomeCents)}',
                    color: AppColors.positiveDark,
                  ),
                ...data.memberPeriodSeries.map((s) {
                  final memberTotal = s.spendCentsByBucket.fold(0, (a, b) => a + b);
                  return _SummaryChip(
                    label: s.displayName,
                    value: '$currency ${_fmtCents(memberTotal)}',
                    color: s.color,
                  );
                }),
              ],
            ),
          ),
        ),
      ),

      // Spending by Category (self only)
      if (data.selfCategoryBreakdown.isNotEmpty)
        _ChartSectionSliver(
          title: 'Spending by Category',
          subtitle: 'Your expenses',
          child: CategoryPieChart(categories: data.selfCategoryBreakdown),
        ),

      // Spending by Account (self only)
      if (data.selfAccountBreakdown.isNotEmpty)
        _ChartSectionSliver(
          title: 'Spending by Account',
          subtitle: 'Your expenses',
          child: CategoryPieChart(categories: data.selfAccountBreakdown),
        ),

      // Spending Over Time (daily grouped by member)
      if (data.bucketDates.isNotEmpty && data.memberPeriodSeries.isNotEmpty)
        _ChartSectionSliver(
          title: 'Spending Over Time',
          showSwipeHint: true,
          child: CollabSpendingBarChart(
            bucketDates: data.bucketDates,
            series: data.memberPeriodSeries,
          ),
        ),

      // Cumulative Spending (line chart per member)
      if (data.bucketDates.isNotEmpty && data.memberPeriodSeries.isNotEmpty)
        _ChartSectionSliver(
          title: 'Cumulative Spending',
          showSwipeHint: true,
          child: CollabCumulativeLineChart(
            bucketDates: data.bucketDates,
            series: data.memberPeriodSeries,
          ),
        ),
    ];
  }

  String _fmtCents(int cents) => (cents / 100).toStringAsFixed(2);
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isPremiumLocked,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final bool isPremiumLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.accent.withValues(alpha: 0.1)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: isActive ? AppColors.accent : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Icon(
              icon,
              size: 13,
              color: isActive
                  ? AppColors.accent
                  : isPremiumLocked
                  ? AppColors.textTertiary
                  : AppColors.textSecondary,
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
            if (isPremiumLocked)
              const Text(
                'Premium',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.budgetOverallBar,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Chart section card ────────────────────────────────────────────────────────

class _ChartSectionSliver extends StatelessWidget {
  const _ChartSectionSliver({
    required this.title,
    required this.child,
    this.subtitle,
    this.showSwipeHint = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool showSwipeHint;

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
            spacing: AppSpacing.xl,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                spacing: AppSpacing.sm,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
              child,
              if (showSwipeHint)
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 4,
                  children: [
                    Icon(
                      Icons.swipe_rounded,
                      size: 12,
                      color: AppColors.textTertiary,
                    ),
                    Text(
                      'Swipe to see more',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Summary chip ──────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
