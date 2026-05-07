import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import '../data/models/recurring_expense_model.dart';

class RecurringExpensesNotifier
    extends AsyncNotifier<List<RecurringExpenseModel>> {
  @override
  Future<List<RecurringExpenseModel>> build() => _fetch();

  Future<List<RecurringExpenseModel>> _fetch() async {
    final data = await supabase
        .from('recurring_expenses')
        .select()
        .order('next_run_at');
    return (data as List)
        .map((r) => RecurringExpenseModel.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Returns null on success, 'upgrade_required' for freemium limit, or an error string.
  Future<String?> create({
    required String title,
    required int amountCents,
    required String frequency,
    required DateTime firstRunAt,
    String type = 'expense',
    String? categoryId,
    String? accountId,
    String? note,
  }) async {
    try {
      await supabase.rpc('create_recurring_expense', params: {
        'p_title': title,
        'p_amount_cents': amountCents,
        'p_frequency': frequency,
        'p_first_run_at': _fmtDate(firstRunAt),
        'p_type': type,
        'p_category_id': categoryId,
        'p_account_id': accountId,
        'p_note': note,
      });
      ref.invalidateSelf();
      return null;
    } catch (e) {
      if (e.toString().contains('upgrade_required')) return 'upgrade_required';
      return 'Something went wrong. Please try again.';
    }
  }

  Future<String?> edit(
    String id, {
    required String title,
    required int amountCents,
    required String frequency,
    required DateTime nextRunAt,
    required String type,
    String? categoryId,
    String? accountId,
    String? note,
  }) async {
    try {
      await supabase.rpc('update_recurring_expense', params: {
        'p_id': id,
        'p_title': title,
        'p_amount_cents': amountCents,
        'p_frequency': frequency,
        'p_next_run_at': _fmtDate(nextRunAt),
        'p_type': type,
        'p_category_id': categoryId,
        'p_account_id': accountId,
        'p_note': note,
      });
      ref.invalidateSelf();
      return null;
    } catch (_) {
      return 'Something went wrong. Please try again.';
    }
  }

  Future<void> toggle(String id, {required bool isActive}) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(
        current
            .map((r) => r.id == id ? r.copyWith(isActive: isActive) : r)
            .toList(),
      );
    }
    await supabase.rpc('toggle_recurring_expense',
        params: {'p_id': id, 'p_is_active': isActive});
  }

  Future<void> delete(String id) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.where((r) => r.id != id).toList());
    }
    await supabase.rpc('delete_recurring_expense', params: {'p_id': id});
  }
}

final recurringExpensesProvider =
    AsyncNotifierProvider<RecurringExpensesNotifier,
        List<RecurringExpenseModel>>(
  RecurringExpensesNotifier.new,
);

String _fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
