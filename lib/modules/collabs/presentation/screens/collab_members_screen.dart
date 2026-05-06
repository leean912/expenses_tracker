import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../service_locator.dart';
import '../../../contacts/data/models/contact_model.dart';
import '../../../contacts/providers/contacts_provider.dart';
import '../../data/models/collab_model.dart';
import '../../providers/collab_expenses_provider.dart';
import '../../providers/collabs_provider.dart';

class CollabMembersScreen extends ConsumerWidget {
  const CollabMembersScreen({super.key, required this.collabId});

  final String collabId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collabsAsync = ref.watch(collabsProvider);
    return collabsAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: _appBar(context, null),
        body: Center(
          child: Text(
            'Error: $e',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ),
      data: (collabs) {
        final collab = collabs.where((c) => c.id == collabId).firstOrNull;
        if (collab == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: _appBar(context, null),
            body: const Center(
              child: Text(
                'Collab not found',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }
        return _MembersBody(collab: collab);
      },
    );
  }

  PreferredSizeWidget _appBar(BuildContext context, String? title) => AppBar(
    backgroundColor: AppColors.background,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    leading: IconButton(
      icon: const Icon(
        Icons.arrow_back_ios_new_rounded,
        size: 18,
        color: AppColors.textPrimary,
      ),
      onPressed: () => context.pop(),
    ),
    title: title != null
        ? Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          )
        : null,
  );
}

// ── Members body ──────────────────────────────────────────────────────────────

class _MembersBody extends ConsumerStatefulWidget {
  const _MembersBody({required this.collab});

  final CollabModel collab;

  @override
  ConsumerState<_MembersBody> createState() => _MembersBodyState();
}

class _MembersBodyState extends ConsumerState<_MembersBody> {
  CollabModel get collab => widget.collab;
  String get _currentUserId => supabase.auth.currentUser?.id ?? '';
  bool get _isOwner => collab.ownerId == _currentUserId;
  final Set<String> _removingIds = {};

  void _showAddMemberSheet() {
    final currentIds = collab.members
        .where((m) => m.isActive)
        .map((m) => m.userId)
        .toSet();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddMemberSheet(
        excludedUserIds: currentIds,
        onAdd: (contact) async {
          context.pop();
          final error = await ref
              .read(collabsProvider.notifier)
              .addMember(collab.id, contact.friendId);
          if (mounted && error != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error)));
          }
        },
      ),
    );
  }

  Future<void> _removeMember(String userId) async {
    setState(() => _removingIds.add(userId));
    final error = await ref
        .read(collabsProvider.notifier)
        .removeMember(collab.id, userId);
    if (mounted) {
      setState(() => _removingIds.remove(userId));
      if (error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    }
  }

  void _showPersonalBudgetDialog(CollabMemberModel member, bool isOwnRow) {
    final controller = TextEditingController(
      text: member.personalBudgetCents != null
          ? (member.personalBudgetCents! / 100).toStringAsFixed(2)
          : '',
    );
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          isOwnRow ? 'My Personal Budget' : '${member.displayName}\'s Budget',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Personal spending cap in ${collab.homeCurrency}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'e.g. 500.00',
                hintStyle: const TextStyle(color: AppColors.textTertiary),
                prefixText: '${collab.homeCurrency} ',
                prefixStyle: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          if (member.personalBudgetCents != null)
            TextButton(
              onPressed: () async {
                context.pop();
                await ref
                    .read(collabsProvider.notifier)
                    .updatePersonalBudget(
                      collabId: collab.id,
                      memberId: member.id,
                      budgetCents: null,
                    );
              },
              child: const Text(
                'Remove',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          TextButton(
            onPressed: () => context.pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              final amount = double.tryParse(controller.text.trim());
              context.pop();
              if (amount != null && amount > 0) {
                await ref
                    .read(collabsProvider.notifier)
                    .updatePersonalBudget(
                      collabId: collab.id,
                      memberId: member.id,
                      budgetCents: (amount * 100).round(),
                    );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _leaveCollab() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Leave collab?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: const Text(
          'Your own expenses remain in your personal books.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => context.pop(true),
            child: const Text(
              'Leave',
              style: TextStyle(color: Color(0xFF993C1D)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await ref
        .read(collabsProvider.notifier)
        .leaveCollab(collab.id);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    } else {
      context
        ..pop()
        ..pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(collabExpensesProvider(collab.id));
    final activeMembers = collab.members.where((m) => m.isActive).toList();

    // Compute per-member spending from already-loaded expenses
    final Map<String, int> spentByUser = {};
    expensesAsync.valueOrNull?.expenses.forEach((e) {
      spentByUser[e.userId] = (spentByUser[e.userId] ?? 0) + e.homeAmountCents;
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: AppColors.textPrimary,
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Members',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          if (_isOwner && collab.isActive)
            IconButton(
              icon: const Icon(
                Icons.person_add_rounded,
                size: 20,
                color: AppColors.textPrimary,
              ),
              onPressed: _showAddMemberSheet,
              tooltip: 'Add member',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.xxl,
              ),
              itemCount: activeMembers.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final member = activeMembers[index];
                final isOwnRow = member.userId == _currentUserId;
                final spentCents = spentByUser[member.userId] ?? 0;
                final canRemove = _isOwner && !isOwnRow && collab.isActive;
                final canEditBudget = (isOwnRow || _isOwner) && collab.isActive;

                return _MemberTile(
                  member: member,
                  collab: collab,
                  spentCents: spentCents,
                  isOwnRow: isOwnRow,
                  isRemoving: _removingIds.contains(member.userId),
                  canRemove: canRemove,
                  canEditBudget: canEditBudget,
                  onRemove: canRemove
                      ? () => _removeMember(member.userId)
                      : null,
                  onEditBudget: canEditBudget
                      ? () => _showPersonalBudgetDialog(member, isOwnRow)
                      : null,
                );
              },
            ),
          ),

          // Leave button for non-owners
          if (!_isOwner && collab.isActive)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                child: OutlinedButton(
                  onPressed: _leaveCollab,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF993C1D),
                    side: const BorderSide(color: Color(0xFF993C1D)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    minimumSize: const Size(double.infinity, 0),
                  ),
                  child: const Text(
                    'Leave Collab',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Member tile ───────────────────────────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.collab,
    required this.spentCents,
    required this.isOwnRow,
    required this.isRemoving,
    required this.canRemove,
    required this.canEditBudget,
    this.onRemove,
    this.onEditBudget,
  });

  final CollabMemberModel member;
  final CollabModel collab;
  final int spentCents;
  final bool isOwnRow;
  final bool isRemoving;
  final bool canRemove;
  final bool canEditBudget;
  final VoidCallback? onRemove;
  final VoidCallback? onEditBudget;

  @override
  Widget build(BuildContext context) {
    final hasBudget =
        member.personalBudgetCents != null && member.personalBudgetCents! > 0;
    final budgetCents = member.personalBudgetCents ?? 0;
    final overBudget = hasBudget && spentCents > budgetCents;
    final progress = hasBudget
        ? (spentCents / budgetCents).clamp(0.0, 1.0)
        : 0.0;

    Widget tile = GestureDetector(
      onTap: canEditBudget ? onEditBudget : null,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Avatar
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    member.displayName.isNotEmpty
                        ? member.displayName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),

                // Name + role
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            isOwnRow ? 'You' : member.displayName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (member.isOwner) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                              ),
                              child: const Text(
                                'Owner',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.accent,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (member.username != null)
                        Text(
                          '@${member.username}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),

                // Spent amount
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${collab.homeCurrency} ${(spentCents / 100).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: overBudget
                            ? const Color(0xFF993C1D)
                            : AppColors.textPrimary,
                      ),
                    ),
                    const Text(
                      'spent',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),

                if (isRemoving) ...[
                  const SizedBox(width: AppSpacing.md),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),

            // Personal budget section
            if (hasBudget || canEditBudget) ...[
              const SizedBox(height: AppSpacing.lg),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: AppSpacing.lg),
              if (hasBudget) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Personal budget',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    Text(
                      '${collab.homeCurrency} ${(budgetCents / 100).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: AppColors.surfaceMuted,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      overBudget
                          ? const Color(0xFF993C1D)
                          : AppColors.budgetOverallBar,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  overBudget
                      ? '${collab.homeCurrency} ${((spentCents - budgetCents) / 100).toStringAsFixed(2)} over'
                      : '${collab.homeCurrency} ${((budgetCents - spentCents) / 100).toStringAsFixed(2)} left',
                  style: TextStyle(
                    fontSize: 11,
                    color: overBudget
                        ? const Color(0xFF993C1D)
                        : AppColors.textTertiary,
                  ),
                ),
              ] else if (canEditBudget) ...[
                GestureDetector(
                  onTap: onEditBudget,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.add_rounded,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isOwnRow
                            ? 'Set my personal budget'
                            : 'Set personal budget',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );

    if (!canRemove) return tile;

    return Dismissible(
      key: Key(member.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(
              'Remove ${member.displayName}?',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            content: const Text(
              'Their existing expenses remain in their personal books.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => context.pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => context.pop(true),
                child: const Text(
                  'Remove',
                  style: TextStyle(color: Color(0xFF993C1D)),
                ),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onRemove?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEB),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(
          Icons.person_remove_outlined,
          color: Color(0xFF993C1D),
          size: 20,
        ),
      ),
      child: tile,
    );
  }
}

// ── Add member sheet ──────────────────────────────────────────────────────────

class _AddMemberSheet extends ConsumerWidget {
  const _AddMemberSheet({required this.excludedUserIds, required this.onAdd});

  final Set<String> excludedUserIds;
  final ValueChanged<ContactModel> onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(contactsProvider);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.xxl,
              AppSpacing.xxl,
              AppSpacing.lg,
            ),
            child: const Text(
              'Add member',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          contactsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Text(
                'Failed to load contacts',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            data: (contacts) {
              final available = contacts
                  .where((c) => !excludedUserIds.contains(c.friendId))
                  .toList();
              if (available.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Text(
                    'All contacts are already in this collab.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: available.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, i) {
                    final contact = available[i];
                    return ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: AppColors.surfaceMuted,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          contact.displayName[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      title: Text(
                        contact.displayName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: contact.username != null
                          ? Text(
                              '@${contact.username}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textTertiary,
                              ),
                            )
                          : null,
                      onTap: () => onAdd(contact),
                      dense: true,
                    );
                  },
                ),
              );
            },
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
