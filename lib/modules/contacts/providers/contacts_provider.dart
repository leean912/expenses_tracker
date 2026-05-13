import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/models/contact_model.dart';

class ContactsNotifier extends AsyncNotifier<List<ContactModel>> {
  @override
  Future<List<ContactModel>> build() {
    ref.watch(currentUserIdProvider);
    return _fetch();
  }

  Future<List<ContactModel>> _fetch() async {
    final rows = await supabase
        .from('contacts')
        .select(
          'id, nickname, status, friend:profiles!friend_id(id, username, display_name, avatar_url)',
        )
        .eq('owner_id', supabase.auth.currentUser!.id)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => ContactModel.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Returns null (accepted), 'pending' (request sent), or error message.
  Future<String?> addContact(String identifier) async {
    try {
      final result = await supabase.rpc(
        'add_contact',
        params: {'p_identifier': identifier, 'p_nickname': null},
      );
      state = AsyncData(await _fetch());
      ref.invalidate(acceptedContactsProvider);
      final map = result as Map<String, dynamic>?;
      if (map?['result'] == 'pending') return 'pending';
      return null;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('user_not_found')) return 'User not found.';
      if (msg.contains('already_friends')) return 'Already in your contacts.';
      if (msg.contains('request_already_sent')) return 'Request already sent.';
      if (msg.contains('already')) return 'Already in your contacts.';
      return 'Something went wrong.';
    }
  }

  Future<void> deleteContact(String friendId) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(
        current.where((c) => c.friendId != friendId).toList(),
      );
    }
    await supabase.rpc('remove_contact', params: {'p_friend_id': friendId});
    ref.invalidate(acceptedContactsProvider);
  }
}

final contactsProvider =
    AsyncNotifierProvider<ContactsNotifier, List<ContactModel>>(
      ContactsNotifier.new,
    );

final acceptedContactsProvider = FutureProvider<List<ContactModel>>((ref) async {
  final rows = await supabase
      .from('contacts')
      .select(
        'id, nickname, status, friend:profiles!friend_id(id, username, display_name, avatar_url)',
      )
      .eq('owner_id', supabase.auth.currentUser!.id)
      .eq('status', 'accepted')
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => ContactModel.fromJson(r as Map<String, dynamic>))
      .toList();
});
