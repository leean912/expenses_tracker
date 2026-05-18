import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../service_locator.dart';
import 'home_state.dart';

// ── Analytics + Budgets ───────────────────────────────────────────────────────

/// Calls the [home_analytics] RPC and the budgets table in parallel.
///
/// Returns aggregated totals — no raw expense rows, no 1000-row risk.
/// Both [periodTotalCents] (home_amount_cents) and [periodActualCents]
/// (actual_amount_cents) are returned so the UI can toggle without re-fetching.
final homeAnalyticsProvider =
    FutureProvider.family<HomeAnalyticsData, HomeFilter>((ref, filter) async {
      final (start, end) = filter.toDateRange();
      final userId = supabase.auth.currentUser!.id;
      final budgetPeriod = _budgetPeriodFor(filter.period);

      final results = await Future.wait([
        supabase.rpc(
          'home_analytics',
          params: {'p_start': start, 'p_end': end},
        ),
        supabase
            .from('budgets')
            .select(
              'id, limit_cents, category_id, category:categories(name, color)',
            )
            .eq('user_id', userId)
            .eq('period', budgetPeriod)
            .isFilter('deleted_at', null),
      ]);

      final rpc = results[0] as Map<String, dynamic>;
      final budgetRows = results[1] as List<dynamic>;

      int asInt(dynamic v) => (v as num? ?? 0).toInt();

      final periodTotalCents = asInt(rpc['period_total_cents']);
      final periodActualCents = asInt(rpc['period_actual_cents']);

      final analytics = AnalyticsSummary(
        totalSpentCents: periodTotalCents,
        actualSpentCents: periodActualCents,
        avgPerDayCents: asInt(rpc['avg_per_day_cents']),
        actualAvgPerDayCents: asInt(rpc['actual_avg_per_day_cents']),
        topCategory: rpc['top_category'] as String? ?? '—',
        changeVsLastMonthCents:
            asInt(rpc['this_month_total_cents']) -
            asInt(rpc['last_month_total_cents']),
        actualChangeVsLastMonthCents:
            asInt(rpc['this_month_actual_cents']) -
            asInt(rpc['last_month_actual_cents']),
      );

      // Build per-category actual spend map for budget progress bars.

      final catSpendRows = (rpc['category_spend'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final Map<String, int> catActualSpend = {
        for (final r in catSpendRows)
          (r['category_id'] as String? ?? ''): asInt(r['actual_cents']),
      };
      final totalActualSpend = catSpendRows.fold<int>(
        0,
        (s, r) => s + asInt(r['actual_cents']),
      );

      final budgets =
          budgetRows.map((b) {
            final row = b as Map<String, dynamic>;
            final catId = row['category_id'] as String?;
            final catMap = row['category'] as Map<String, dynamic>?;
            final label = catMap?['name'] as String? ?? 'Overall';
            final color =
                _hexToColor(catMap?['color'] as String?) ??
                const Color(0xFF888780);
            final spentCents = catId == null
                ? totalActualSpend
                : (catActualSpend[catId] ?? 0);
            return BudgetMini(
              id: row['id'] as String,
              label: label,
              spentCents: spentCents,
              limitCents: row['limit_cents'] as int,
              barColor: color,
              labelColor: _darken(color),
              categoryId: catId,
              isOverall: catId == null,
            );
          }).toList()..sort((a, b) {
            if (a.isOverall != b.isOverall) return a.isOverall ? -1 : 1;
            return b.spentCents.compareTo(a.spentCents);
          });

      return HomeAnalyticsData(
        analytics: analytics,
        budgets: budgets,
        periodTotalCents: periodTotalCents,
        periodActualCents: periodActualCents,
      );
    });

// ── Paginated expense list ────────────────────────────────────────────────────

class HomeExpensesNotifier
    extends FamilyAsyncNotifier<HomeExpensesState, HomeFilter> {
  static const _pageSize = 30;

  var _page = 0;
  var _hasMore = true;
  var _isFetchingMore = false;
  final _items = <ExpenseTileData>[];

  @override
  Future<HomeExpensesState> build(HomeFilter filter) async {
    _page = 0;
    _hasMore = true;
    _isFetchingMore = false;
    _items.clear();
    return _fetchPage(filter);
  }

  Future<HomeExpensesState> _fetchPage(HomeFilter filter) async {
    final (start, end) = filter.toDateRange();
    final userId = supabase.auth.currentUser!.id;
    final from = _page * _pageSize;

    final rows =
        await supabase
                .from('expenses')
                .select(
                  'id, note, amount_cents, home_amount_cents, actual_amount_cents, '
                  'type, expense_date, category_id, currency, collab_id, '
                  'source_split_bill_id, source_recurring_expense_id, '
                  'source_recurring_split_bill_id, receipt_url, '
                  'category:categories(name, color), account:accounts(name)',
                )
                .eq('user_id', userId)
                .gte('expense_date', start)
                .lte('expense_date', end)
                .isFilter('deleted_at', null)
                .isFilter('archived_at', null)
                .order('expense_date', ascending: false)
                .order('created_at', ascending: false)
                .range(from, from + _pageSize - 1)
            as List<dynamic>;

    _hasMore = rows.length == _pageSize;
    _items.addAll(_mapRows(rows));
    _page++;
    return HomeExpensesState(
      items: List.unmodifiable(_items),
      hasMore: _hasMore,
    );
  }

  /// Removes a single expense from the local list without re-fetching.
  void removeExpense(String id) {
    final current = state.valueOrNull;
    if (current == null) return;
    _items.removeWhere((e) => e.id == id);
    state = AsyncData(
      HomeExpensesState(items: List.unmodifiable(_items), hasMore: _hasMore),
    );
  }

  /// Fetches the next page and appends to the existing list.
  /// Safe to call multiple times — guarded by [_isFetchingMore].
  Future<void> fetchMore() async {
    if (!_hasMore || _isFetchingMore || state.isLoading) return;
    _isFetchingMore = true;
    try {
      final next = await _fetchPage(arg);
      state = AsyncData(next);
    } catch (_) {
      // Keep existing data on pagination error.
    } finally {
      _isFetchingMore = false;
    }
  }
}

final homeExpensesProvider =
    AsyncNotifierProvider.family<
      HomeExpensesNotifier,
      HomeExpensesState,
      HomeFilter
    >(HomeExpensesNotifier.new);

// ── Helpers ───────────────────────────────────────────────────────────────────

List<ExpenseTileData> _mapRows(List<dynamic> rows) => rows.map((r) {
  final row = r as Map<String, dynamic>;
  final catMap = row['category'] as Map<String, dynamic>?;
  final color =
      _hexToColor(catMap?['color'] as String?) ?? const Color(0xFF888780);
  final currency = row['currency'] as String?;
  return ExpenseTileData(
    id: row['id'] as String,
    title: row['note'] as String? ?? '',
    amountCents: row['home_amount_cents'] as int? ?? 0,
    actualAmountCents: row['actual_amount_cents'] as int?,
    isIncome: row['type'] != 'expense',
    categoryName: catMap?['name'] as String? ?? 'Other',
    categoryLight: _lighten(color),
    categoryDark: _darken(color),
    date: DateTime.parse(row['expense_date'] as String),
    accountName: (row['account'] as Map<String, dynamic>?)?['name'] as String?,
    isCollab: row['collab_id'] != null,
    isSplitBill:
        row['source_split_bill_id'] != null ||
        row['source_recurring_split_bill_id'] != null,
    isRecurring:
        row['source_recurring_expense_id'] != null ||
        row['source_recurring_split_bill_id'] != null,
    hasReceipt: row['receipt_url'] != null,
    currencyCode: (currency != null && currency != 'MYR') ? currency : null,
    foreignAmountCents: (currency != null && currency != 'MYR')
        ? row['amount_cents'] as int?
        : null,
    collabId: row['collab_id'] as String?,
    splitBillId: row['source_split_bill_id'] as String?,
  );
}).toList();

String _budgetPeriodFor(TimePeriod period) => switch (period) {
  TimePeriod.today => 'daily',
  TimePeriod.week => 'weekly',
  TimePeriod.year => 'yearly',
  _ => 'monthly',
};

Color? _hexToColor(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return null;
  return Color(int.parse('FF$h', radix: 16));
}

Color _lighten(Color color) =>
    Color.lerp(color, const Color(0xFFFFFFFF), 0.82)!;

Color _darken(Color color) => Color.lerp(color, const Color(0xFF000000), 0.35)!;
