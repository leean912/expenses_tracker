import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
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
