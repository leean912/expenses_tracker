import 'package:cached_network_image/cached_network_image.dart';
import 'package:jomspendz/modules/home/providers/home/home_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/receipt_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/receipt_viewer.dart';
import '../../../../service_locator.dart';
import '../../../expenses/data/models/account_model.dart';
import '../../../expenses/data/models/category_model.dart';
import '../../../expenses/providers/accounts_provider.dart';
import '../../../expenses/providers/categories_provider.dart';
import '../../../subscription/providers/subscription_provider.dart';
import '../../data/models/split_bill_model.dart';
import '../../data/models/split_share_model.dart';
import '../../providers/split_bill_detail_provider.dart';
import '../../providers/split_bills_provider.dart';

class SplitBillDetailScreen extends ConsumerWidget {
  const SplitBillDetailScreen({super.key, required this.billId});
  final String billId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(splitBillDetailProvider(billId));
    final currentUserId = supabase.auth.currentUser?.id ?? '';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text(
          'Split Bill',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          if (async.valueOrNull case final bill?
              when bill.createdBy == currentUserId)
            _DeleteButton(billId: billId, bill: bill),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Failed to load',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextButton(
                onPressed: () =>
                    ref.invalidate(splitBillDetailProvider(billId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (bill) => _BillDetail(bill: bill, billId: billId),
      ),
    );
  }
}

// ─── Delete button ────────────────────────────────────────────────────────────

class _DeleteButton extends ConsumerStatefulWidget {
  const _DeleteButton({required this.billId, required this.bill});
  final String billId;
  final SplitBillModel bill;

  @override
  ConsumerState<_DeleteButton> createState() => _DeleteButtonState();
}

class _DeleteButtonState extends ConsumerState<_DeleteButton> {
  bool _loading = false;

  Future<void> _onTap() async {
    final hasSettledOthers = widget.bill.shares.any(
      (s) => s.userId != widget.bill.createdBy && s.isSettled,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete split bill?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your personal expense record will not be removed — it stays in your history.',
            ),
            if (hasSettledOthers) ...[
              const SizedBox(height: 12),
              const Text(
                'Some participants have already settled their share. Their payments cannot be reversed.',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 12),
            const Text('This action cannot be undone.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => context.pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFE24B4A)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    final error = await ref
        .read(splitBillsProvider.notifier)
        .deleteSplitBill(widget.billId);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.textTertiary,
              ),
              onPressed: _onTap,
            ),
    );
  }
}

// ─── Detail body ─────────────────────────────────────────────────────────────

class _BillDetail extends ConsumerWidget {
  const _BillDetail({required this.bill, required this.billId});
  final SplitBillModel bill;
  final String billId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = supabase.auth.currentUser?.id ?? '';

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(splitBillDetailProvider(billId)),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          _BillHeader(bill: bill),
          if (bill.receiptUrl != null) ...[
            const SizedBox(height: AppSpacing.xl),
            _ReceiptSection(
              receiptUrl: bill.receiptUrl!,
              billId: billId,
              isCreator: bill.createdBy == currentUserId,
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          const Text(
            'PARTICIPANTS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (int i = 0; i < bill.shares.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.border,
                    ),
                  _ShareRow(
                    share: bill.shares[i],
                    currency: bill.currency,
                    isCurrentUser: bill.shares[i].userId == currentUserId,
                    billId: billId,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

// ─── Receipt section ──────────────────────────────────────────────────────────

class _ReceiptSection extends ConsumerStatefulWidget {
  const _ReceiptSection({
    required this.receiptUrl,
    required this.billId,
    required this.isCreator,
  });

  final String receiptUrl;
  final String billId;
  final bool isCreator;

  @override
  ConsumerState<_ReceiptSection> createState() => _ReceiptSectionState();
}

class _ReceiptSectionState extends ConsumerState<_ReceiptSection> {
  bool _expanded = false;
  bool _deleting = false;

  Future<void> _delete() async {
    final isPremium = ref.read(isPremiumProvider);
    if (!isPremium) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete receipt?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFE24B4A)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    await ReceiptUploadService.deleteByUrl(widget.receiptUrl);
    await supabase
        .from('split_bills')
        .update({'receipt_url': null})
        .eq('id', widget.billId);
    if (mounted) {
      ref.invalidate(splitBillDetailProvider(widget.billId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(isPremiumProvider);
    final canDelete = widget.isCreator && isPremium;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row — always visible
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.lg,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  const Text(
                    'Receipt attached',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (_deleting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      _expanded ? 'Hide' : 'View',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.accent,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Expanded image
          if (_expanded) ...[
            const Divider(height: 1, color: AppColors.border),
            GestureDetector(
              onTap: () => showReceiptViewer(context, widget.receiptUrl),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(AppRadius.xl),
                ),
                child: CachedNetworkImage(
                  imageUrl: widget.receiptUrl,
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  placeholder: (context2, p) => const SizedBox(
                    height: 160,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (context2, url, err) => const SizedBox(
                    height: 80,
                    child: Center(
                      child: Icon(
                        Icons.broken_image_rounded,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (canDelete)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  AppSpacing.lg,
                ),
                child: GestureDetector(
                  onTap: _deleting ? null : _delete,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        size: 14,
                        color: Color(0xFFE24B4A),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Delete receipt',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFE24B4A),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─── Bill header card ─────────────────────────────────────────────────────────

final _dateFmtFull = DateFormat('d MMM yyyy');

String _fmtAmount(int cents, String currency) =>
    '$currency ${(cents / 100).toStringAsFixed(2)}';

class _BillHeader extends StatelessWidget {
  const _BillHeader({required this.bill});
  final SplitBillModel bill;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bill.note.isEmpty ? 'Split bill' : bill.note,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Row(
            label: 'Total',
            value: _fmtAmount(bill.totalAmountCents, bill.currency),
          ),
          const SizedBox(height: AppSpacing.md),
          _Row(label: 'Paid by', value: bill.payer?.displayName ?? 'Unknown'),
          const SizedBox(height: AppSpacing.md),
          _Row(label: 'Date', value: _dateFmtFull.format(bill.expenseDate)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ─── Share row ────────────────────────────────────────────────────────────────

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.share,
    required this.currency,
    required this.isCurrentUser,
    required this.billId,
  });

  final SplitShareModel share;
  final String currency;
  final bool isCurrentUser;
  final String billId;

  @override
  Widget build(BuildContext context) {
    final name = isCurrentUser ? 'You' : share.user?.displayName ?? 'Unknown';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      child: Row(
        children: [
          _InitialAvatar(initial: name[0].toUpperCase()),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            _fmtAmount(share.shareCents, currency),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (isCurrentUser && share.isPending)
            _SettleButton(share: share, currency: currency, billId: billId)
          else
            _StatusChip(isSettled: share.isSettled),
        ],
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.initial});
  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isSettled});
  final bool isSettled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isSettled ? AppColors.positiveLight : AppColors.pendingStatus,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        isSettled ? 'Settled' : 'Pending',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: isSettled ? AppColors.positiveDark : AppColors.accentText,
        ),
      ),
    );
  }
}

// ─── Settle button ────────────────────────────────────────────────────────────

class _SettleButton extends StatelessWidget {
  const _SettleButton({
    required this.share,
    required this.currency,
    required this.billId,
  });

  final SplitShareModel share;
  final String currency;
  final String billId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            _SettleSheet(share: share, currency: currency, billId: billId),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: const Text(
          'Settle',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.accentText,
          ),
        ),
      ),
    );
  }
}

// ─── Settle bottom sheet ──────────────────────────────────────────────────────

class _SettleSheet extends ConsumerStatefulWidget {
  const _SettleSheet({
    required this.share,
    required this.currency,
    required this.billId,
  });

  final SplitShareModel share;
  final String currency;
  final String billId;

  @override
  ConsumerState<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends ConsumerState<_SettleSheet> {
  CategoryModel? _category;
  AccountModel? _account;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(pickerCategoriesProvider);
    final accountsAsync = ref.watch(pickerAccountsProvider);
    final canConfirm = _category != null && _account != null && !_loading;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mark as Settled',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _fmtAmount(widget.share.shareCents, widget.currency),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    const _SectionLabel('CATEGORY'),
                    const SizedBox(height: AppSpacing.md),
                    categoriesAsync.when(
                      loading: () => const _PickerSkeleton(),
                      error: (_, _) => const Text(
                        'Failed to load',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      data: (cats) => _CategoryChipPicker(
                        categories: cats,
                        selected: _category,
                        onSelect: (c) => setState(() => _category = c),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _SectionLabel('ACCOUNT'),
                    const SizedBox(height: AppSpacing.md),
                    accountsAsync.when(
                      loading: () => const _PickerSkeleton(),
                      error: (_, _) => const Text(
                        'Failed to load',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      data: (accounts) => _AccountChipPicker(
                        accounts: accounts,
                        selected: _account,
                        onSelect: (a) => setState(() => _account = a),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.accentText,
                    disabledBackgroundColor: AppColors.surfaceMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.lg,
                    ),
                  ),
                  onPressed: canConfirm ? _confirm : null,
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
                          'Confirm',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    setState(() => _loading = true);
    final error = await ref
        .read(splitBillsProvider.notifier)
        .settleShare(
          shareId: widget.share.id,
          categoryId: _category!.id,
          accountId: _account!.id,
        );
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    ref.invalidate(splitBillDetailProvider(widget.billId));
    ref.invalidate(homeDataProvider);
    context.pop();
  }
}

// ─── Picker widget ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textTertiary,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _PickerSkeleton extends StatelessWidget {
  const _PickerSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
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
    );
  }
}

class _CategoryChipPicker extends StatelessWidget {
  const _CategoryChipPicker({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<CategoryModel> categories;
  final CategoryModel? selected;
  final ValueChanged<CategoryModel?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: categories.map((cat) {
        final isSelected = cat.id == selected?.id;
        final color = _hexToColor(cat.color);
        return GestureDetector(
          onTap: () => onSelect(isSelected ? null : cat),
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
                  _iconForName(cat.icon),
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

class _AccountChipPicker extends StatelessWidget {
  const _AccountChipPicker({
    required this.accounts,
    required this.selected,
    required this.onSelect,
  });

  final List<AccountModel> accounts;
  final AccountModel? selected;
  final ValueChanged<AccountModel?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: accounts.map((acc) {
        final isSelected = acc.id == selected?.id;
        final color = _hexToColor(acc.color);
        return GestureDetector(
          onTap: () => onSelect(isSelected ? null : acc),
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
                  _iconForName(acc.icon),
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

Color _hexToColor(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

IconData _iconForName(String name) {
  const map = <String, IconData>{
    'restaurant': Icons.restaurant,
    'directions_car': Icons.directions_car,
    'shopping_bag': Icons.shopping_bag,
    'receipt_long': Icons.receipt_long,
    'movie': Icons.movie,
    'favorite': Icons.favorite,
    'flight': Icons.flight,
    'school': Icons.school,
    'redeem': Icons.redeem,
    'category': Icons.category,
    'luggage': Icons.luggage,
    'payments': Icons.payments,
    'account_balance': Icons.account_balance,
    'account_balance_wallet': Icons.account_balance_wallet,
    'local_cafe': Icons.local_cafe,
    'sports': Icons.sports,
    'home': Icons.home,
    'work': Icons.work,
    'pets': Icons.pets,
    'fitness_center': Icons.fitness_center,
    'local_hospital': Icons.local_hospital,
    'computer': Icons.computer,
    'music_note': Icons.music_note,
  };
  return map[name] ?? Icons.category;
}
