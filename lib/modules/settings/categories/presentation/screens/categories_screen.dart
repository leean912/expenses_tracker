import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../service_locator.dart';
import '../../../../auth/providers/auth_provider.dart';
import '../../../../auth/providers/states/auth_state.dart';
import '../../../../expenses/data/models/category_model.dart';
import '../../../../expenses/providers/categories_provider.dart';
import '../../../../expenses/utils/expense_ui_helpers.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final user = ref.watch(authProvider).whenOrNull(authenticated: (u) => u);
    final isPremium = user?.subscriptionTier != 'free';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Categories',
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
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text(
            'Failed to load categories',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        data: (categories) {
          final customCount = categories.where((c) => !c.isDefault).length;
          return Column(
            children: [
              if (!isPremium) ...[
                _UsageBanner(
                  used: customCount,
                  limit: 5,
                  label: 'custom categories',
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  itemCount: categories.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, i) {
                    final cat = categories[i];
                    return _CategoryTile(
                      category: cat,
                      onDelete: cat.isDefault
                          ? null
                          : () => _confirmDelete(context, ref, cat.id),
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
          final categories = ref.read(categoriesProvider).valueOrNull ?? [];
          final customCount = categories.where((c) => !c.isDefault).length;
          final isPremiumNow =
              ref
                  .read(authProvider)
                  .whenOrNull(authenticated: (u) => u)
                  ?.subscriptionTier !=
              'free';

          if (!isPremiumNow && customCount >= 5) {
            _showUpgradeSheet(context, 5);
            return;
          }

          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _AddCategorySheet(
              nextSortOrder: categories.length + 1,
              onCreated: () => ref.invalidate(categoriesProvider),
            ),
          );
        },
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.accentText,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Category',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Delete category?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          "This won't affect existing expenses.",
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFE24B4A)),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await supabase
        .from('categories')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
    ref.invalidate(categoriesProvider);
  }

  void _showUpgradeSheet(BuildContext context, int limit) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _UpgradeSheet(feature: 'categories', limit: limit),
    );
  }
}

// ── Category tile ─────────────────────────────────────────────────────────────

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, this.onDelete});

  final CategoryModel category;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final color = hexToColor(category.color);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xs,
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(iconForName(category.icon), size: 18, color: color),
      ),
      title: Text(
        category.name,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      trailing: category.isDefault
          ? Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: const Text(
                'Default',
                style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
              ),
            )
          : IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
              onPressed: onDelete,
            ),
    );
  }
}

// ── Usage banner ──────────────────────────────────────────────────────────────

class _UsageBanner extends StatelessWidget {
  const _UsageBanner({
    required this.used,
    required this.limit,
    required this.label,
  });

  final int used;
  final int limit;
  final String label;

  @override
  Widget build(BuildContext context) {
    final remaining = limit - used;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$used / $limit $label',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          if (remaining <= 1)
            Text(
              remaining == 0 ? 'Limit reached' : '1 slot left',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: remaining == 0
                    ? const Color(0xFFE24B4A)
                    : AppColors.budgetOverallBar,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Add category sheet ────────────────────────────────────────────────────────

class _AddCategorySheet extends ConsumerStatefulWidget {
  const _AddCategorySheet({
    required this.nextSortOrder,
    required this.onCreated,
  });

  final int nextSortOrder;
  final VoidCallback onCreated;

  @override
  ConsumerState<_AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends ConsumerState<_AddCategorySheet> {
  final _nameController = TextEditingController();
  String _selectedIcon = kIconNames.first;
  String _selectedColor = kCategoryColors.first;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a name');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await supabase.from('categories').insert({
        'user_id': supabase.auth.currentUser!.id,
        'name': name,
        'icon': _selectedIcon,
        'color': _selectedColor,
        'is_default': false,
        'sort_order': widget.nextSortOrder,
      });
      widget.onCreated();
      if (mounted) context.pop();
    } on PostgrestException catch (e) {
      if (e.hint == 'upgrade_required') {
        if (mounted) {
          context.pop();
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (_) =>
                const _UpgradeSheet(feature: 'categories', limit: 5),
          );
        }
      } else {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xxl),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderDashed,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Text(
                'Add Category',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Name
              const _Label('Name'),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. Coffee, Gym, Subscriptions',
                  hintStyle: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 14,
                  ),
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
                    borderSide: const BorderSide(
                      color: AppColors.accent,
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.lg,
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFE24B4A),
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.xxl),

              // Color
              const _Label('Color'),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: kCategoryColors.map((hex) {
                  final color = hexToColor(hex);
                  final isSelected = hex == _selectedColor;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = hex),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.textPrimary
                              : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // Icon
              const _Label('Icon'),
              const SizedBox(height: AppSpacing.md),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.border),
                ),
                child: Wrap(
                  children: kIconNames.map((name) {
                    final isSelected = name == _selectedIcon;
                    final color = hexToColor(_selectedColor);
                    return GestureDetector(
                      onTap: () => setState(() => _selectedIcon = name),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.all(AppSpacing.xs),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Icon(
                          iconForName(name),
                          size: 20,
                          color: isSelected ? color : AppColors.textTertiary,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.accentText,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accentText,
                          ),
                        )
                      : const Text(
                          'Save',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Upgrade sheet ─────────────────────────────────────────────────────────────

class _UpgradeSheet extends StatelessWidget {
  const _UpgradeSheet({required this.feature, required this.limit});

  final String feature;
  final int limit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.workspace_premium_rounded,
            size: 40,
            color: AppColors.budgetOverallBar,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            "You've used all $limit custom $feature!",
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Upgrade to Premium for unlimited categories, accounts, and groups.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.budgetOverallBar,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
              ),
              child: const Text(
                'Upgrade to Premium',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text(
              'Maybe later',
              style: TextStyle(color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sheet label ───────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textTertiary,
        letterSpacing: 0.5,
      ),
    );
  }
}
