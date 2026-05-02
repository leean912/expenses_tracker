import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../service_locator.dart';
import 'home_state.dart';

/// All data needed to render the home screen for a given [TimePeriod].
///
/// Fetched in a single round-trip: 3 parallel Supabase queries via
/// [Future.wait]. Expense rows are reused for analytics, budget spend, and the
/// expense list — no duplicate fetching.
class HomeData {
  const HomeData({
    required this.analytics,
    required this.budgets,
    required this.expenses,
    required this.periodTotalCents,
  });

  final AnalyticsSummary analytics;
  final List<BudgetMini> budgets;
  final List<ExpenseTileData> expenses;

  /// Total expense-type spend for the selected period (cents).
  final int periodTotalCents;
}

/// Loads [HomeData] for the given [TimePeriod] using 3 parallel queries:
///
///   1. Current-period expense rows (with category + account metadata).
///   2. Previous-period totals (for the change-% delta in the analytics banner).
///   3. Active budgets matching the period, with category color from DB.
///
/// Budget spend is computed from the expense rows already in memory — no
/// extra round-trip.
final homeDataProvider =
    FutureProvider.family<HomeData, TimePeriod>((ref, period) async {
  final userId = supabase.auth.currentUser!.id;
  final (start, end) = period.toDateRange();
  final (prevStart, prevEnd) = period.toPreviousDateRange();
  final budgetPeriod = _budgetPeriodFor(period);

  final results = await Future.wait([
    // 1. Current-period expenses — feeds analytics, budget spend, and the list.
    supabase
        .from('expenses')
        .select(
          'id, note, home_amount_cents, type, expense_date, category_id, '
          'category:categories(name, color), account:accounts(name)',
        )
        .eq('user_id', userId)
        .gte('expense_date', start)
        .lte('expense_date', end)
        .isFilter('deleted_at', null)
        .isFilter('archived_at', null)
        .order('expense_date', ascending: false),

    // 2. Previous-period totals (expense type only, for delta calculation).
    supabase
        .from('expenses')
        .select('home_amount_cents')
        .eq('user_id', userId)
        .eq('type', 'expense')
        .gte('expense_date', prevStart)
        .lte('expense_date', prevEnd)
        .isFilter('deleted_at', null)
        .isFilter('archived_at', null),

    // 3. Active budgets for the matching period, with category color.
    supabase
        .from('budgets')
        .select('id, limit_cents, category_id, category:categories(name, color)')
        .eq('user_id', userId)
        .eq('period', budgetPeriod)
        .isFilter('deleted_at', null),
  ]);

  final expenseRows = results[0] as List<dynamic>;
  final prevRows = results[1] as List<dynamic>;
  final budgetRows = results[2] as List<dynamic>;

  // ── Analytics ─────────────────────────────────────────────────────────────

  int totalCents = 0;
  final Map<String, ({int cents, String name})> spendByCategory = {};

  for (final r in expenseRows) {
    final row = r as Map<String, dynamic>;
    final cents = row['home_amount_cents'] as int? ?? 0;
    final isIncome = row['type'] == 'income';

    if (isIncome) {
      totalCents -= cents;
    } else {
      totalCents += cents;

      final catId = row['category_id'] as String? ?? '';
      final catName =
          (row['category'] as Map<String, dynamic>?)?['name'] as String? ?? catId;
      final existing = spendByCategory[catId];
      spendByCategory[catId] = (
        cents: (existing?.cents ?? 0) + cents,
        name: catName,
      );
    }
  }

  final int prevTotalCents = prevRows.fold(
    0,
    (sum, r) => sum + ((r as Map)['home_amount_cents'] as int? ?? 0),
  );
  final changeVsLast = totalCents - prevTotalCents;
  final changePercent =
      prevTotalCents == 0 ? 0.0 : (changeVsLast / prevTotalCents) * 100.0;

  final topCategory = spendByCategory.entries
          .fold<MapEntry<String, ({int cents, String name})>?>(
            null,
            (best, e) =>
                best == null || e.value.cents > best.value.cents ? e : best,
          )
          ?.value
          .name ??
      '—';

  final periodDays =
      DateTime.parse(end).difference(DateTime.parse(start)).inDays + 1;
  final avgPerDayCents = periodDays > 0 ? totalCents ~/ periodDays : 0;

  final analytics = AnalyticsSummary(
    totalSpentCents: totalCents,
    changePercent: changePercent,
    avgPerDayCents: avgPerDayCents,
    topCategory: topCategory,
    changeVsLastMonthCents: changeVsLast,
  );

  // ── Budgets ───────────────────────────────────────────────────────────────

  final budgets = budgetRows.map((b) {
    final row = b as Map<String, dynamic>;
    final catId = row['category_id'] as String?;
    final catMap = row['category'] as Map<String, dynamic>?;
    final label = catMap?['name'] as String? ?? 'Overall';
    final color =
        _hexToColor(catMap?['color'] as String?) ?? const Color(0xFF888780);
    final spentCents =
        catId == null ? totalCents : (spendByCategory[catId]?.cents ?? 0);

    return BudgetMini(
      id: row['id'] as String,
      label: label,
      spentCents: spentCents,
      limitCents: row['limit_cents'] as int,
      barColor: color,
      labelColor: _darken(color),
      isOverall: catId == null,
    );
  }).toList()
    ..sort((a, b) {
      // Overall budget first, then by spend descending.
      if (a.isOverall != b.isOverall) return a.isOverall ? -1 : 1;
      return b.spentCents.compareTo(a.spentCents);
    });

  // ── Expense list ──────────────────────────────────────────────────────────

  final expenses = expenseRows.map((r) {
    final row = r as Map<String, dynamic>;
    final catMap = row['category'] as Map<String, dynamic>?;
    final color =
        _hexToColor(catMap?['color'] as String?) ?? const Color(0xFF888780);

    return ExpenseTileData(
      id: row['id'] as String,
      title: row['note'] as String? ?? '',
      amountCents: row['home_amount_cents'] as int? ?? 0,
      isIncome: row['type'] != 'expense',
      categoryName: catMap?['name'] as String? ?? 'Other',
      categoryLight: _lighten(color),
      categoryDark: _darken(color),
      date: DateTime.parse(row['expense_date'] as String),
      accountName:
          (row['account'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }).toList();

  return HomeData(
    analytics: analytics,
    budgets: budgets,
    expenses: expenses,
    periodTotalCents: totalCents,
  );
});

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Maps [TimePeriod] to the `budgets.period` value used in Supabase.
/// 'today' has no daily budget type — falls back to monthly.
String _budgetPeriodFor(TimePeriod period) => switch (period) {
      TimePeriod.week => 'weekly',
      TimePeriod.year => 'yearly',
      _ => 'monthly',
    };

/// Parses a CSS hex string (e.g. `#E85D24`) into a Flutter [Color].
Color? _hexToColor(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return null;
  return Color(int.parse('FF$h', radix: 16));
}

Color _lighten(Color color) =>
    Color.lerp(color, const Color(0xFFFFFFFF), 0.82)!;

Color _darken(Color color) =>
    Color.lerp(color, const Color(0xFF000000), 0.35)!;
