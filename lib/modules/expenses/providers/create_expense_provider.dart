import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';

class CreateExpenseState {
  const CreateExpenseState({this.isLoading = false, this.error});

  final bool isLoading;
  final String? error;
}

class CreateExpenseNotifier extends AutoDisposeNotifier<CreateExpenseState> {
  @override
  CreateExpenseState build() => const CreateExpenseState();

  Future<bool> submit({
    required int amountCents,
    required String currency,
    required DateTime date,
    String? categoryId,
    String? accountId,
    String? note,
  }) async {
    state = const CreateExpenseState(isLoading: true);
    try {
      final userId = supabase.auth.currentUser!.id;
      final dateStr =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      final payload = <String, dynamic>{
        'user_id': userId,
        'type': 'expense',
        'source': 'manual',
        'amount_cents': amountCents,
        'currency': currency,
        'home_amount_cents': amountCents,
        'home_currency': currency,
        'expense_date': dateStr,
      };
      if (categoryId != null) payload['category_id'] = categoryId;
      if (accountId != null) payload['account_id'] = accountId;
      if (note != null && note.isNotEmpty) payload['note'] = note;

      await supabase.from('expenses').insert(payload);

      state = const CreateExpenseState();
      return true;
    } catch (e) {
      state = CreateExpenseState(error: e.toString());
      return false;
    }
  }
}

final createExpenseProvider = AutoDisposeNotifierProvider<CreateExpenseNotifier,
    CreateExpenseState>(CreateExpenseNotifier.new);
