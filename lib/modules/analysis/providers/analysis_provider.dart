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

  final results = await Future.wait([
    () {
      var q = supabase
          .from('expenses')
          .select(
            'home_amount_cents, type, expense_date, category_id, '
            'category:categories(name, color)',
          )
          .eq('user_id', userId)
          .gte('expense_date', start)
          .lte('expense_date', end)
          .isFilter('deleted_at', null)
          .isFilter('archived_at', null);
      if (!filter.includeCollabExpenses) {
        q = q.isFilter('collab_id', null);
      }
      return q.order('expense_date', ascending: true);
    }(),
    supabase
        .from('budgets')
        .select(
          'limit_cents, category_id, category:categories(name, color)',
        )
        .eq('user_id', userId)
        .eq('period', budgetPeriod)
        .isFilter('deleted_at', null),
  ]);

  final expenseRows = results[0] as List<dynamic>;
  final budgetRows = results[1] as List<dynamic>;

  // ── Category breakdown ─────────────────────────────────────────────────────

  int totalSpentCents = 0;
  int totalIncomeCents = 0;
  final Map<String, ({int cents, String name, String? colorHex})> catMap = {};

  for (final r in expenseRows) {
    final row = r as Map<String, dynamic>;
    final cents = row['home_amount_cents'] as int? ?? 0;
    final isIncome = row['type'] == 'income';
    final catId = row['category_id'] as String? ?? 'uncategorized';
    final catData = row['category'] as Map<String, dynamic>?;
    final catName = catData?['name'] as String? ?? 'Other';
    final colorHex = catData?['color'] as String?;

    if (isIncome) {
      totalIncomeCents += cents;
    } else {
      totalSpentCents += cents;
      final existing = catMap[catId];
      catMap[catId] = (
        cents: (existing?.cents ?? 0) + cents,
        name: catName,
        colorHex: colorHex ?? existing?.colorHex,
      );
    }
  }

  final categoryBreakdown = catMap.entries.map((e) {
    final color = _hexToColor(e.value.colorHex) ?? const Color(0xFF888780);
    return CategorySpend(
      categoryId: e.key,
      categoryName: e.value.name,
      color: color,
      totalCents: e.value.cents,
      percentage:
          totalSpentCents == 0 ? 0 : e.value.cents / totalSpentCents * 100,
    );
  }).toList()
    ..sort((a, b) => b.totalCents.compareTo(a.totalCents));

  // ── Period breakdown (bar chart) ──────────────────────────────────────────

  final periodBreakdown = _buildPeriodBuckets(
    expenseRows,
    startDate,
    endDate,
    filter.period,
  );

  // ── Cumulative trend (line chart) ─────────────────────────────────────────

  final cumulativeTrend = _buildCumulativeTrend(
    expenseRows,
    startDate,
    endDate,
  );

  // ── Budget progress ────────────────────────────────────────────────────────

  final budgetProgress = budgetRows.map((b) {
    final row = b as Map<String, dynamic>;
    final catId = row['category_id'] as String?;
    final catData = row['category'] as Map<String, dynamic>?;
    final label = catData?['name'] as String? ?? 'Overall';
    final color =
        _hexToColor(catData?['color'] as String?) ?? const Color(0xFFBA7517);
    final spentCents = catId == null
        ? totalSpentCents
        : (catMap[catId]?.cents ?? 0);
    return BudgetProgress(
      label: label,
      spentCents: spentCents,
      limitCents: row['limit_cents'] as int,
      barColor: color,
    );
  }).toList()
    ..sort((a, b) => b.spentCents.compareTo(a.spentCents));

  return AnalysisData(
    categoryBreakdown: categoryBreakdown,
    periodBreakdown: periodBreakdown,
    budgetProgress: budgetProgress,
    cumulativeTrend: cumulativeTrend,
    totalSpentCents: totalSpentCents,
    totalIncomeCents: totalIncomeCents,
  );
});

// ── Period bucket builders ────────────────────────────────────────────────────

List<PeriodBucket> _buildPeriodBuckets(
  List<dynamic> rows,
  DateTime startDate,
  DateTime endDate,
  AnalysisPeriod period,
) {
  switch (period) {
    case AnalysisPeriod.week:
      return _bucketByDay(rows, startDate, 7);
    case AnalysisPeriod.month:
      return _bucketByWeekOfMonth(rows, startDate, endDate);
    case AnalysisPeriod.year:
      return _bucketByMonth(rows, startDate.year);
    case AnalysisPeriod.custom:
      final days = endDate.difference(startDate).inDays + 1;
      if (days <= 14) return _bucketByDay(rows, startDate, days);
      if (days <= 90) return _bucketByWeek(rows, startDate, endDate);
      return _bucketByMonth(rows, startDate.year);
  }
}

List<PeriodBucket> _bucketByDay(
  List<dynamic> rows,
  DateTime startDate,
  int count,
) {
  const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final spendBuckets = List.filled(count, 0);
  final incomeBuckets = List.filled(count, 0);

  for (final r in rows) {
    final row = r as Map<String, dynamic>;
    final date = DateTime.parse(row['expense_date'] as String);
    final idx = date.difference(startDate).inDays;
    if (idx < 0 || idx >= count) continue;
    final cents = row['home_amount_cents'] as int? ?? 0;
    if (row['type'] == 'income') {
      incomeBuckets[idx] += cents;
    } else {
      spendBuckets[idx] += cents;
    }
  }

  return List.generate(count, (i) {
    final date = startDate.add(Duration(days: i));
    final label =
        count <= 7 ? weekdayLabels[date.weekday - 1] : '${date.day}';
    return PeriodBucket(
      label: label,
      spendCents: spendBuckets[i],
      incomeCents: incomeBuckets[i],
    );
  });
}

List<PeriodBucket> _bucketByWeekOfMonth(
  List<dynamic> rows,
  DateTime startDate,
  DateTime endDate,
) {
  final totalDays = endDate.difference(startDate).inDays + 1;
  final weekCount = ((totalDays - 1) ~/ 7) + 1;
  final spendBuckets = List.filled(weekCount, 0);
  final incomeBuckets = List.filled(weekCount, 0);

  for (final r in rows) {
    final row = r as Map<String, dynamic>;
    final date = DateTime.parse(row['expense_date'] as String);
    final dayOffset = date.difference(startDate).inDays;
    if (dayOffset < 0) continue;
    final weekIdx = (dayOffset ~/ 7).clamp(0, weekCount - 1);
    final cents = row['home_amount_cents'] as int? ?? 0;
    if (row['type'] == 'income') {
      incomeBuckets[weekIdx] += cents;
    } else {
      spendBuckets[weekIdx] += cents;
    }
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
  List<dynamic> rows,
  DateTime startDate,
  DateTime endDate,
) {
  final totalDays = endDate.difference(startDate).inDays + 1;
  final weekCount = ((totalDays - 1) ~/ 7) + 1;
  final spendBuckets = List.filled(weekCount, 0);
  final incomeBuckets = List.filled(weekCount, 0);

  for (final r in rows) {
    final row = r as Map<String, dynamic>;
    final date = DateTime.parse(row['expense_date'] as String);
    final dayOffset = date.difference(startDate).inDays;
    if (dayOffset < 0) continue;
    final weekIdx = (dayOffset ~/ 7).clamp(0, weekCount - 1);
    final cents = row['home_amount_cents'] as int? ?? 0;
    if (row['type'] == 'income') {
      incomeBuckets[weekIdx] += cents;
    } else {
      spendBuckets[weekIdx] += cents;
    }
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

List<PeriodBucket> _bucketByMonth(List<dynamic> rows, int year) {
  const monthLabels = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final spendBuckets = List.filled(12, 0);
  final incomeBuckets = List.filled(12, 0);

  for (final r in rows) {
    final row = r as Map<String, dynamic>;
    final date = DateTime.parse(row['expense_date'] as String);
    if (date.year != year) continue;
    final monthIdx = date.month - 1;
    final cents = row['home_amount_cents'] as int? ?? 0;
    if (row['type'] == 'income') {
      incomeBuckets[monthIdx] += cents;
    } else {
      spendBuckets[monthIdx] += cents;
    }
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

List<DailyPoint> _buildCumulativeTrend(
  List<dynamic> rows,
  DateTime startDate,
  DateTime endDate,
) {
  final totalDays = endDate.difference(startDate).inDays + 1;
  final dailyCents = List.filled(totalDays, 0);

  for (final r in rows) {
    final row = r as Map<String, dynamic>;
    if (row['type'] == 'income') continue;
    final date = DateTime.parse(row['expense_date'] as String);
    final idx = date.difference(startDate).inDays;
    if (idx < 0 || idx >= totalDays) continue;
    dailyCents[idx] += row['home_amount_cents'] as int? ?? 0;
  }

  var running = 0;
  return List.generate(totalDays, (i) {
    running += dailyCents[i];
    return DailyPoint(
      date: startDate.add(Duration(days: i)),
      cumulativeCents: running,
    );
  });
}

// ── Color helpers ─────────────────────────────────────────────────────────────

Color? _hexToColor(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return null;
  return Color(int.parse('FF$h', radix: 16));
}
