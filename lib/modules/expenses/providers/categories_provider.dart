import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
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
