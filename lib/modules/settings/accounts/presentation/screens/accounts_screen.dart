import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/widgets/upgrade_sheet.dart';
import '../../../../../service_locator.dart';
import '../../../../auth/providers/auth_provider.dart';
import '../../../../auth/providers/states/auth_state.dart';
import '../../../../expenses/data/models/account_model.dart';
import '../../../../expenses/providers/accounts_provider.dart';
import '../../../../expenses/utils/expense_ui_helpers.dart';
import '../../../../subscription/providers/subscription_provider.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);
    final isPremium = ref.watch(isPremiumProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Accounts',
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
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text(
            'Failed to load accounts',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        data: (accounts) {
          final freeCustomCount = accounts
              .where((a) => !a.isDefault && !a.requiresPremium)
              .length;

          const typeOrder = [
            'wallet', 'bank', 'cash', 'credit_card',
            'investment', 'loan', 'other',
          ];
          final grouped = <String, List<AccountModel>>{};
          for (final t in typeOrder) {
            final group = accounts.where((a) => a.accountType == t).toList();
            if (group.isNotEmpty) grouped[t] = group;
          }
          final ungrouped = accounts
              .where((a) => !typeOrder.contains(a.accountType))
              .toList();
          if (ungrouped.isNotEmpty) grouped['other'] = [...(grouped['other'] ?? []), ...ungrouped];

          final sections = grouped.entries.toList();

          return Column(
            children: [
              if (!isPremium) ...[
                _UsageBanner(
                  used: freeCustomCount,
                  limit: 5,
                  label: 'custom accounts',
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  itemCount: sections.length,
                  itemBuilder: (context, si) {
                    final label = const {
                      'wallet': 'Wallet',
                      'bank': 'Bank',
                      'cash': 'Cash',
                      'credit_card': 'Credit Card',
                      'investment': 'Investment',
                      'loan': 'Loan',
                      'other': 'Other',
                    }[sections[si].key] ?? sections[si].key;
                    final group = sections[si].value;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xs,
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        const Divider(height: 1, color: AppColors.border),
                        ...group.map((acc) {
                          final isGreyed = !isPremium && acc.requiresPremium;
                          return Column(
                            children: [
                              _AccountTile(
                                account: acc,
                                isGreyed: isGreyed,
                                onDelete: acc.isDefault
                                    ? null
                                    : () => _confirmDelete(context, ref, acc.id),
                              ),
                              const Divider(height: 1, color: AppColors.border),
                            ],
                          );
                        }),
                      ],
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
          final accounts = ref.read(accountsProvider).valueOrNull ?? [];
          final freeCustomCount = accounts
              .where((a) => !a.isDefault && !a.requiresPremium)
              .length;
          final isPremiumNow = ref.read(isPremiumProvider);
          final defaultCurrency =
              ref
                  .read(authProvider)
                  .whenOrNull(authenticated: (u) => u)
                  ?.defaultCurrency ??
              'MYR';

          if (!isPremiumNow && freeCustomCount >= 5) {
            _showUpgradeSheet(context, 5);
            return;
          }

          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _AddAccountSheet(
              defaultCurrency: defaultCurrency,
              nextSortOrder: accounts.length + 1,
              onCreated: () => ref.invalidate(accountsProvider),
            ),
          );
        },
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.accentText,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Account',
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
          'Delete account?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          "This won't affect existing expenses.",
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => ctx.pop(true),
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
        .from('accounts')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
    ref.invalidate(accountsProvider);
  }

  void _showUpgradeSheet(BuildContext context, int limit) {
    UpgradeSheet.show(
      context,
      title: "You've used all $limit custom accounts!",
      description:
          'Upgrade to Premium for unlimited categories, accounts, and groups.',
    );
  }
}

// ── Account tile ──────────────────────────────────────────────────────────────

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    this.isGreyed = false,
    this.onDelete,
  });

  final AccountModel account;
  final bool isGreyed;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final color = hexToColor(account.color);
    final effectiveColor = isGreyed ? color.withValues(alpha: 0.35) : color;
    return Opacity(
      opacity: isGreyed ? 0.5 : 1.0,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xs,
        ),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: effectiveColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            iconForName(account.icon),
            size: 18,
            color: effectiveColor,
          ),
        ),
        title: Text(
          account.name,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          account.currency,
          style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
        ),
        trailing: account.isDefault
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
            : isGreyed
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
                  'Premium',
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
          if (remaining <= 2)
            Text(
              remaining == 0
                  ? 'Limit reached'
                  : '$remaining slot${remaining == 1 ? '' : 's'} left',
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

// ── Add account sheet ─────────────────────────────────────────────────────────

class _AddAccountSheet extends ConsumerStatefulWidget {
  const _AddAccountSheet({
    required this.defaultCurrency,
    required this.nextSortOrder,
    required this.onCreated,
  });

  final String defaultCurrency;
  final int nextSortOrder;
  final VoidCallback onCreated;

  @override
  ConsumerState<_AddAccountSheet> createState() => _AddAccountSheetState();
}

const _accountTypes = [
  ('wallet', 'Wallet'),
  ('bank', 'Bank'),
  ('cash', 'Cash'),
  ('credit_card', 'Credit Card'),
  ('investment', 'Investment'),
  ('loan', 'Loan'),
  ('other', 'Other'),
];

class _AddAccountSheetState extends ConsumerState<_AddAccountSheet> {
  final _nameController = TextEditingController();
  String _selectedIcon = 'account_balance_wallet';
  String _selectedColor = kCategoryColors[4];
  String _selectedType = 'wallet';
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
      await supabase.rpc(
        'create_account',
        params: {
          'p_name': name,
          'p_account_type': _selectedType,
          'p_icon': _selectedIcon,
          'p_color': _selectedColor,
          'p_currency': widget.defaultCurrency,
        },
      );
      widget.onCreated();
      if (mounted) context.pop();
    } on PostgrestException catch (e) {
      if (e.hint == 'upgrade_required') {
        if (mounted) {
          context.pop();
          UpgradeSheet.show(
            context,
            title: "You've used all 5 custom accounts!",
            description:
                'Upgrade to Premium for unlimited categories, accounts, and groups.',
          );
        }
      } else if (e.hint == 'duplicate_name') {
        setState(() {
          _error = 'An account with this name already exists.';
          _loading = false;
        });
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
                'Add Account',
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
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. Maybank Savings, Touch\'n Go',
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

              // Type
              const _Label('Type'),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: _accountTypes.map(((String, String) t) {
                  final isSelected = t.$1 == _selectedType;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedType = t.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.accent
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.accent
                              : AppColors.borderDashed,
                        ),
                      ),
                      child: Text(
                        t.$2,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? AppColors.accentText
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

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
                  children: kAccountIconNames.map((name) {
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
