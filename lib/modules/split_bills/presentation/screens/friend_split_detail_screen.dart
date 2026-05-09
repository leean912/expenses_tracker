import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../service_locator.dart';
import '../../data/models/friend_split_summary.dart';
import '../../data/models/my_share_item.dart';
import '../../data/models/split_bill_model.dart';
import '../../providers/split_bills_provider.dart';

class FriendSplitDetailScreen extends ConsumerStatefulWidget {
  const FriendSplitDetailScreen({super.key, required this.friendId});
  final String friendId;

  @override
  ConsumerState<FriendSplitDetailScreen> createState() =>
      _FriendSplitDetailScreenState();
}

class _FriendSplitDetailScreenState
    extends ConsumerState<FriendSplitDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(splitBillsProvider);
    final currentUserId = supabase.auth.currentUser!.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with back button + friend name
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Expanded(
                    child:
                        async.whenOrNull(
                          data: (data) {
                            final summaries = FriendSplitSummary.fromData(
                              data,
                              currentUserId,
                            );
                            final summary = summaries
                                .where((s) => s.friend.id == widget.friendId)
                                .firstOrNull;
                            return Text(
                              summary?.friend.displayName ??
                                  summary?.friend.username ??
                                  'Friend',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            );
                          },
                        ) ??
                        const Text(
                          'Friend',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              labelColor: AppColors.textPrimary,
              unselectedLabelColor: AppColors.textTertiary,
              indicatorColor: AppColors.textPrimary,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: AppColors.border,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              tabs: const [
                Tab(text: 'They Owe You'),
                Tab(text: 'You Owe Them'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Failed to load',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextButton(
                        onPressed: () => ref.invalidate(splitBillsProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (data) {
                  final summaries = FriendSplitSummary.fromData(
                    data,
                    currentUserId,
                  );
                  final summary = summaries
                      .where((s) => s.friend.id == widget.friendId)
                      .firstOrNull;

                  if (summary == null) {
                    return const Center(
                      child: Text(
                        'No bills found.',
                        style: TextStyle(color: AppColors.textTertiary),
                      ),
                    );
                  }

                  return TabBarView(
                    controller: _tabs,
                    children: [
                      _TheyOweYouTab(
                        bills: summary.billsIPaid,
                        friendId: widget.friendId,
                        onRefresh: () => ref.refresh(splitBillsProvider.future),
                      ),
                      _YouOweThemTab(
                        shares: summary.billsFriendPaid,
                        onRefresh: () => ref.refresh(splitBillsProvider.future),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tab: They Owe You ──────────────────────────────────────────────────────────

class _TheyOweYouTab extends StatelessWidget {
  const _TheyOweYouTab({
    required this.bills,
    required this.friendId,
    required this.onRefresh,
  });
  final List<SplitBillModel> bills;
  final String friendId;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (bills.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(
              child: Text(
                'No bills here',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        itemCount: bills.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) =>
            _IPaidCard(bill: bills[i], friendId: friendId),
      ),
    );
  }
}

// ── Tab: You Owe Them ──────────────────────────────────────────────────────────

class _YouOweThemTab extends StatelessWidget {
  const _YouOweThemTab({required this.shares, required this.onRefresh});
  final List<MyShareItem> shares;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (shares.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(
              child: Text(
                'Nothing to settle',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        itemCount: shares.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) => _IOweCard(item: shares[i]),
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

final _dateFmt = DateFormat('d MMM');

String _fmtAmount(int cents, String currency) =>
    '$currency ${(cents / 100).toStringAsFixed(2)}';

// ── I Paid card ────────────────────────────────────────────────────────────────

class _IPaidCard extends StatelessWidget {
  const _IPaidCard({required this.bill, required this.friendId});
  final SplitBillModel bill;
  final String friendId;

  @override
  Widget build(BuildContext context) {
    final friendShare = bill.shares
        .where((s) => s.userId == friendId)
        .firstOrNull;
    final isPending = friendShare?.isPending ?? false;

    return GestureDetector(
      onTap: () => context.push('$splitBillsRoute/${bill.id}'),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    bill.note.isEmpty ? 'Split bill' : bill.note,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                if (friendShare != null)
                  Text(
                    _fmtAmount(friendShare.shareCents, bill.currency),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  _dateFmt.format(bill.expenseDate),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
                const Spacer(),
                _StatusBadge(isPending: isPending),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── I Owe card ─────────────────────────────────────────────────────────────────

class _IOweCard extends StatelessWidget {
  const _IOweCard({required this.item});
  final MyShareItem item;

  @override
  Widget build(BuildContext context) {
    final isPending = item.share.isPending;

    return GestureDetector(
      onTap: () => context.push('$splitBillsRoute/${item.billId}'),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: isPending ? AppColors.pendingStatus : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.billNote.isEmpty ? 'Split bill' : item.billNote,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  _fmtAmount(item.share.shareCents, item.currency),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  _dateFmt.format(item.expenseDate),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
                const Spacer(),
                _StatusBadge(isPending: isPending),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status badge ───────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isPending});
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isPending ? AppColors.pendingStatus : AppColors.positiveLight,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        isPending ? 'Pending' : 'Settled',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: isPending ? AppColors.accentText : AppColors.positiveDark,
        ),
      ),
    );
  }
}
