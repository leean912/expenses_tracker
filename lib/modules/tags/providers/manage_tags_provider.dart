import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories/tag_repository.dart';
import 'tags_provider.dart';

class ManageTagsNotifier extends Notifier<void> {
  @override
  void build() {}

  /// Returns null on success, 'upgrade_required' if limit hit, or error string.
  Future<String?> createTag(String name, String color) async {
    try {
      await TagRepository().createTag(name, color);
      ref.invalidate(tagsProvider);
      return null;
    } on PostgrestException catch (e) {
      if (e.hint == 'upgrade_required') return 'upgrade_required';
      debugPrint('createTag error: $e');
      return 'Something went wrong.';
    } catch (e) {
      if (e.toString().contains('upgrade_required')) return 'upgrade_required';
      debugPrint('createTag error: $e');
      return 'Something went wrong.';
    }
  }

  Future<void> deleteTag(String id, {required bool isDefault}) async {
    if (isDefault) return;
    await TagRepository().deleteTag(id);
    ref.invalidate(tagsProvider);
  }
}

final manageTagsProvider =
    NotifierProvider<ManageTagsNotifier, void>(ManageTagsNotifier.new);
