import 'package:flutter/material.dart';

/// Time period filter for the expense list.
enum TimePeriod { today, week, month, year, custom }

/// Provider family key: a period + optional custom date range.
/// Custom dates are only set when [period] == [TimePeriod.custom].
class HomeFilter {
  const HomeFilter({required this.period, this.customStart, this.customEnd});

  final TimePeriod period;
  final DateTime? customStart;
  final DateTime? customEnd;

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  (String start, String end) toDateRange() {
    if (period == TimePeriod.custom &&
        customStart != null &&
        customEnd != null) {
      return (_iso(customStart!), _iso(customEnd!));
    }
    return period.toDateRange();
  }

  @override
  bool operator ==(Object other) =>
      other is HomeFilter &&
      other.period == period &&
      other.customStart == customStart &&
      other.customEnd == customEnd;

  @override
  int get hashCode => Object.hash(period, customStart, customEnd);
}

extension TimePeriodLabel on TimePeriod {
  String get label {
    switch (this) {
      case TimePeriod.today:
        return 'Today';
      case TimePeriod.week:
        return 'Week';
      case TimePeriod.month:
        return 'Month';
      case TimePeriod.year:
        return 'Year';
      case TimePeriod.custom:
        return 'Custom';
    }
  }
}

extension TimePeriodRange on TimePeriod {
  /// Returns (start, end) as ISO-8601 date strings (YYYY-MM-DD).
  (String start, String end) toDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    late DateTime start;
    late DateTime end;

    switch (this) {
      case TimePeriod.today:
        start = today;
        end = today;
      case TimePeriod.week:
        start = today.subtract(Duration(days: today.weekday - 1));
        end = start.add(const Duration(days: 6));
      case TimePeriod.month:
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0);
      case TimePeriod.year:
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year, 12, 31);
      case TimePeriod.custom:
        // Callers should use a separate date-range parameter for custom.
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0);
    }

    return (_fmt(start), _fmt(end));
  }

  /// Returns the equivalent range for the immediately preceding period.
  (String start, String end) toPreviousDateRange() {
    final now = DateTime.now();

    switch (this) {
      case TimePeriod.today:
        final d = DateTime(now.year, now.month, now.day - 1);
        final s = _fmt(d);
        return (s, s);
      case TimePeriod.week:
        final thisMonday = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: now.weekday - 1));
        return (
          _fmt(thisMonday.subtract(const Duration(days: 7))),
          _fmt(thisMonday.subtract(const Duration(days: 1))),
        );
      case TimePeriod.month:
        return (
          _fmt(DateTime(now.year, now.month - 1, 1)),
          _fmt(DateTime(now.year, now.month, 0)),
        );
      case TimePeriod.year:
        return ('${now.year - 1}-01-01', '${now.year - 1}-12-31');
      case TimePeriod.custom:
        return toDateRange();
    }
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Aggregated analytics for the top banner.
///
/// In production, populate from a Supabase RPC or computed query.
class AnalyticsSummary {
  const AnalyticsSummary({
    required this.totalSpentCents,
    // required this.changePercent, // negative = spent less than last month
    required this.avgPerDayCents,
    required this.topCategory,
    required this.changeVsLastMonthCents,
  });

  final int totalSpentCents;
  // final double changePercent;
  final int avgPerDayCents;
  final String topCategory;
  final int changeVsLastMonthCents;
}

/// A budget card for the grid.
///
/// Maps from the `budgets` table joined with summed expenses for the period.
class BudgetMini {
  const BudgetMini({
    required this.id,
    required this.label,
    required this.spentCents,
    required this.limitCents,
    required this.barColor,
    this.labelColor,
    this.isOverall = false,
  });

  final String id;
  final String label;
  final int spentCents;
  final int limitCents;
  final Color barColor;
  final Color? labelColor;
  final bool isOverall;

  double get progress =>
      limitCents == 0 ? 0 : (spentCents / limitCents).clamp(0, 1.5);

  int get percentUsed => (progress * 100).round();
}

/// One row in the expense list.
///
/// Maps from `expenses` table; category metadata joined.
class ExpenseTileData {
  const ExpenseTileData({
    required this.id,
    required this.title,
    required this.amountCents,
    required this.isIncome,
    required this.categoryName,
    required this.categoryLight,
    required this.categoryDark,
    required this.date,
    this.accountName,
  });

  final String id;
  final String title;
  final int amountCents; // always positive; sign decided by isIncome
  final bool isIncome;
  final String categoryName;
  final Color categoryLight;
  final Color categoryDark;
  final DateTime date;
  final String? accountName;
}
