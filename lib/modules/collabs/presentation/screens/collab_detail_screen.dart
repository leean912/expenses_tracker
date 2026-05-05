import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/amount_input_formatter.dart';
import '../../../../service_locator.dart';
import '../../../expenses/data/models/account_model.dart';
import '../../../expenses/data/models/category_model.dart';
import '../../../expenses/providers/accounts_provider.dart';
import '../../../expenses/providers/categories_provider.dart';
import '../../../expenses/utils/expense_ui_helpers.dart';
import '../../data/models/collab_model.dart';
import '../../providers/collab_expenses_provider.dart';
import '../../providers/collabs_provider.dart';
import '../widgets/collab_split_bill_sheet.dart';

class CollabDetailScreen extends ConsumerWidget {
  const CollabDetailScreen({super.key, required this.collabId});

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
        appBar: _buildAppBar(context, null, null),
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
            appBar: _buildAppBar(context, null, null),
            body: const Center(
              child: Text(
                'Collab not found',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }
        return _CollabDetailBody(collab: collab);
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    String? title,
    Widget? actions,
  ) {
    return AppBar(
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
      actions: actions != null ? [actions] : null,
    );
  }
}

// ── Detail body ───────────────────────────────────────────────────────────────

class _CollabDetailBody extends ConsumerStatefulWidget {
  const _CollabDetailBody({required this.collab});

  final CollabModel collab;

  @override
  ConsumerState<_CollabDetailBody> createState() => _CollabDetailBodyState();
}

class _CollabDetailBodyState extends ConsumerState<_CollabDetailBody> {
  CollabModel get collab => widget.collab;

  String get _currentUserId => supabase.auth.currentUser?.id ?? '';
  bool get _isOwner => collab.ownerId == _currentUserId;

  void _openAddExpense() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddCollabExpenseSheet(collab: collab),
    ).then(
      (_) => ref.read(collabExpensesProvider(collab.id).notifier).refresh(),
    );
  }

  void _showMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CollabMenuSheet(
        collab: collab,
        isOwner: _isOwner,
        onSplitBill: () {
          context.pop();
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => CollabSplitBillSheet(collab: collab),
          );
        },
        onEdit: () {
          context.pop();
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _EditCollabSheet(collab: collab),
          );
        },
        onClose: () async {
          context.pop();
          final error = await ref
              .read(collabsProvider.notifier)
              .closeCollab(collab.id);
          if (!mounted) return;
          if (error != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error)));
          } else {
            context.pop();
          }
        },
        onLeave: () async {
          context.pop();
          final error = await ref
              .read(collabsProvider.notifier)
              .leaveCollab(collab.id);
          if (!mounted) return;
          if (error != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error)));
          } else {
            context.pop();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(collabExpensesProvider(collab.id));
    final activeMembers = collab.members.where((m) => m.isActive).toList();

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
        title: Text(
          collab.name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.more_horiz_rounded,
              size: 22,
              color: AppColors.textPrimary,
            ),
            onPressed: _showMenu,
          ),
        ],
      ),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Failed to load expenses.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref
                    .read(collabExpensesProvider(collab.id).notifier)
                    .refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (state) {
          final grouped = _groupByDate(state.expenses);
          return CustomScrollView(
            slivers: [
              // ── Header ───────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: _CollabHeader(
                  collab: collab,
                  members: activeMembers,
                  spentCents: state.totalHomeAmountCents,
                  onMembersTap: () =>
                      context.push('$collabDetailRoute/${collab.id}/members'),
                ),
              ),

              // ── Empty state ───────────────────────────────────────────────
              if (state.expenses.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No expenses yet.\nTap + to add the first one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                )
              else ...[
                for (final entry in grouped.entries) ...[
                  // Date header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.xl,
                        AppSpacing.xl,
                        AppSpacing.sm,
                      ),
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textTertiary,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                  // Expense rows
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                    ),
                    sliver: SliverList.separated(
                      itemCount: entry.value.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) {
                        final expense = entry.value[i];
                        final isOwn = expense.userId == _currentUserId;
                        return _ExpenseTile(
                          expense: expense,
                          collab: collab,
                          isOwn: isOwn,
                        );
                      },
                    ),
                  ),
                ],
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.xxl * 4),
                ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: collab.isActive
          ? FloatingActionButton.extended(
              onPressed: _openAddExpense,
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.accentText,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text(
                'Add Expense',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            )
          : null,
    );
  }

  Map<String, List<CollabExpense>> _groupByDate(List<CollabExpense> expenses) {
    final map = <String, List<CollabExpense>>{};
    for (final e in expenses) {
      final key = _formatDateHeader(e.expenseDate);
      map.putIfAbsent(key, () => []).add(e);
    }
    return map;
  }

  String _formatDateHeader(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(d.year, d.month, d.day);
    if (date == today) return 'Today';
    if (date == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('d MMM yyyy').format(d);
  }
}

// ── Collab header ─────────────────────────────────────────────────────────────

class _CollabHeader extends StatelessWidget {
  const _CollabHeader({
    required this.collab,
    required this.members,
    required this.spentCents,
    required this.onMembersTap,
  });

  final CollabModel collab;
  final List<CollabMemberModel> members;
  final int spentCents;
  final VoidCallback onMembersTap;

  @override
  Widget build(BuildContext context) {
    final hasBudget = collab.budgetCents != null && collab.budgetCents! > 0;
    final budgetCents = collab.budgetCents ?? 0;
    final progress = hasBudget
        ? (spentCents / budgetCents).clamp(0.0, 1.0)
        : 0.0;
    final overBudget = hasBudget && spentCents > budgetCents;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: currency badge + status
            Row(
              children: [
                if (collab.isForeignCurrency) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '${collab.currency}  ←  ${collab.homeCurrency}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                if (collab.isClosed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: const Text(
                      'Closed',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                const Spacer(),
                const Icon(
                  Icons.people_outline_rounded,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${members.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),

            // Budget section
            if (hasBudget) ...[
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Spent ${collab.homeCurrency} ${_fmt(spentCents)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: overBudget
                          ? const Color(0xFF993C1D)
                          : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'of ${collab.homeCurrency} ${_fmt(budgetCents)}',
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
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceMuted,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    overBudget
                        ? const Color(0xFF993C1D)
                        : AppColors.budgetOverallBar,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                overBudget
                    ? '${collab.homeCurrency} ${_fmt(spentCents - budgetCents)} over budget'
                    : '${collab.homeCurrency} ${_fmt(budgetCents - spentCents)} remaining',
                style: TextStyle(
                  fontSize: 11,
                  color: overBudget
                      ? const Color(0xFF993C1D)
                      : AppColors.textTertiary,
                ),
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                '${collab.homeCurrency} ${_fmt(spentCents)} spent',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],

            // Exchange rate hint
            if (collab.isForeignCurrency && collab.exchangeRate != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '1 ${collab.homeCurrency} = ${collab.exchangeRate!.toStringAsFixed(collab.exchangeRate! >= 10 ? 0 : 2)} ${collab.currency}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                ),
              ),
            ],

            // Member avatars strip
            if (members.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: AppSpacing.xl),
              GestureDetector(
                onTap: onMembersTap,
                child: Row(
                  children: [
                    Expanded(child: _MemberStrip(members: members)),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(int cents) => (cents / 100).toStringAsFixed(2);
}

// ── Member strip ──────────────────────────────────────────────────────────────

class _MemberStrip extends StatelessWidget {
  const _MemberStrip({required this.members});

  final List<CollabMemberModel> members;

  @override
  Widget build(BuildContext context) {
    const maxVisible = 5;
    final visible = members.take(maxVisible).toList();
    final overflow = members.length - maxVisible;

    return Row(
      children: [
        for (final m in visible)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: _Avatar(name: m.displayName, isOwner: m.isOwner),
          ),
        if (overflow > 0)
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: Text(
              '+$overflow',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
              ),
            ),
          ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.isOwner = false});

  final String name;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        if (isOwner)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Expense tile ──────────────────────────────────────────────────────────────

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({
    required this.expense,
    required this.collab,
    required this.isOwn,
  });

  final CollabExpense expense;
  final CollabModel collab;
  final bool isOwn;

  @override
  Widget build(BuildContext context) {
    final hasCategory = expense.categoryName != null;
    final catColor = hasCategory
        ? hexToColor(expense.categoryColor ?? '#888780')
        : AppColors.textTertiary;

    final primaryAmount =
        '${collab.currency} ${_fmtAmount(expense.amountCents, expense.currency)}';
    final showHomeAmount = collab.isForeignCurrency;
    final homeAmount = showHomeAmount
        ? '${collab.homeCurrency} ${(expense.homeAmountCents / 100).toStringAsFixed(2)}'
        : null;

    return Container(
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
          // Category icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasCategory
                  ? iconForName(expense.categoryIcon ?? 'category')
                  : Icons.receipt_long_outlined,
              size: 16,
              color: catColor,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),

          // Note + owner
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.note?.isNotEmpty == true
                      ? expense.note!
                      : expense.categoryName ?? 'Expense',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isOwn
                            ? AppColors.accent.withValues(alpha: 0.1)
                            : AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        isOwn ? 'You' : expense.ownerDisplayName,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isOwn
                              ? AppColors.accent
                              : AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                primaryAmount,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (homeAmount != null)
                Text(
                  homeAmount,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtAmount(int cents, String currency) {
    // For JPY and KRW (no decimal), show as whole number
    final noDecimal = {'JPY', 'KRW', 'VND', 'IDR'}.contains(currency);
    if (noDecimal) return (cents ~/ 100).toString();
    return (cents / 100).toStringAsFixed(2);
  }
}

// ── Collab menu sheet ─────────────────────────────────────────────────────────

class _CollabMenuSheet extends StatelessWidget {
  const _CollabMenuSheet({
    required this.collab,
    required this.isOwner,
    required this.onClose,
    required this.onLeave,
    required this.onSplitBill,
    required this.onEdit,
  });

  final CollabModel collab;
  final bool isOwner;
  final VoidCallback onClose;
  final VoidCallback onLeave;
  final VoidCallback onSplitBill;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
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
        children: [
          if (collab.isActive) ...[
            ListTile(
              leading: const Icon(
                Icons.receipt_long_rounded,
                color: AppColors.textSecondary,
              ),
              title: const Text(
                'Create Split Bill',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              onTap: onSplitBill,
            ),
          ],
          if (isOwner) ...[
            ListTile(
              leading: const Icon(
                Icons.edit_outlined,
                color: AppColors.textSecondary,
              ),
              title: const Text(
                'Edit Collab',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              onTap: onEdit,
            ),
          ],
          if (isOwner && collab.isActive) ...[
            ListTile(
              leading: const Icon(
                Icons.lock_outline_rounded,
                color: AppColors.textSecondary,
              ),
              title: const Text(
                'Close Collab',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              subtitle: const Text(
                'Makes it read-only. Unsettled splits remain.',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: const Text(
                      'Close collab?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    content: const Text(
                      'No new expenses can be added after closing. '
                      'Existing expenses are untouched.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Close Collab'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) onClose();
              },
            ),
          ],
          if (!isOwner) ...[
            ListTile(
              leading: const Icon(
                Icons.logout_rounded,
                color: Color(0xFF993C1D),
              ),
              title: const Text(
                'Leave Collab',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF993C1D),
                ),
              ),
              onTap: () async {
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
                      'You will no longer see this collab. '
                      'Your own expenses remain in your personal books.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text(
                          'Leave',
                          style: TextStyle(color: Color(0xFF993C1D)),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) onLeave();
              },
            ),
          ],
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

// ── Edit collab sheet ─────────────────────────────────────────────────────────

class _EditCollabSheet extends ConsumerStatefulWidget {
  const _EditCollabSheet({required this.collab});

  final CollabModel collab;

  @override
  ConsumerState<_EditCollabSheet> createState() => _EditCollabSheetState();
}

class _EditCollabSheetState extends ConsumerState<_EditCollabSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;

  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = false;
  String? _error;

  CollabModel get collab => widget.collab;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: collab.name);
    _descController = TextEditingController(text: collab.description ?? '');
    _startDate = collab.startDate;
    _endDate = collab.endDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? d) {
    if (d == null) return 'Not set';
    return DateFormat('d MMM yyyy').format(d);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.accent,
            onPrimary: AppColors.accentText,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await ref
        .read(collabsProvider.notifier)
        .updateCollab(
          collabId: collab.id,
          name: name,
          description: _descController.text.trim().isEmpty
              ? null
              : _descController.text.trim(),
          startDate: _startDate,
          endDate: _endDate,
        );
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      setState(() => _error = error);
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Edit Collab',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _nameController,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _descController,
              maxLines: 3,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickDate(isStart: true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Start',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDate(_startDate),
                            style: TextStyle(
                              fontSize: 13,
                              color: _startDate != null
                                  ? AppColors.textPrimary
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickDate(isStart: false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'End',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDate(_endDate),
                            style: TextStyle(
                              fontSize: 13,
                              color: _endDate != null
                                  ? AppColors.textPrimary
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: Color(0xFF993C1D)),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.accentText,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add collab expense sheet ───────────────────────────────────────────────────

class _AddCollabExpenseSheet extends ConsumerStatefulWidget {
  const _AddCollabExpenseSheet({required this.collab});

  final CollabModel collab;

  @override
  ConsumerState<_AddCollabExpenseSheet> createState() =>
      _AddCollabExpenseSheetState();
}

class _AddCollabExpenseSheetState
    extends ConsumerState<_AddCollabExpenseSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _rateController = TextEditingController();

  String? _selectedCategoryId;
  String? _selectedAccountId;
  DateTime _selectedDate = DateTime.now();
  bool _loading = false;
  String? _error;

  CollabModel get collab => widget.collab;

  @override
  void initState() {
    super.initState();
    if (collab.isForeignCurrency && collab.exchangeRate != null) {
      _rateController.text = collab.exchangeRate!.toStringAsFixed(
        collab.exchangeRate! >= 10 ? 0 : 4,
      );
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    return DateFormat('d MMM yyyy').format(d);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.accent,
            onPrimary: AppColors.accentText,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _submit() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      setState(() => _error = 'Please enter an amount.');
      return;
    }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Invalid amount.');
      return;
    }

    double? rate;
    if (collab.isForeignCurrency) {
      rate = double.tryParse(_rateController.text.trim());
      if (rate == null || rate <= 0) {
        setState(() => _error = 'Please enter a valid exchange rate.');
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final amountCents = (amount * 100).round();
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final userId = supabase.auth.currentUser!.id;

      int homeAmountCents;
      if (collab.isForeignCurrency && rate != null) {
        homeAmountCents = (amountCents / rate).round();
      } else {
        homeAmountCents = amountCents;
      }

      final payload = <String, dynamic>{
        'user_id': userId,
        'type': 'expense',
        'source': 'manual',
        'collab_id': collab.id,
        'amount_cents': amountCents,
        'currency': collab.currency,
        'home_amount_cents': homeAmountCents,
        'home_currency': collab.homeCurrency,
        'expense_date': dateStr,
      };

      if (collab.isForeignCurrency && rate != null) {
        payload['conversion_rate'] = rate;
      }
      if (_selectedCategoryId != null) {
        payload['category_id'] = _selectedCategoryId;
      }
      if (_selectedAccountId != null) {
        payload['account_id'] = _selectedAccountId;
      }
      final note = _noteController.text.trim();
      if (note.isNotEmpty) payload['note'] = note;

      await supabase.from('expenses').insert(payload);

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to add expense. Please try again.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final accountsAsync = ref.watch(accountsProvider);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.9,
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xxl),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Add Expense',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            collab.name,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.textSecondary,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surfaceMuted,
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(AppSpacing.sm),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),

              // Form
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Amount
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Text(
                              collab.currency,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textTertiary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: TextField(
                                controller: _amountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [AmountInputFormatter()],
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.5,
                                ),
                                textAlign: TextAlign.right,
                                decoration: const InputDecoration(
                                  hintText: '0.00',
                                  hintStyle: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ],
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

                      // Exchange rate (foreign currency only)
                      if (collab.isForeignCurrency) ...[
                        const SizedBox(height: AppSpacing.xxl),
                        _Label(
                          '1 ${collab.homeCurrency} = ? ${collab.currency}',
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextField(
                          controller: _rateController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'),
                            ),
                          ],
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'e.g. 30',
                            hintStyle: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 14,
                            ),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              borderSide: const BorderSide(
                                color: AppColors.border,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              borderSide: const BorderSide(
                                color: AppColors.border,
                              ),
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
                      ],

                      const SizedBox(height: AppSpacing.xxl),

                      // Category
                      const _Label('Category'),
                      const SizedBox(height: AppSpacing.md),
                      categoriesAsync.when(
                        data: (cats) => _CategoryPicker(
                          categories: cats,
                          selectedId: _selectedCategoryId,
                          onSelect: (id) =>
                              setState(() => _selectedCategoryId = id),
                        ),
                        loading: () => const SizedBox(
                          height: 40,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                        error: (_, _) => const Text(
                          'Failed to load categories',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.xxl),

                      // Account
                      const _Label('Account'),
                      const SizedBox(height: AppSpacing.md),
                      accountsAsync.when(
                        data: (accounts) => _AccountPicker(
                          accounts: accounts,
                          selectedId: _selectedAccountId,
                          onSelect: (id) =>
                              setState(() => _selectedAccountId = id),
                        ),
                        loading: () => const SizedBox(
                          height: 40,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                        error: (_, _) => const Text(
                          'Failed to load accounts',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.xxl),

                      // Date
                      const _Label('Date'),
                      const SizedBox(height: AppSpacing.md),
                      GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.lg,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Text(
                                _formatDate(_selectedDate),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const Spacer(),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: AppColors.textTertiary,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: AppSpacing.xxl),

                      // Note
                      const _Label('Note (optional)'),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _noteController,
                        maxLines: 2,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'What was this for?',
                          hintStyle: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            borderSide: const BorderSide(
                              color: AppColors.border,
                            ),
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
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                  ),
                ),
              ),

              // Submit
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  AppSpacing.xl + MediaQuery.of(context).padding.bottom,
                ),
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
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
                          'Add Expense',
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

// ── Small shared widgets ───────────────────────────────────────────────────────

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

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  final List<CategoryModel> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: categories.map((cat) {
        final isSelected = cat.id == selectedId;
        final color = hexToColor(cat.color);
        return GestureDetector(
          onTap: () => onSelect(isSelected ? null : cat.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: isSelected ? color : color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: isSelected ? color : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  iconForName(cat.icon),
                  size: 14,
                  color: isSelected ? Colors.white : color,
                ),
                const SizedBox(width: 5),
                Text(
                  cat.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : color,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _AccountPicker extends StatelessWidget {
  const _AccountPicker({
    required this.accounts,
    required this.selectedId,
    required this.onSelect,
  });

  final List<AccountModel> accounts;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: accounts.map((acc) {
        final isSelected = acc.id == selectedId;
        final color = hexToColor(acc.color);
        return GestureDetector(
          onTap: () => onSelect(isSelected ? null : acc.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: isSelected ? color : color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: isSelected ? color : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  iconForName(acc.icon),
                  size: 14,
                  color: isSelected ? Colors.white : color,
                ),
                const SizedBox(width: 5),
                Text(
                  acc.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : color,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
