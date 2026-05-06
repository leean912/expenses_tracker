import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import '../../subscription/providers/subscription_provider.dart';
import '../data/models/category_model.dart';

final categoriesProvider =
    FutureProvider.autoDispose<List<CategoryModel>>((ref) async {
  final data = await supabase
      .from('categories')
      .select()
      .isFilter('deleted_at', null)
      .order('sort_order');
  return (data as List<dynamic>)
      .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// Categories available for selection in expense/split bill pickers.
/// Excludes premium-flagged categories when the user is on the free tier.
final pickerCategoriesProvider = Provider.autoDispose<AsyncValue<List<CategoryModel>>>((ref) {
  final categoriesAsync = ref.watch(categoriesProvider);
  final isPremium = ref.watch(isPremiumProvider);
  return categoriesAsync.whenData(
    (cats) => isPremium ? cats : cats.where((c) => !c.requiresPremium).toList(),
  );
});
