import '../../../../service_locator.dart';
import '../models/tag_model.dart';

class TagRepository {
  Future<List<TagModel>> fetchTags() async {
    final userId = supabase.auth.currentUser!.id;
    final rows = await supabase
        .from('tags')
        .select('id, name, color, is_default, requires_premium, sort_order')
        .eq('user_id', userId)
        .isFilter('deleted_at', null)
        .order('is_default', ascending: false)
        .order('sort_order')
        .order('name');
    return (rows as List)
        .map((r) => TagModel.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<String> createTag(String name, String color) async {
    final result = await supabase.rpc(
      'create_tag',
      params: {'p_name': name, 'p_color': color},
    );
    return result as String;
  }

  Future<void> deleteTag(String id) async {
    await supabase
        .from('tags')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
  }
}
