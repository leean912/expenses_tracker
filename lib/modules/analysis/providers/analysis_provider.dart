import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import 'analysis_state.dart';

final analysisDataProvider =
    FutureProvider.family<AnalysisData, AnalysisFilter>((ref, filter) async {
  final userId = supabase.auth.currentUser!.id;
  final (start, end) = filter.toDateRange();
  final startDate = DateTime.parse(start);
  final endDate = DateTime.parse(end);
  final budgetPeriod = filter.period.budgetPeriod;

  // RPC returns aggregated daily data — no 1000-row risk regardless of how
  // many expenses exist in the period.
  final results = await Future.wait<dynamic>([
    supabase.rpc('analysis_summary', params: {
      'p_start': start,
      'p_end': end,
      'p_include_collab': filter.includeCollabExpenses,
    }),
    budgetPeriod == null
        ? Future<dynamic>.value(<dynamic>[])
        : supabase
            .from('budgets')
            .select(
                'limit_cents, category_id, category:categories(name, color)')
            .eq('user_id', userId)
            .eq('period', budgetPeriod)
            .isFilter('deleted_at', null),
  ]);

  final rpc = results[0] as Map<String, dynamic>;
  final budgetRows = results[1] as List<dynamic>;

  // ── Parse RPC payload ──────────────────────────────────────────────────────

  int asInt(dynamic v) => (v as num? ?? 0).toInt();

  final totalSpentCents = asInt(rpc['total_spent_cents']);
  final totalActualCents = asInt(rpc['total_actual_cents']);
  final totalIncomeCents = asInt(rpc['total_income_cents']);

  final byCategoryRows = (rpc['by_category'] as List<dynamic>? ?? [])
      .cast<Map<String, dynamic>>();
  final byAccountRows = (rpc['by_account'] as List<dynamic>? ?? [])
      .cast<Map<String, dynamic>>();
  final dailyBuckets = (rpc['daily_buckets'] as List<dynamic>? ?? [])
      .cast<Map<String, dynamic>>();
  final dailyCatBuckets = (rpc['daily_category_buckets'] as List<dynamic>? ?? [])
      .cast<Map<String, dynamic>>();

  // ── Category breakdown ─────────────────────────────────────────────────────

  final catTotal = byCategoryRows.fold<int>(0, (s, r) {
    return s +
        (filter.useActualAmount ? asInt(r['actual_cents']) : asInt(r['total_cents']));
  });

  final categoryBreakdown = byCategoryRows.map((r) {
    final cents = filter.useActualAmount
        ? asInt(r['actual_cents'])
        : asInt(r['total_cents']);
    final color =
        _hexToColor(r['category_color'] as String?) ?? const Color(0xFF888780);
    return CategorySpend(
      categoryId: r['category_id'] as String? ?? '',
      categoryName: r['category_name'] as String? ?? 'Other',
      color: color,
      totalCents: cents,
      percentage: catTotal <= 0 ? 0 : cents / catTotal * 100,
    );
  }).where((c) => c.totalCents > 0).toList()
    ..sort((a, b) => b.totalCents.compareTo(a.totalCents));

  // ── Account breakdown ──────────────────────────────────────────────────────

  final accTotal = byAccountRows.fold<int>(0, (s, r) {
    return s +
        (filter.useActualAmount ? asInt(r['actual_cents']) : asInt(r['total_cents']));
  });

  final accountBreakdown = byAccountRows.indexed.map((entry) {
    final (i, r) = entry;
    final cents = filter.useActualAmount
        ? asInt(r['actual_cents'])
        : asInt(r['total_cents']);
    return CategorySpend(
      categoryId: r['account_id'] as String? ?? '',
      categoryName: r['account_name'] as String? ?? 'No Account',
      color: _accountPalette[i % _accountPalette.length],
      totalCents: cents,
      percentage: accTotal <= 0 ? 0 : cents / accTotal * 100,
    );
  }).where((a) => a.totalCents > 0).toList();

  // ── Period breakdown (bar chart) ──────────────────────────────────────────

  final periodBreakdown = _buildPeriodBuckets(
    dailyBuckets,
    startDate,
    endDate,
    filter.period,
    filter.useActualAmount,
  );

  // ── Budget progress + pace points ─────────────────────────────────────────

  final buildPace = filter.period != AnalysisPeriod.day &&
      filter.period != AnalysisPeriod.custom;
  final isYearly = filter.period == AnalysisPeriod.year;
  final totalDays = endDate.difference(startDate).inDays + 1;
  final bucketCount = isYearly ? ((totalDays - 1) ~/ 7) + 1 : totalDays;

  String paceLabel(int i) {
    if (isYearly) return 'W${i + 1}';
    final d = startDate.add(Duration(days: i));
    return totalDays <= 7
        ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]
        : '${d.day}';
  }

  int paceIndex(String dateStr) {
    final d = DateTime.parse(dateStr);
    final offset = d.difference(startDate).inDays;
    if (offset < 0) return -1;
    return isYearly
        ? (offset ~/ 7).clamp(0, bucketCount - 1)
        : (offset < bucketCount ? offset : -1);
  }

  List<SpendVsBudgetPoint> buildPacePoints(String? catId, int limitCents) {
    if (!buildPace) return const [];
    final buckets = List.filled(bucketCount, 0);

    if (catId == null) {
      // Overall budget — sum from the pre-aggregated daily totals.
      for (final r in dailyBuckets) {
        final idx = paceIndex(r['bucket_date'] as String);
        if (idx < 0) continue;
        buckets[idx] += filter.useActualAmount
            ? asInt(r['actual_cents'])
            : asInt(r['spend_cents']);
      }
    } else {
      // Category budget — use the per-category daily aggregates.
      for (final r in dailyCatBuckets) {
        if (r['category_id'] != catId) continue;
        final idx = paceIndex(r['bucket_date'] as String);
        if (idx < 0) continue;
        buckets[idx] += filter.useActualAmount
            ? asInt(r['actual_cents'])
            : asInt(r['spend_cents']);
      }
    }

    final budgetPerBucket = limitCents / bucketCount;
    var running = 0;
    return List.generate(bucketCount, (i) {
      running += buckets[i];
      return SpendVsBudgetPoint(
        label: paceLabel(i),
        cumulativeSpendCents: running,
        cumulativeBudgetCents: ((i + 1) * budgetPerBucket).round(),
      );
    });
  }

  final displayedSpent =
      filter.useActualAmount ? totalActualCents : totalSpentCents;

  final budgetProgress = budgetRows.map((b) {
    final row = b as Map<String, dynamic>;
    final catId = row['category_id'] as String?;
    final catData = row['category'] as Map<String, dynamic>?;
    final label = catData?['name'] as String? ?? 'Overall';
    final color =
        _hexToColor(catData?['color'] as String?) ?? const Color(0xFFBA7517);
    final limitCents = row['limit_cents'] as int;

    int spentCents;
    if (catId == null) {
      spentCents =
          (displayedSpent - totalIncomeCents).clamp(0, displayedSpent);
    } else {
      final catRow =
          byCategoryRows.where((r) => r['category_id'] == catId).firstOrNull;
      spentCents = catRow == null
          ? 0
          : (filter.useActualAmount
              ? asInt(catRow['actual_cents'])
              : asInt(catRow['total_cents']));
    }

    return BudgetProgress(
      label: label,
      spentCents: spentCents,
      limitCents: limitCents,
      barColor: color,
      pacePoints: buildPacePoints(catId, limitCents),
    );
  }).toList()
    ..sort((a, b) => b.spentCents.compareTo(a.spentCents));

  return AnalysisData(
    categoryBreakdown: categoryBreakdown,
    accountBreakdown: accountBreakdown,
    periodBreakdown: periodBreakdown,
    budgetProgress: budgetProgress,
    totalSpentCents: displayedSpent,
    totalIncomeCents: totalIncomeCents,
  );
});

// ── Period bucket builders ────────────────────────────────────────────────────
// These operate on pre-aggregated daily rows from the RPC — not raw expense
// rows — so bucketing in Dart is safe regardless of how many expenses exist.

List<PeriodBucket> _buildPeriodBuckets(
  List<Map<String, dynamic>> dailyBuckets,
  DateTime startDate,
  DateTime endDate,
  AnalysisPeriod period,
  bool useActualAmount,
) {
  switch (period) {
    case AnalysisPeriod.day:
      return _bucketByDay(dailyBuckets, startDate, 1, useActualAmount);
    case AnalysisPeriod.week:
      return _bucketByDay(dailyBuckets, startDate, 7, useActualAmount);
    case AnalysisPeriod.month:
      return _bucketByWeekOfMonth(
          dailyBuckets, startDate, endDate, useActualAmount);
    case AnalysisPeriod.year:
      return _bucketByMonth(dailyBuckets, startDate.year, useActualAmount);
    case AnalysisPeriod.custom:
      final days = endDate.difference(startDate).inDays + 1;
      if (days <= 14) {
        return _bucketByDay(dailyBuckets, startDate, days, useActualAmount);
      }
      if (days <= 90) {
        return _bucketByWeek(dailyBuckets, startDate, endDate, useActualAmount);
      }
      return _bucketByMonth(dailyBuckets, startDate.year, useActualAmount);
  }
}

List<PeriodBucket> _bucketByDay(
  List<Map<String, dynamic>> dailyBuckets,
  DateTime startDate,
  int count,
  bool useActualAmount,
) {
  const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final spendBuckets = List.filled(count, 0);
  final incomeBuckets = List.filled(count, 0);

  for (final row in dailyBuckets) {
    final date = DateTime.parse(row['bucket_date'] as String);
    final idx = date.difference(startDate).inDays;
    if (idx < 0 || idx >= count) continue;
    spendBuckets[idx] += useActualAmount
        ? (row['actual_cents'] as num? ?? 0).toInt()
        : (row['spend_cents'] as num? ?? 0).toInt();
    incomeBuckets[idx] += (row['income_cents'] as num? ?? 0).toInt();
  }

  return List.generate(count, (i) {
    final date = startDate.add(Duration(days: i));
    final label = count <= 7 ? weekdayLabels[date.weekday - 1] : '${date.day}';
    return PeriodBucket(
      label: label,
      spendCents: spendBuckets[i],
      incomeCents: incomeBuckets[i],
    );
  });
}

List<PeriodBucket> _bucketByWeekOfMonth(
  List<Map<String, dynamic>> dailyBuckets,
  DateTime startDate,
  DateTime endDate,
  bool useActualAmount,
) {
  final totalDays = endDate.difference(startDate).inDays + 1;
  final weekCount = ((totalDays - 1) ~/ 7) + 1;
  final spendBuckets = List.filled(weekCount, 0);
  final incomeBuckets = List.filled(weekCount, 0);

  for (final row in dailyBuckets) {
    final date = DateTime.parse(row['bucket_date'] as String);
    final dayOffset = date.difference(startDate).inDays;
    if (dayOffset < 0) continue;
    final weekIdx = (dayOffset ~/ 7).clamp(0, weekCount - 1);
    spendBuckets[weekIdx] += useActualAmount
        ? (row['actual_cents'] as num? ?? 0).toInt()
        : (row['spend_cents'] as num? ?? 0).toInt();
    incomeBuckets[weekIdx] += (row['income_cents'] as num? ?? 0).toInt();
  }

  return List.generate(
    weekCount,
    (i) => PeriodBucket(
      label: 'W${i + 1}',
      spendCents: spendBuckets[i],
      incomeCents: incomeBuckets[i],
    ),
  );
}

List<PeriodBucket> _bucketByWeek(
  List<Map<String, dynamic>> dailyBuckets,
  DateTime startDate,
  DateTime endDate,
  bool useActualAmount,
) {
  final totalDays = endDate.difference(startDate).inDays + 1;
  final weekCount = ((totalDays - 1) ~/ 7) + 1;
  final spendBuckets = List.filled(weekCount, 0);
  final incomeBuckets = List.filled(weekCount, 0);

  for (final row in dailyBuckets) {
    final date = DateTime.parse(row['bucket_date'] as String);
    final dayOffset = date.difference(startDate).inDays;
    if (dayOffset < 0) continue;
    final weekIdx = (dayOffset ~/ 7).clamp(0, weekCount - 1);
    spendBuckets[weekIdx] += useActualAmount
        ? (row['actual_cents'] as num? ?? 0).toInt()
        : (row['spend_cents'] as num? ?? 0).toInt();
    incomeBuckets[weekIdx] += (row['income_cents'] as num? ?? 0).toInt();
  }

  return List.generate(
    weekCount,
    (i) => PeriodBucket(
      label: 'W${i + 1}',
      spendCents: spendBuckets[i],
      incomeCents: incomeBuckets[i],
    ),
  );
}

List<PeriodBucket> _bucketByMonth(
  List<Map<String, dynamic>> dailyBuckets,
  int year,
  bool useActualAmount,
) {
  const monthLabels = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final spendBuckets = List.filled(12, 0);
  final incomeBuckets = List.filled(12, 0);

  for (final row in dailyBuckets) {
    final date = DateTime.parse(row['bucket_date'] as String);
    if (date.year != year) continue;
    final monthIdx = date.month - 1;
    spendBuckets[monthIdx] += useActualAmount
        ? (row['actual_cents'] as num? ?? 0).toInt()
        : (row['spend_cents'] as num? ?? 0).toInt();
    incomeBuckets[monthIdx] += (row['income_cents'] as num? ?? 0).toInt();
  }

  return List.generate(
    12,
    (i) => PeriodBucket(
      label: monthLabels[i],
      spendCents: spendBuckets[i],
      incomeCents: incomeBuckets[i],
    ),
  );
}

// ── Account color palette ─────────────────────────────────────────────────────

const _accountPalette = [
  Color(0xFF5B8CFF),
  Color(0xFFFF7C5B),
  Color(0xFF4DC8A0),
  Color(0xFFFFB347),
  Color(0xFFA78BFA),
  Color(0xFFFF6B9D),
  Color(0xFF34C6CD),
  Color(0xFFFFD166),
];

// ── Color helpers ─────────────────────────────────────────────────────────────

Color? _hexToColor(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return null;
  return Color(int.parse('FF$h', radix: 16));
}
