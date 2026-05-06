import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import '../../subscription/providers/subscription_provider.dart';
import '../data/models/account_model.dart';

final accountsProvider =
    FutureProvider.autoDispose<List<AccountModel>>((ref) async {
  final data = await supabase
      .from('accounts')
      .select()
      .eq('is_archived', false)
      .isFilter('deleted_at', null)
      .order('is_default', ascending: false)
      .order('sort_order');
  return (data as List<dynamic>)
      .map((e) => AccountModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Accounts available for selection in expense/split bill pickers.
/// Excludes premium-flagged accounts when the user is on the free tier.
final pickerAccountsProvider = Provider.autoDispose<AsyncValue<List<AccountModel>>>((ref) {
  final accountsAsync = ref.watch(accountsProvider);
  final isPremium = ref.watch(isPremiumProvider);
  return accountsAsync.whenData(
    (accs) => isPremium ? accs : accs.where((a) => !a.requiresPremium).toList(),
  );
});
