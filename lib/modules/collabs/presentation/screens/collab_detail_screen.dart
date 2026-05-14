import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currencies.dart';
import '../../../../service_locator.dart';
import '../../../expenses/presentation/widgets/edit_expense_sheet.dart';
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
                'Collab not found / deleted',
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
      builder: (_) => CollabExpenseSheet(collab: collab),
    );
  }

  void _showPersonalBudgetDialog(CollabMemberModel member) {
    final controller = TextEditingController(
      text: member.personalBudgetCents != null
          ? (member.personalBudgetCents! / 100).toStringAsFixed(2)
          : '',
    );
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'My Personal Budget',
          style: TextStyle(
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

  void _showMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CollabMenuSheet(
        collab: collab,
        isOwner: _isOwner,
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
        skipLoadingOnRefresh: true,
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
          final currentMember = collab.members
              .where((m) => m.userId == _currentUserId && m.isActive)
              .firstOrNull;
          final mySpentCents = state.expenses.fold<int>(0, (sum, e) {
            if (e.userId != _currentUserId) return sum;
            return sum + (e.isIncome ? -e.homeAmountCents : e.homeAmountCents);
          });
          return RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () => Future.wait([
              ref.refresh(collabsProvider.future),
              ref.refresh(collabExpensesProvider(collab.id).future),
            ]),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // ── Header ───────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _CollabHeader(
                    collab: collab,
                    members: activeMembers,
                    spentCents: state.totalHomeAmountCents,
                    onMembersTap: () =>
                        context.push('$collabDetailRoute/${collab.id}/members'),
                    currentMember: currentMember,
                    mySpentCents: mySpentCents,
                    onBudgetTap: currentMember != null && collab.isActive
                        ? () => _showPersonalBudgetDialog(currentMember)
                        : null,
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
                            onTap: isOwn
                                ? () => showModalBottomSheet<void>(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => EditExpenseSheet(
                                        expenseId: expense.id,
                                        onSaved: () => ref
                                            .read(collabExpensesProvider(collab.id).notifier)
                                            .refresh(),
                                      ),
                                    )
                                : null,
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
            ),
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
                'Collab Expense',
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
    this.currentMember,
    required this.mySpentCents,
    this.onBudgetTap,
  });

  final CollabModel collab;
  final List<CollabMemberModel> members;
  final int spentCents;
  final VoidCallback onMembersTap;
  final CollabMemberModel? currentMember;
  final int mySpentCents;
  final VoidCallback? onBudgetTap;

  @override
  Widget build(BuildContext context) {
    final hasBudget =
        currentMember?.personalBudgetCents != null &&
        currentMember!.personalBudgetCents! > 0;
    final budgetCents = currentMember?.personalBudgetCents ?? 0;
    final overBudget = hasBudget && mySpentCents > budgetCents;
    final progress = hasBudget
        ? (mySpentCents / budgetCents).clamp(0.0, 1.0)
        : 0.0;

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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: collab.isClosed
                        ? const Color(0xFFFFEBEB)
                        : const Color(0xFFE6F9F0),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    collab.isClosed ? 'Closed' : 'Ongoing',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: collab.isClosed
                          ? const Color(0xFF993C1D)
                          : const Color(0xFF1A7A4A),
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

            // Total spent
            const SizedBox(height: AppSpacing.md),
            Text(
              '${collab.homeCurrency} ${_fmt(spentCents)} total spent',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),

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

            // My personal budget section
            if (currentMember != null) ...[
              const SizedBox(height: AppSpacing.xl),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: AppSpacing.xl),
              GestureDetector(
                onTap: onBudgetTap,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'My spending',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        if (hasBudget)
                          Text(
                            '${collab.homeCurrency} ${_fmt(mySpentCents)} / ${_fmt(budgetCents)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: overBudget
                                  ? const Color(0xFF993C1D)
                                  : AppColors.textSecondary,
                            ),
                          )
                        else
                          Text(
                            '${collab.homeCurrency} ${_fmt(mySpentCents)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    if (hasBudget) ...[
                      const SizedBox(height: AppSpacing.sm),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 5,
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
                            ? '${collab.homeCurrency} ${_fmt(mySpentCents - budgetCents)} over my budget'
                            : '${collab.homeCurrency} ${_fmt(budgetCents - mySpentCents)} left',
                        style: TextStyle(
                          fontSize: 11,
                          color: overBudget
                              ? const Color(0xFF993C1D)
                              : AppColors.textTertiary,
                        ),
                      ),
                    ] else if (onBudgetTap != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.add_rounded,
                            size: 12,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(width: 3),
                          const Text(
                            'Set my personal budget',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
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
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Expanded(child: _MemberStrip(members: members)),
                    const Text(
                      'View all',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 25,
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
    this.onTap,
  });

  final CollabExpense expense;
  final CollabModel collab;
  final bool isOwn;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasCategory = expense.categoryName != null;
    final catColor = hasCategory
        ? hexToColor(expense.categoryColor ?? '#888780')
        : AppColors.textTertiary;

    final amountStr =
        '${expense.currency} ${_fmtAmount(expense.amountCents, expense.currency)}';
    final primaryAmount = '${expense.isIncome ? "+" : "−"}$amountStr';
    final isForeignExpense = expense.currency != collab.homeCurrency;
    final homeAmount = isForeignExpense
        ? '${collab.homeCurrency} ${(expense.homeAmountCents / 100).toStringAsFixed(2)}'
        : null;
    final amountColor = expense.isIncome
        ? AppColors.positiveDark
        : AppColors.expenseLight;

    final hasBadges =
        expense.isSplitBill || expense.hasReceipt || isForeignExpense;

    return GestureDetector(
      onTap: onTap,
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
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                color: isOwn ? AppColors.accent : AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Row(
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

              // Owner + note + badges
              Expanded(
                child: Column(
                  spacing: 2,
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
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    if (hasBadges) ...[
                      Row(
                        children: [
                          if (expense.isSplitBill) ...[
                            _TileBadge(
                              icon: Icons.call_split_rounded,
                              label: expense.isIncome
                                  ? 'Settlement'
                                  : 'Split bill',
                              onTap: expense.splitBillId != null
                                  ? () => context.push(
                                      '/split-bills/${expense.splitBillId}',
                                    )
                                  : null,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                          ],
                          if (expense.currency != collab.homeCurrency) ...[
                            _TileBadge(
                              icon: Icons.language_rounded,
                              label: expense.currency,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                          ],
                          if (expense.hasReceipt)
                            const _TileBadge(
                              icon: Icons.receipt_long_rounded,
                              label: 'Receipt',
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                    ],
                    Row(
                      children: [
                        if (hasCategory) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(
                              expense.categoryName!,
                              style: TextStyle(fontSize: 10, color: catColor),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        if (expense.accountName != null)
                          Flexible(
                            child: Text(
                              expense.accountName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),

              // Amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    primaryAmount,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: amountColor,
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
        ],
      ),
    ),
    );
  }

  String _fmtAmount(int cents, String currency) {
    final noDecimal = {'JPY', 'KRW', 'VND', 'IDR'}.contains(currency);
    if (noDecimal) return (cents ~/ 100).toString();
    return (cents / 100).toStringAsFixed(2);
  }
}

class _TileBadge extends StatelessWidget {
  const _TileBadge({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tappable = onTap != null;
    final content = Container(
      padding: tappable
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
          : EdgeInsets.zero,
      decoration: tappable
          ? BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 11,
            color: tappable ? AppColors.accent : AppColors.textTertiary,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: tappable ? AppColors.accent : AppColors.textTertiary,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (tappable) ...[
            const SizedBox(width: 2),
            const Icon(
              Icons.chevron_right_rounded,
              size: 11,
              color: AppColors.accent,
            ),
          ],
        ],
      ),
    );
    if (!tappable) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}

// ── Collab menu sheet ─────────────────────────────────────────────────────────

class _CollabMenuSheet extends StatelessWidget {
  const _CollabMenuSheet({
    required this.collab,
    required this.isOwner,
    required this.onClose,
    required this.onLeave,
    required this.onEdit,
  });

  final CollabModel collab;
  final bool isOwner;
  final VoidCallback onClose;
  final VoidCallback onLeave;
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
                        onPressed: () => context.pop(false),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.pop(true),
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
                if (confirmed == true) onLeave();
              },
            ),
          ],
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
  late final TextEditingController _exchangeRateController;

  late String _currency;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = false;
  String? _error;

  CollabModel get collab => widget.collab;

  bool get _isForeign => _currency != collab.homeCurrency;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: collab.name);
    _descController = TextEditingController(text: collab.description ?? '');
    _currency = collab.currency;
    _startDate = collab.startDate;
    _endDate = collab.endDate;
    _exchangeRateController = TextEditingController(
      text: collab.exchangeRate != null
          ? collab.exchangeRate!.toStringAsFixed(
              collab.exchangeRate! >= 10 ? 0 : 2,
            )
          : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _exchangeRateController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? d) {
    if (d == null) return 'Not set';
    return DateFormat('d MMM yyyy').format(d);
  }

  void _pickCurrency() {
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CurrencyPickerSheet(selected: _currency),
    ).then((picked) {
      if (picked != null && picked != _currency) {
        setState(() {
          _currency = picked;
          if (!_isForeign) _exchangeRateController.clear();
        });
      }
    });
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
    if (_isForeign) {
      final rateText = _exchangeRateController.text.trim();
      if (rateText.isEmpty || double.tryParse(rateText) == null) {
        setState(() => _error = 'Please enter a valid exchange rate.');
        return;
      }
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    double? exchangeRate;
    if (_isForeign) {
      exchangeRate = double.tryParse(_exchangeRateController.text.trim());
    }

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
          currency: _currency,
          exchangeRate: exchangeRate,
        );
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      setState(() => _error = error);
    } else {
      context.pop();
    }
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
    filled: true,
    fillColor: AppColors.background,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      borderSide: BorderSide.none,
    ),
  );

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

            // Name
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: _fieldDecoration('Name'),
            ),
            const SizedBox(height: AppSpacing.md),

            // Description
            TextField(
              controller: _descController,
              maxLines: 3,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: _fieldDecoration('Description (optional)'),
            ),
            const SizedBox(height: AppSpacing.md),

            // Dates
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
            const SizedBox(height: AppSpacing.md),

            // Currency
            GestureDetector(
              onTap: _pickCurrency,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Currency',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$_currency — ${AppCurrency.nameFor(_currency)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Changing currency won\'t affect existing transactions.',
              style: TextStyle(fontSize: 11, color: AppColors.expenseLight),
            ),

            // Exchange rate (foreign currency only)
            if (_isForeign) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _exchangeRateController,
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
                decoration: _fieldDecoration(
                  'Exchange Rate (1 ${collab.homeCurrency} = ? $_currency)',
                ),
              ),
            ],

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

// ── Currency picker sheet ─────────────────────────────────────────────────────

class _CurrencyPickerSheet extends StatelessWidget {
  const _CurrencyPickerSheet({required this.selected});

  final String selected;

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
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.xxl,
              AppSpacing.xxl,
              AppSpacing.lg,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Select Currency',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => context.pop(),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: AppCurrency.all.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, index) {
                final currency = AppCurrency.all[index];
                final isSelected = currency.code == selected;
                return ListTile(
                  onTap: () => context.pop(currency.code),
                  title: Text(
                    '${currency.code} — ${currency.name}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: AppColors.accent,
                        )
                      : null,
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
