import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/tag_model.dart';
import '../data/repositories/tag_repository.dart';

class TagsNotifier extends AsyncNotifier<List<TagModel>> {
  @override
  Future<List<TagModel>> build() => TagRepository().fetchTags();
}

final tagsProvider =
    AsyncNotifierProvider<TagsNotifier, List<TagModel>>(TagsNotifier.new);
