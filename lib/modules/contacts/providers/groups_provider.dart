import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import '../data/models/group_model.dart';

class GroupsNotifier extends AsyncNotifier<List<GroupModel>> {
  @override
  Future<List<GroupModel>> build() => _fetch();

  Future<List<GroupModel>> _fetch() async {
    final rows = await supabase
        .from('groups')
        .select(
          '*, members:group_members(user:profiles(id, username, display_name))',
        )
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => GroupModel.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Returns null on success, 'upgrade_required' if limit hit, or error message.
  Future<String?> createGroup({
    required String name,
    required List<String> memberUserIds,
    required String color,
  }) async {
    try {
      await supabase.rpc('create_group', params: {
        'p_name': name,
        'p_member_user_ids': memberUserIds,
        'p_icon': 'group',
        'p_color': color,
      });
      state = AsyncData(await _fetch());
      return null;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('upgrade_required')) return 'upgrade_required';
      return 'Something went wrong.';
    }
  }

  Future<void> deleteGroup(String groupId) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.where((g) => g.id != groupId).toList());
    }
    await supabase.rpc('delete_group', params: {'p_group_id': groupId});
  }
}

final groupsProvider =
    AsyncNotifierProvider<GroupsNotifier, List<GroupModel>>(
      GroupsNotifier.new,
    );
