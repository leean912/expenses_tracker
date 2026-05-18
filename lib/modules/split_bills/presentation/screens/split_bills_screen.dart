import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/my_share_item.dart';
import '../../data/models/split_bill_model.dart';
import '../../providers/split_bills_provider.dart' show myBillsProvider, mySharesProvider;

// enum _ViewMode { byBills, byFriends }

enum _FilterMode { pending, settled }

class SplitBillsScreen extends ConsumerStatefulWidget {
  const SplitBillsScreen({super.key});

  @override
  ConsumerState<SplitBillsScreen> createState() => _SplitBillsScreenState();
}

class _SplitBillsScreenState extends ConsumerState<SplitBillsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  // final _ViewMode _viewMode = _ViewMode.byBills;
  _FilterMode _filterMode = _FilterMode.pending;

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
    final billsAsync = ref.watch(myBillsProvider);
    final sharesAsync = ref.watch(mySharesProvider);

    final isLoading =
        (billsAsync.isLoading && billsAsync.valueOrNull == null) ||
        (sharesAsync.isLoading && sharesAsync.valueOrNull == null);
    final hasError =
        (billsAsync.hasError && billsAsync.valueOrNull == null) ||
        (sharesAsync.hasError && sharesAsync.valueOrNull == null);

    final isPending = _filterMode == _FilterMode.pending;
    final allBills = billsAsync.valueOrNull?.items ?? [];
    final allShares = sharesAsync.valueOrNull?.items ?? [];

    final filteredBills = allBills.where((b) {
      final allSettled = b.shares.isNotEmpty && b.settledCount == b.shares.length;
      return isPending ? !allSettled : allSettled;
    }).toList();
    final filteredShares = allShares.where((s) {
      return isPending ? s.share.isPending : !s.share.isPending;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text(
          'Split Bills',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: _FilterModeButton(
              current: _filterMode,
              onSelected: (f) => setState(() => _filterMode = f),
            ),
          ),
        ],
        bottom: TabBar(
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
            Tab(text: 'I Paid'),
            Tab(text: 'I Owe'),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : hasError
          ? _ErrorView(
              onRetry: () {
                ref.invalidate(myBillsProvider);
                ref.invalidate(mySharesProvider);
              },
            )
          : TabBarView(
              controller: _tabs,
              children: [
                _IPaidTab(
                  bills: filteredBills,
                  hasMore: billsAsync.valueOrNull?.hasMore ?? false,
                ),
                _IOweTab(
                  shares: filteredShares,
                  hasMore: sharesAsync.valueOrNull?.hasMore ?? false,
                ),
              ],
            ),
    );
  }
}

// ── Filter mode button (pending / settled) ─────────────────────────────────────

class _FilterModeButton extends StatelessWidget {
  const _FilterModeButton({required this.current, required this.onSelected});
  final _FilterMode current;
  final ValueChanged<_FilterMode> onSelected;

  String get _label => switch (current) {
    _FilterMode.pending => 'Pending',
    _FilterMode.settled => 'Settled',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_FilterMode>(
      onSelected: onSelected,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.border),
      ),
      offset: const Offset(0, 40),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
      itemBuilder: (_) => [
        _menuItem(_FilterMode.pending, 'Pending', current),
        _menuItem(_FilterMode.settled, 'Settled', current),
      ],
    );
  }

  PopupMenuItem<_FilterMode> _menuItem(
    _FilterMode value,
    String label,
    _FilterMode current,
  ) {
    final isSelected = value == current;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (isSelected)
            const Icon(
              Icons.check_rounded,
              size: 16,
              color: AppColors.textPrimary,
            ),
        ],
      ),
    );
  }
}

// ── View mode button ───────────────────────────────────────────────────────────

// class _ViewModeButton extends StatelessWidget {
//   const _ViewModeButton({required this.current, required this.onSelected});
//   final _ViewMode current;
//   final ValueChanged<_ViewMode> onSelected;

//   String get _label => switch (current) {
//     _ViewMode.byBills => 'By Bills',
//     _ViewMode.byFriends => 'By Friends',
//   };

//   @override
//   Widget build(BuildContext context) {
//     return PopupMenuButton<_ViewMode>(
//       onSelected: onSelected,
//       color: AppColors.surface,
//       shape: RoundedRectangleBorder(
//         borderRadius: BorderRadius.circular(AppRadius.md),
//         side: const BorderSide(color: AppColors.border),
//       ),
//       offset: const Offset(0, 40),
//       child: Container(
//         padding: const EdgeInsets.symmetric(
//           horizontal: AppSpacing.md,
//           vertical: 6,
//         ),
//         decoration: BoxDecoration(
//           color: AppColors.surface,
//           borderRadius: BorderRadius.circular(AppRadius.md),
//           border: Border.all(color: AppColors.border),
//         ),
//         child: Row(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Text(
//               _label,
//               style: const TextStyle(
//                 fontSize: 13,
//                 fontWeight: FontWeight.w500,
//                 color: AppColors.textSecondary,
//               ),
//             ),
//             const SizedBox(width: 2),
//             const Icon(
//               Icons.keyboard_arrow_down_rounded,
//               size: 16,
//               color: AppColors.textTertiary,
//             ),
//           ],
//         ),
//       ),
//       itemBuilder: (_) => [
//         _menuItem(_ViewMode.byBills, 'By Bills', current),
//         _menuItem(_ViewMode.byFriends, 'By Friends', current),
//       ],
//     );
//   }

//   PopupMenuItem<_ViewMode> _menuItem(
//     _ViewMode value,
//     String label,
//     _ViewMode current,
//   ) {
//     final isSelected = value == current;
//     return PopupMenuItem(
//       value: value,
//       child: Row(
//         children: [
//           Expanded(
//             child: Text(
//               label,
//               style: TextStyle(
//                 fontSize: 14,
//                 fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
//                 color: AppColors.textPrimary,
//               ),
//             ),
//           ),
//           if (isSelected)
//             const Icon(
//               Icons.check_rounded,
//               size: 16,
//               color: AppColors.textPrimary,
//             ),
//         ],
//       ),
//     );
//   }
// }

// ── Error view ─────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Failed to load',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

// ── Tab: I Paid ────────────────────────────────────────────────────────────────

class _IPaidTab extends ConsumerWidget {
  const _IPaidTab({required this.bills, required this.hasMore});
  final List<SplitBillModel> bills;
  final bool hasMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bills.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(myBillsProvider),
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(
              child: Text(
                'No bills yet',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollUpdateNotification &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
          ref.read(myBillsProvider.notifier).fetchMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myBillsProvider),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          itemCount: bills.length + (hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, i) {
            if (i == bills.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return _BillCard(bill: bills[i]);
          },
        ),
      ),
    );
  }
}

// ── Tab: I Owe ─────────────────────────────────────────────────────────────────

class _IOweTab extends ConsumerWidget {
  const _IOweTab({required this.shares, required this.hasMore});
  final List<MyShareItem> shares;
  final bool hasMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (shares.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(mySharesProvider),
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
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollUpdateNotification &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 300) {
          ref.read(mySharesProvider.notifier).fetchMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(mySharesProvider),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          itemCount: shares.length + (hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, i) {
            if (i == shares.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return _ShareCard(item: shares[i]);
          },
        ),
      ),
    );
  }
}

// ── Tab: By Friends ────────────────────────────────────────────────────────────

// class _ByFriendsTab extends ConsumerWidget {
//   const _ByFriendsTab({required this.summaries});
//   final List<FriendSplitSummary> summaries;

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     if (summaries.isEmpty) {
//       return RefreshIndicator(
//         onRefresh: () async => ref.invalidate(splitBillsProvider),
//         child: ListView(
//           children: const [
//             SizedBox(height: 120),
//             Center(
//               child: Text(
//                 'No friends to show',
//                 style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
//               ),
//             ),
//           ],
//         ),
//       );
//     }
//     return RefreshIndicator(
//       onRefresh: () => ref.refresh(splitBillsProvider.future),
//       child: ListView.separated(
//         padding: const EdgeInsets.fromLTRB(
//           AppSpacing.xl,
//           AppSpacing.md,
//           AppSpacing.xl,
//           AppSpacing.xl,
//         ),
//         itemCount: summaries.length,
//         separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
//         itemBuilder: (context, i) => _FriendCard(summary: summaries[i]),
//       ),
//     );
//   }
// }

// ── Shared helpers ─────────────────────────────────────────────────────────────

final _dateFmt = DateFormat('d MMM');

String _fmtAmount(int cents, String currency) =>
    '$currency ${(cents / 100).toStringAsFixed(2)}';

// ── I Paid card ────────────────────────────────────────────────────────────────

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
                _ProgressBadge(
                  settled: settled,
                  total: total,
                  allSettled: allSettled,
                ),
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

// ── I Owe card ─────────────────────────────────────────────────────────────────

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.item});
  final MyShareItem item;

  @override
  Widget build(BuildContext context) {
    final isPending = item.share.isPending;
    final isOverdue = isPending &&
        DateTime.now().difference(item.expenseDate).inDays > 5;

    return GestureDetector(
      onTap: () => context.push('$splitBillsRoute/${item.billId}'),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: isOverdue
                ? AppColors.overdueDark
                : isPending
                    ? AppColors.pendingStatus
                    : AppColors.border,
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
                _StatusBadge(isPending: isPending, isOverdue: isOverdue),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  '${item.payer?.displayName} paid',
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
            const SizedBox(height: AppSpacing.xs),
            Text(
              _dateFmt.format(item.expenseDate),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isPending, this.isOverdue = false});
  final bool isPending;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color textColor;
    final String label;

    if (!isPending) {
      bgColor = AppColors.positiveLight;
      textColor = AppColors.positiveDark;
      label = 'Settled';
    } else if (isOverdue) {
      bgColor = AppColors.overdueLight;
      textColor = AppColors.overdueDark;
      label = 'Overdue';
    } else {
      bgColor = AppColors.pendingStatus;
      textColor = AppColors.accentText;
      label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }
}

// ── Friend card ────────────────────────────────────────────────────────────────

// class _FriendCard extends StatelessWidget {
//   const _FriendCard({required this.summary});
//   final FriendSplitSummary summary;

//   @override
//   Widget build(BuildContext context) {
//     final hasPending = summary.totalPendingBills > 0;

//     return GestureDetector(
//       onTap: () => context.push('$splitBillsFriendRoute/${summary.friend.id}'),
//       child: Container(
//         padding: const EdgeInsets.all(AppSpacing.xl),
//         decoration: BoxDecoration(
//           color: AppColors.surface,
//           borderRadius: BorderRadius.circular(AppRadius.xl),
//           border: Border.all(color: AppColors.border),
//         ),
//         child: Row(
//           children: [
//             // Avatar
//             Container(
//               width: 40,
//               height: 40,
//               decoration: BoxDecoration(
//                 color: AppColors.surfaceMuted,
//                 shape: BoxShape.circle,
//               ),
//               child: Center(
//                 child: Text(
//                   ((summary.friend.displayName?.isNotEmpty == true)
//                           ? summary.friend.displayName![0]
//                           : '?')
//                       .toUpperCase(),
//                   style: const TextStyle(
//                     fontSize: 16,
//                     fontWeight: FontWeight.w600,
//                     color: AppColors.textSecondary,
//                   ),
//                 ),
//               ),
//             ),
//             const SizedBox(width: AppSpacing.lg),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     summary.friend.displayName ??
//                         summary.friend.username ??
//                         'Unknown',
//                     style: const TextStyle(
//                       fontSize: 15,
//                       fontWeight: FontWeight.w500,
//                       color: AppColors.textPrimary,
//                     ),
//                   ),
//                   const SizedBox(height: 2),
//                   Text(
//                     '${summary.totalBills} bill${summary.totalBills == 1 ? '' : 's'}',
//                     style: const TextStyle(
//                       fontSize: 12,
//                       color: AppColors.textTertiary,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             if (hasPending)
//               Container(
//                 padding: const EdgeInsets.symmetric(
//                   horizontal: AppSpacing.md,
//                   vertical: AppSpacing.xs,
//                 ),
//                 decoration: BoxDecoration(
//                   color: AppColors.surfaceMuted,
//                   borderRadius: BorderRadius.circular(AppRadius.pill),
//                 ),
//                 child: Text(
//                   '${summary.totalPendingBills} pending',
//                   style: const TextStyle(
//                     fontSize: 11,
//                     fontWeight: FontWeight.w500,
//                     color: AppColors.textSecondary,
//                   ),
//                 ),
//               )
//             else
//               Container(
//                 padding: const EdgeInsets.symmetric(
//                   horizontal: AppSpacing.md,
//                   vertical: AppSpacing.xs,
//                 ),
//                 decoration: BoxDecoration(
//                   color: AppColors.positiveLight,
//                   borderRadius: BorderRadius.circular(AppRadius.pill),
//                 ),
//                 child: const Text(
//                   'All settled',
//                   style: TextStyle(
//                     fontSize: 11,
//                     fontWeight: FontWeight.w500,
//                     color: AppColors.positiveDark,
//                   ),
//                 ),
//               ),
//             const SizedBox(width: AppSpacing.sm),
//             const Icon(
//               Icons.chevron_right_rounded,
//               size: 18,
//               color: AppColors.textTertiary,
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
