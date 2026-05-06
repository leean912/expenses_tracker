import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import '../data/models/collab_model.dart';

class CollabsNotifier extends AsyncNotifier<List<CollabModel>> {
  @override
  Future<List<CollabModel>> build() => _fetch();

  Future<List<CollabModel>> _fetch() async {
    final rows = await supabase
        .from('collabs')
        .select(
          '*, members:collab_members(id, collab_id, user_id, role, joined_at, left_at, personal_budget_cents, user:profiles(id, username, display_name, avatar_url))',
        )
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => CollabModel.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Returns null on success, error message on failure.
  Future<String?> createCollab({
    required String name,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    required String currency,
    required String homeCurrency,
    double? exchangeRate,
    int? budgetCents,
  }) async {
    try {
      final payload = <String, dynamic>{
        'owner_id': supabase.auth.currentUser!.id,
        'name': name,
        'currency': currency,
        'home_currency': homeCurrency,
      };
      if (description != null && description.isNotEmpty) {
        payload['description'] = description;
      }
      if (startDate != null) {
        payload['start_date'] =
            '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
      }
      if (endDate != null) {
        payload['end_date'] =
            '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';
      }
      if (currency != homeCurrency && exchangeRate != null) {
        payload['exchange_rate'] = exchangeRate;
      }
      if (budgetCents != null) payload['budget_cents'] = budgetCents;

      await supabase.from('collabs').insert(payload);
      state = AsyncData(await _fetch());
      return null;
    } catch (e) {
      return 'Something went wrong.';
    }
  }

  Future<String?> updateCollab({
    required String collabId,
    required String name,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    required int? budgetCents,
    required String currency,
    double? exchangeRate,
  }) async {
    try {
      final payload = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
        'name': name,
        'description': description,
        'currency': currency,
        'budget_cents': budgetCents,
        'exchange_rate': exchangeRate,
      };
      if (startDate != null) {
        payload['start_date'] =
            '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
      }
      if (endDate != null) {
        payload['end_date'] =
            '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';
      }

      await supabase.from('collabs').update(payload).eq('id', collabId);
      state = AsyncData(await _fetch());
      return null;
    } catch (e) {
      return 'Something went wrong.';
    }
  }

  Future<String?> closeCollab(String collabId) async {
    try {
      await supabase.rpc('close_collab', params: {'p_collab_id': collabId});
      state = AsyncData(await _fetch());
      return null;
    } catch (e) {
      return 'Something went wrong.';
    }
  }

  Future<String?> addMember(String collabId, String userId) async {
    try {
      await supabase.rpc('add_collab_member', params: {
        'p_collab_id': collabId,
        'p_user_id': userId,
      });
      state = AsyncData(await _fetch());
      return null;
    } catch (e) {
      return 'Something went wrong.';
    }
  }

  Future<String?> removeMember(String collabId, String userId) async {
    try {
      await supabase.rpc('remove_collab_member', params: {
        'p_collab_id': collabId,
        'p_user_id': userId,
      });
      state = AsyncData(await _fetch());
      return null;
    } catch (e) {
      return 'Something went wrong.';
    }
  }

  Future<String?> deleteCollab(String collabId) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.where((c) => c.id != collabId).toList());
    }
    try {
      await supabase.from('collabs').update({
        'deleted_at': DateTime.now().toIso8601String(),
      }).eq('id', collabId);
      return null;
    } catch (e) {
      state = AsyncData(await _fetch());
      return 'Something went wrong.';
    }
  }

  Future<String?> leaveCollab(String collabId) async {
    try {
      await supabase.rpc('leave_collab', params: {'p_collab_id': collabId});
      state = AsyncData(await _fetch());
      return null;
    } catch (e) {
      return 'Something went wrong.';
    }
  }

  Future<String?> updatePersonalBudget({
    required String collabId,
    required String memberId,
    required int? budgetCents,
  }) async {
    try {
      await supabase
          .from('collab_members')
          .update({'personal_budget_cents': budgetCents})
          .eq('id', memberId);
      state = AsyncData(await _fetch());
      return null;
    } catch (e) {
      return 'Something went wrong.';
    }
  }
}

final collabsProvider =
    AsyncNotifierProvider<CollabsNotifier, List<CollabModel>>(
      CollabsNotifier.new,
    );
