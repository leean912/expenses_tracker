import 'package:flutter/material.dart';

enum AnalysisPeriod { week, month, year, custom }

class AnalysisFilter {
  const AnalysisFilter({
    required this.period,
    this.customStart,
    this.customEnd,
    this.includeCollabExpenses = true,
  });

  final AnalysisPeriod period;
  final DateTime? customStart;
  final DateTime? customEnd;
  final bool includeCollabExpenses;

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  (String start, String end) toDateRange() {
    if (period == AnalysisPeriod.custom &&
        customStart != null &&
        customEnd != null) {
      return (_iso(customStart!), _iso(customEnd!));
    }
    return period.toDateRange();
  }

  @override
  bool operator ==(Object other) =>
      other is AnalysisFilter &&
      other.period == period &&
      other.customStart == customStart &&
      other.customEnd == customEnd &&
      other.includeCollabExpenses == includeCollabExpenses;

  @override
  int get hashCode =>
      Object.hash(period, customStart, customEnd, includeCollabExpenses);
}

extension AnalysisPeriodLabel on AnalysisPeriod {
  String get label => switch (this) {
        AnalysisPeriod.week => 'Week',
        AnalysisPeriod.month => 'Month',
        AnalysisPeriod.year => 'Year',
        AnalysisPeriod.custom => 'Custom',
      };

  String get budgetPeriod => switch (this) {
        AnalysisPeriod.week => 'weekly',
        AnalysisPeriod.year => 'yearly',
        _ => 'monthly',
      };
}

extension AnalysisPeriodRange on AnalysisPeriod {
  (String start, String end) toDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    late DateTime start;
    late DateTime end;

    switch (this) {
      case AnalysisPeriod.week:
        start = today.subtract(Duration(days: today.weekday - 1));
        end = start.add(const Duration(days: 6));
      case AnalysisPeriod.month:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0);
      case AnalysisPeriod.year:
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, 12, 31);
      case AnalysisPeriod.custom:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0);
    }

    return (_fmt(start), _fmt(end));
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

// ── Data models ───────────────────────────────────────────────────────────────

class CategorySpend {
  const CategorySpend({
    required this.categoryId,
    required this.categoryName,
    required this.color,
    required this.totalCents,
    required this.percentage,
  });

  final String categoryId;
  final String categoryName;
  final Color color;
  final int totalCents;
  final double percentage;
}

class PeriodBucket {
  const PeriodBucket({
    required this.label,
    required this.spendCents,
    required this.incomeCents,
  });

  final String label;
  final int spendCents;
  final int incomeCents;
}

class BudgetProgress {
  const BudgetProgress({
    required this.label,
    required this.spentCents,
    required this.limitCents,
    required this.barColor,
  });

  final String label;
  final int spentCents;
  final int limitCents;
  final Color barColor;

  double get progress =>
      limitCents == 0 ? 0 : (spentCents / limitCents).clamp(0.0, 1.5);
  int get percentUsed => (progress * 100).clamp(0, 999).round();
}

class DailyPoint {
  const DailyPoint({required this.date, required this.cumulativeCents});

  final DateTime date;
  final int cumulativeCents;
}

class AnalysisData {
  const AnalysisData({
    required this.categoryBreakdown,
    required this.periodBreakdown,
    required this.budgetProgress,
    required this.cumulativeTrend,
    required this.totalSpentCents,
    required this.totalIncomeCents,
  });

  final List<CategorySpend> categoryBreakdown;
  final List<PeriodBucket> periodBreakdown;
  final List<BudgetProgress> budgetProgress;
  final List<DailyPoint> cumulativeTrend;
  final int totalSpentCents;
  final int totalIncomeCents;
}
