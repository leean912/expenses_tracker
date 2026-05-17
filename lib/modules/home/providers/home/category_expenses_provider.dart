import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../service_locator.dart';
import 'home_state.dart';

final categoryExpensesProvider =
    FutureProvider.family<List<ExpenseTileData>, (HomeFilter, String?)>((
  ref,
  args,
) async {
  final (filter, categoryId) = args;
  final userId = supabase.auth.currentUser!.id;
  final (start, end) = filter.toDateRange();

  var query = supabase
      .from('expenses')
      .select(
        'id, note, amount_cents, home_amount_cents, actual_amount_cents, type, expense_date, category_id, '
        'currency, collab_id, source_split_bill_id, source_recurring_expense_id, '
        'source_recurring_split_bill_id, receipt_url, '
        'category:categories(name, color), account:accounts(name)',
      )
      .eq('user_id', userId)
      .gte('expense_date', start)
      .lte('expense_date', end)
      .isFilter('deleted_at', null)
      .isFilter('archived_at', null);

  if (categoryId != null) {
    query = query.eq('category_id', categoryId);
  }

  final rows = await query
      .order('expense_date', ascending: false)
      .order('created_at', ascending: false);

  return (rows as List<dynamic>).map((r) {
    final row = r as Map<String, dynamic>;
    final catMap = row['category'] as Map<String, dynamic>?;
    final color = _hexToColor(catMap?['color'] as String?) ??
        const Color(0xFF888780);
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
      accountName:
          (row['account'] as Map<String, dynamic>?)?['name'] as String?,
      isCollab: row['collab_id'] != null,
      isSplitBill: row['source_split_bill_id'] != null ||
          row['source_recurring_split_bill_id'] != null,
      isRecurring: row['source_recurring_expense_id'] != null ||
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
});

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
