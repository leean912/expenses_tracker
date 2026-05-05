import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import '../data/models/contact_model.dart';

class ContactsNotifier extends AsyncNotifier<List<ContactModel>> {
  @override
  Future<List<ContactModel>> build() => _fetch();

  Future<List<ContactModel>> _fetch() async {
    final rows = await supabase
        .from('contacts')
        .select(
          'id, nickname, friend:profiles!friend_id(id, username, display_name, avatar_url)',
        )
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => ContactModel.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Returns null on success, error message on failure.
  Future<String?> addContact(String identifier) async {
    try {
      await supabase.rpc(
        'add_contact',
        params: {'p_identifier': identifier, 'p_nickname': null},
      );
      state = AsyncData(await _fetch());
      return null;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('user_not_found')) return 'User not found.';
      if (msg.contains('already')) return 'Already in your contacts.';
      return 'Something went wrong.';
    }
  }

  Future<void> deleteContact(String contactId) async {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.where((c) => c.id != contactId).toList());
    }
    await supabase.from('contacts').delete().eq('id', contactId);
  }
}

final contactsProvider =
    AsyncNotifierProvider<ContactsNotifier, List<ContactModel>>(
      ContactsNotifier.new,
    );
