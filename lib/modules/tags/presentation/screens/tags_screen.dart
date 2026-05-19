import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/widgets/upgrade_sheet.dart';
import '../../../subscription/providers/subscription_provider.dart';
import '../../data/models/tag_model.dart';
import '../../providers/manage_tags_provider.dart';
import '../../providers/tags_provider.dart';

class TagsScreen extends ConsumerWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(tagsProvider);
    final isPremium = ref.watch(isPremiumProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Tags',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: tagsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text(
            'Failed to load tags',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        data: (tags) {
          final customCount =
              tags.where((t) => !t.isDefault).length;
          return Column(
            children: [
              if (!isPremium) ...[
                _UsageBanner(used: customCount, limit: 5),
                const SizedBox(height: AppSpacing.sm),
              ],
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  itemCount: tags.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, i) {
                    final tag = tags[i];
                    return _TagTile(
                      tag: tag,
                      onDelete: tag.isDefault
                          ? null
                          : () => _confirmDelete(context, ref, tag),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final tags = ref.read(tagsProvider).valueOrNull ?? [];
          final customCount = tags.where((t) => !t.isDefault).length;
          if (!isPremium && customCount >= 5) {
            UpgradeSheet.show(
              context,
              title: 'Tags is a Pro feature',
              description:
                  'Upgrade to Spendz Pro to create unlimited tags.',
            );
            return;
          }
          _showAddSheet(context, ref);
        },
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.accentText,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Tag',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, TagModel tag) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeleteConfirmSheet(
        tagName: tag.name,
        onConfirm: () async {
          await ref
              .read(manageTagsProvider.notifier)
              .deleteTag(tag.id, isDefault: tag.isDefault);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('"${tag.name}" deleted.'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.textPrimary,
              ),
            );
          }
        },
      ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddTagSheet(
        onCreated: (name, color) async {
          final result = await ref
              .read(manageTagsProvider.notifier)
              .createTag(name, color);
          if (!context.mounted) return;
          if (result == 'upgrade_required') {
            UpgradeSheet.show(
              context,
              title: 'Tags is a Pro feature',
              description:
                  'Upgrade to Spendz Pro to create unlimited tags.',
            );
          }
        },
      ),
    );
  }
}

// ── Usage banner ──────────────────────────────────────────────────────────────

class _UsageBanner extends StatelessWidget {
  const _UsageBanner({required this.used, required this.limit});

  final int used;
  final int limit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.label_outline_rounded,
              size: 16, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '$used / $limit custom tags used',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tag tile ──────────────────────────────────────────────────────────────────

class _TagTile extends StatelessWidget {
  const _TagTile({required this.tag, this.onDelete});

  final TagModel tag;
  final VoidCallback? onDelete;

  Color? _hexToColor(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length != 6) return null;
    return Color(int.parse('FF$h', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final color = _hexToColor(tag.color) ?? AppColors.textSecondary;
    return ListTile(
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.label_rounded, size: 16, color: color),
      ),
      title: Text(
        tag.name,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: tag.isDefault
          ? const Text(
              'Default',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            )
          : null,
      trailing: onDelete != null
          ? IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: AppColors.textTertiary),
              onPressed: onDelete,
            )
          : null,
    );
  }
}

// ── Delete confirm sheet ──────────────────────────────────────────────────────

class _DeleteConfirmSheet extends StatelessWidget {
  const _DeleteConfirmSheet({
    required this.tagName,
    required this.onConfirm,
  });

  final String tagName;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Delete "$tagName"?',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Expenses with this tag will keep their tag assignment, but this tag will no longer appear in filters.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    context.pop();
                    onConfirm();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.expenseLight,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                  child: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Add tag sheet ─────────────────────────────────────────────────────────────

class _AddTagSheet extends ConsumerStatefulWidget {
  const _AddTagSheet({required this.onCreated});

  final Future<void> Function(String name, String color) onCreated;

  @override
  ConsumerState<_AddTagSheet> createState() => _AddTagSheetState();
}

class _AddTagSheetState extends ConsumerState<_AddTagSheet> {
  final _nameController = TextEditingController();
  String _selectedColor = '#4A90D9';
  bool _loading = false;
  String? _error;

  static const _palette = [
    '#4A90D9',
    '#E24B4A',
    '#4DC8A0',
    '#FFB347',
    '#A78BFA',
    '#FF6B9D',
    '#34C6CD',
    '#FFD166',
    '#888780',
    '#5B8CFF',
    '#FF7C5B',
    '#BA7517',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a tag name.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    await widget.onCreated(name, _selectedColor);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'New Tag',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Tag name',
                hintStyle: const TextStyle(
                    fontSize: 14, color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide:
                      const BorderSide(color: AppColors.accent, width: 1.5),
                ),
                errorText: _error,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Color',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: _palette.map((hex) {
                final color = Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
                final isSelected = _selectedColor == hex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = hex),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(
                              color: AppColors.textPrimary, width: 2.5)
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.accentText,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accentText,
                      ),
                    )
                  : const Text(
                      'Create Tag',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
