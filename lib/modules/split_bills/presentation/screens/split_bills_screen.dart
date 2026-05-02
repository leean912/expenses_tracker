import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../home/presentation/widgets/custom_bottom_nav.dart';
import '../../data/models/my_share_item.dart';
import '../../data/models/split_bill_model.dart';
import '../../providers/split_bills_provider.dart';

class SplitBillsScreen extends ConsumerStatefulWidget {
  const SplitBillsScreen({super.key});

  @override
  ConsumerState<SplitBillsScreen> createState() => _SplitBillsScreenState();
}

class _SplitBillsScreenState extends ConsumerState<SplitBillsScreen>
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: const Text(
                'Split Bills',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: TabBar(
                  controller: _tabs,
                  indicator: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: AppColors.accentText,
                  unselectedLabelColor: AppColors.textSecondary,
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: const [Tab(text: 'I Paid'), Tab(text: 'I Owe')],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
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
                data: (data) => TabBarView(
                  controller: _tabs,
                  children: [
                    _IPaidTab(bills: data.myBills),
                    _IOweTab(shares: data.myShares),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: CustomBottomNav(
          currentIndex: 1,
          onTabTap: (index) {
            if (index != 1) context.pop();
          },
          onAddTap: () {},
        ),
      ),
    );
  }
}

// ─── Tab: I Paid ─────────────────────────────────────────────────────────────

class _IPaidTab extends StatelessWidget {
  const _IPaidTab({required this.bills});
  final List<SplitBillModel> bills;

  @override
  Widget build(BuildContext context) {
    if (bills.isEmpty) {
      return const Center(
        child: Text(
          'No bills yet',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      itemCount: bills.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) => _BillCard(bill: bills[i]),
    );
  }
}

// ─── Tab: I Owe ──────────────────────────────────────────────────────────────

class _IOweTab extends StatelessWidget {
  const _IOweTab({required this.shares});
  final List<MyShareItem> shares;

  @override
  Widget build(BuildContext context) {
    if (shares.isEmpty) {
      return const Center(
        child: Text(
          'Nothing to settle',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      itemCount: shares.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) => _ShareCard(item: shares[i]),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

final _dateFmt = DateFormat('d MMM');

String _fmtAmount(int cents, String currency) =>
    '$currency ${(cents / 100).toStringAsFixed(2)}';

// ─── I Paid card ─────────────────────────────────────────────────────────────

class _BillCard extends StatelessWidget {
  const _BillCard({required this.bill});
  final SplitBillModel bill;

  @override
  Widget build(BuildContext context) {
    final settled = bill.settledCount;
    final total = bill.shares.length;
    final allSettled = total > 0 && settled == total;

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
                Text(
                  _fmtAmount(bill.totalAmountCents, bill.currency),
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
                _ProgressBadge(settled: settled, total: total, allSettled: allSettled),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBadge extends StatelessWidget {
  const _ProgressBadge({
    required this.settled,
    required this.total,
    required this.allSettled,
  });
  final int settled;
  final int total;
  final bool allSettled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: allSettled ? AppColors.positiveLight : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        allSettled ? 'All settled' : '$settled/$total settled',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: allSettled ? AppColors.positiveDark : AppColors.textSecondary,
        ),
      ),
    );
  }
}

// ─── I Owe card ───────────────────────────────────────────────────────────────

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.item});
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
            color: isPending ? AppColors.borderDashed : AppColors.border,
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
                _StatusBadge(isPending: isPending),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  '${item.payer?.displayLabel ?? 'Someone'} paid',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
                const Spacer(),
                Text(
                  'Your share: ${_fmtAmount(item.share.shareCents, item.currency)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
        color: isPending ? AppColors.surfaceMuted : AppColors.positiveLight,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        isPending ? 'Pending' : 'Settled',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: isPending ? AppColors.textSecondary : AppColors.positiveDark,
        ),
      ),
    );
  }
}
