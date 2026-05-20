import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../subscription/providers/subscription_provider.dart';
import '../data/models/tag_model.dart';
import '../data/repositories/tag_repository.dart';

class TagsNotifier extends AsyncNotifier<List<TagModel>> {
  @override
  Future<List<TagModel>> build() => TagRepository().fetchTags();
}

final tagsProvider =
    AsyncNotifierProvider<TagsNotifier, List<TagModel>>(TagsNotifier.new);

/// Tags available for selection in expense/split bill pickers.
/// Excludes premium-flagged tags when the user is on the free tier.
final pickerTagsProvider = Provider.autoDispose<AsyncValue<List<TagModel>>>((ref) {
  final tagsAsync = ref.watch(tagsProvider);
  final isPremium = ref.watch(isPremiumProvider);
  return tagsAsync.whenData(
    (tags) => isPremium ? tags : tags.where((t) => !t.requiresPremium).toList(),
  );
});
