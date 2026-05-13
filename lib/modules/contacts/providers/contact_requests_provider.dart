import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/models/contact_request_model.dart';
import 'contacts_provider.dart';

class ContactRequestsNotifier
    extends AsyncNotifier<List<ContactRequestModel>> {
  @override
  Future<List<ContactRequestModel>> build() {
    ref.watch(currentUserIdProvider);
    return _fetch();
  }

  Future<List<ContactRequestModel>> _fetch() async {
    final rows = await supabase
        .from('contacts')
        .select(
          'id, from:profiles!owner_id(id, username, display_name, avatar_url)',
        )
        .eq('friend_id', supabase.auth.currentUser!.id)
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => ContactRequestModel.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> acceptRequest(String fromUserId) async {
    await supabase.rpc(
      'accept_contact_request',
      params: {'p_from_user_id': fromUserId},
    );
    ref.invalidate(contactsProvider);
    ref.invalidate(acceptedContactsProvider);
    state = AsyncData(await _fetch());
  }

  Future<void> declineRequest(String fromUserId) async {
    await supabase.rpc(
      'decline_contact_request',
      params: {'p_from_user_id': fromUserId},
    );
    state = AsyncData(await _fetch());
  }
}

final contactRequestsProvider =
    AsyncNotifierProvider<ContactRequestsNotifier, List<ContactRequestModel>>(
      ContactRequestsNotifier.new,
    );
