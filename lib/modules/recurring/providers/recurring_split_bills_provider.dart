import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import '../data/models/recurring_split_bill_model.dart';

class RecurringSplitBillsNotifier
    extends AsyncNotifier<List<RecurringSplitBillModel>> {
  @override
  Future<List<RecurringSplitBillModel>> build() => _fetch();

  Future<List<RecurringSplitBillModel>> _fetch() async {
    final data = await supabase
        .from('recurring_split_bills')
        .select(
          '*, shares:recurring_split_bill_shares(*, profile:profiles!user_id(display_name, avatar_url))',
        )
        .order('next_run_at');
    return (data as List)
        .map((r) => RecurringSplitBillModel.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Returns null on success, 'upgrade_required' for freemium limit, or an error string.
  Future<String?> create({
    required String title,
    required int amountCents,
    required String frequency,
    required DateTime firstRunAt,
    required String splitMethod,
    required List<Map<String, dynamic>> shares,
    String? categoryId,
    String? accountId,
    String? note,
  }) async {
    try {
      await supabase.rpc(
        'create_recurring_split_bill',
        params: {
          'p_title': title,
          'p_amount_cents': amountCents,
          'p_frequency': frequency,
          'p_first_run_at': _fmtDate(firstRunAt),
          'p_split_method': splitMethod,
          'p_shares': shares,
          'p_category_id': categoryId,
          'p_account_id': accountId,
          'p_note': note,
        },
      );
      ref.invalidateSelf();
      return null;
    } catch (e) {
      debugPrint('Create recurring split bill error: $e');
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
    required String splitMethod,
    required List<Map<String, dynamic>> shares,
    String? categoryId,
    String? accountId,
    String? note,
  }) async {
    try {
      await supabase.rpc(
        'update_recurring_split_bill',
        params: {
          'p_id': id,
          'p_title': title,
          'p_amount_cents': amountCents,
          'p_frequency': frequency,
          'p_next_run_at': _fmtDate(nextRunAt),
          'p_split_method': splitMethod,
          'p_shares': shares,
          'p_category_id': categoryId,
          'p_account_id': accountId,
          'p_note': note,
        },
      );
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
    await supabase.rpc(
      'toggle_recurring_split_bill',
      params: {'p_id': id, 'p_is_active': isActive},
    );
  }

  Future<void> delete(String id) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.where((r) => r.id != id).toList());
    }
    await supabase.rpc('delete_recurring_split_bill', params: {'p_id': id});
  }
}

final recurringSplitBillsProvider =
    AsyncNotifierProvider<
      RecurringSplitBillsNotifier,
      List<RecurringSplitBillModel>
    >(RecurringSplitBillsNotifier.new);

String _fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
