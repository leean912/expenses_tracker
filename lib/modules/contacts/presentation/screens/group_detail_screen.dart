import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../expenses/utils/expense_ui_helpers.dart';
import '../../data/models/contact_model.dart';
import '../../data/models/group_model.dart';
import '../../providers/contacts_provider.dart';
import '../../providers/groups_provider.dart';
import '../widgets/group_split_bill_sheet.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsProvider);
    return groupsAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: _buildAppBar(context, null),
        body: Center(
          child: Text('Error: $e', style: const TextStyle(color: AppColors.textSecondary)),
        ),
      ),
      data: (groups) {
        final group = groups.where((g) => g.id == groupId).firstOrNull;
        if (group == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: _buildAppBar(context, null),
            body: const Center(
              child: Text('Group not found', style: TextStyle(color: AppColors.textSecondary)),
            ),
          );
        }
        return _GroupDetailBody(group: group);
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, String? title) {
    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textPrimary),
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
}

// ── Group detail body ─────────────────────────────────────────────────────────

class _GroupDetailBody extends ConsumerStatefulWidget {
  const _GroupDetailBody({required this.group});

  final GroupModel group;

  @override
  ConsumerState<_GroupDetailBody> createState() => _GroupDetailBodyState();
}

class _GroupDetailBodyState extends ConsumerState<_GroupDetailBody> {
  final Set<String> _removingIds = {};

  Future<void> _removeMember(String userId) async {
    setState(() => _removingIds.add(userId));
    await ref.read(groupsProvider.notifier).removeMember(widget.group.id, userId);
    if (mounted) setState(() => _removingIds.remove(userId));
  }

  void _showAddMemberSheet() {
    final currentMemberIds = widget.group.members.map((m) => m.id).toSet();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddMemberSheet(
        excludedUserIds: currentMemberIds,
        onAdd: (contact) async {
          Navigator.of(context).pop();
          final error = await ref.read(groupsProvider.notifier).addMember(
                widget.group.id,
                contact.friendId,
              );
          if (mounted && error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(error)),
            );
          }
        },
      ),
    );
  }

  void _openCreateSplitBill() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => GroupSplitBillSheet(group: widget.group),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final color = hexToColor(group.color);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: AppColors.textPrimary,
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          group.name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
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
          // Group header card
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.group_rounded, size: 22, color: color),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${group.members.length + 1} member${group.members.length + 1 == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Members label
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.sm),
            child: Row(
              children: [
                const Text(
                  'Members',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _showAddMemberSheet,
                  child: Row(
                    children: [
                      const Icon(Icons.add_rounded, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 2),
                      const Text(
                        'Add',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Members list
          Expanded(
            child: group.members.isEmpty
                ? const Center(
                    child: Text(
                      'No members yet.\nTap + to add someone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                    itemCount: group.members.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final member = group.members[index];
                      return _MemberTile(
                        member: member,
                        isRemoving: _removingIds.contains(member.id),
                        onRemove: () => _removeMember(member.id),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: FilledButton.icon(
            onPressed: _openCreateSplitBill,
            icon: const Icon(Icons.call_split_rounded, size: 18),
            label: const Text(
              'Create Split Bill',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.accentText,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Member tile ───────────────────────────────────────────────────────────────

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isRemoving,
    required this.onRemove,
  });

  final GroupMemberPreview member;
  final bool isRemoving;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(member.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEB),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Color(0xFF993C1D), size: 20),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              alignment: Alignment.center,
              child: Text(
                member.displayName[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
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
            if (isRemoving)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Add member sheet ──────────────────────────────────────────────────────────

class _AddMemberSheet extends ConsumerWidget {
  const _AddMemberSheet({
    required this.excludedUserIds,
    required this.onAdd,
  });

  final Set<String> excludedUserIds;
  final ValueChanged<ContactModel> onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(contactsProvider);

    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
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
                    'All contacts are already in this group.',
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
                  separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) {
                    final contact = available[index];
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
