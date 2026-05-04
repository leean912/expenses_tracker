import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../service_locator.dart';

class BudgetItem {
  const BudgetItem({
    required this.id,
    required this.label,
    required this.categoryId,
    required this.categoryColor,
    required this.limitCents,
    required this.spentCents,
    required this.period,
    required this.currency,
    this.isOverall = false,
  });

  final String id;
  final String label;
  final String? categoryId;
  final String? categoryColor;
  final int limitCents;
  final int spentCents;
  final String period;
  final String currency;
  final bool isOverall;

  double get progress =>
      limitCents == 0 ? 0 : spentCents / limitCents;

  int get percentUsed => (progress * 100).round();
}

final budgetsProvider = FutureProvider.autoDispose<List<BudgetItem>>((
  ref,
) async {
  final userId = supabase.auth.currentUser!.id;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final rows = await supabase
      .from('budgets')
      .select('*, category:categories(name, color)')
      .isFilter('deleted_at', null)
      .eq('user_id', userId)
      .order('created_at');

  if ((rows as List).isEmpty) return [];

  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  final monthStart = DateTime(now.year, now.month, 1);
  final yearStart = DateTime(now.year, 1, 1);
  final todayStr = _fmt(today);

  final ranges = <String, (String, String)>{
    'daily': (todayStr, todayStr),
    'weekly': (_fmt(weekStart), todayStr),
    'monthly': (_fmt(monthStart), todayStr),
    'yearly': (_fmt(yearStart), todayStr),
  };

  final periodTypes = rows.map((r) => r['period'] as String).toSet();
  final spendByPeriod = <String, (int, Map<String, int>)>{};

  for (final period in periodTypes) {
    final (start, end) = ranges[period]!;
    final expenses = await supabase
        .from('expenses')
        .select('category_id, home_amount_cents, type')
        .isFilter('deleted_at', null)
        .isFilter('archived_at', null)
        .gte('expense_date', start)
        .lte('expense_date', end)
        .eq('user_id', userId);

    int total = 0;
    final Map<String, int> byCategory = {};
    for (final e in (expenses as List)) {
      final catId = e['category_id'] as String?;
      final cents = (e['home_amount_cents'] as num).toInt();
      final isIncome = e['type'] == 'income';
      if (isIncome) {
        total -= cents;
      } else {
        total += cents;
        if (catId != null) byCategory[catId] = (byCategory[catId] ?? 0) + cents;
      }
    }
    spendByPeriod[period] = (total, byCategory);
  }

  return rows.map<BudgetItem>((row) {
    final catId = row['category_id'] as String?;
    final cat = row['category'] as Map<String, dynamic>?;
    final label = cat?['name'] as String? ?? 'Overall';
    final color = cat?['color'] as String?;
    final limitCents = (row['limit_cents'] as num).toInt();
    final period = row['period'] as String;
    final (total, byCategory) = spendByPeriod[period] ?? (0, <String, int>{});
    final spentCents = catId == null ? total : (byCategory[catId] ?? 0);

    return BudgetItem(
      id: row['id'] as String,
      label: label,
      categoryId: catId,
      categoryColor: color,
      limitCents: limitCents,
      spentCents: spentCents,
      period: period,
      currency: row['currency'] as String? ?? 'MYR',
      isOverall: catId == null,
    );
  }).toList();
});

String _fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
