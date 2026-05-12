import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/services/receipt_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/receipt_viewer.dart';
import '../../../../core/utils/amount_input_formatter.dart';
import '../../../../core/widgets/upgrade_sheet.dart';
import '../../../../service_locator.dart';
import '../../../home/providers/home/home_provider.dart';
import '../../../subscription/providers/subscription_provider.dart';
import '../../data/models/account_model.dart';
import '../../data/models/category_model.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/categories_provider.dart';
import '../../utils/expense_ui_helpers.dart';

class EditExpenseSheet extends ConsumerStatefulWidget {
  const EditExpenseSheet({
    super.key,
    required this.expenseId,
    this.onSaved,
  });

  final String expenseId;
  final VoidCallback? onSaved;

  @override
  ConsumerState<EditExpenseSheet> createState() => _EditExpenseSheetState();
}

class _EditExpenseSheetState extends ConsumerState<EditExpenseSheet> {
  final _amountController = TextEditingController();
  final _homeAmountController = TextEditingController();
  final _conversionRateController = TextEditingController();
  final _noteController = TextEditingController();

  String? _selectedCategoryId;
  String? _selectedAccountId;
  DateTime _selectedDate = DateTime.now();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  String _currency = 'MYR';
  String _homeCurrency = 'MYR';

  String? _receiptUrl;
  bool _receiptUploading = false;

  bool _isSplitBill = false;
  bool _isRecurring = false;
  bool _isCollab = false;

  bool get _isForeignCurrency => _currency != _homeCurrency;

  @override
  void initState() {
    super.initState();
    _loadExpense();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _homeAmountController.dispose();
    _conversionRateController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadExpense() async {
    try {
      final row = await supabase
          .from('expenses')
          .select(
            'id, note, amount_cents, home_amount_cents, currency, home_currency, '
            'conversion_rate, expense_date, category_id, account_id, '
            'source_split_bill_id, source_recurring_expense_id, '
            'source_recurring_split_bill_id, collab_id, receipt_url',
          )
          .eq('id', widget.expenseId)
          .single();

      if (!mounted) return;

      final amountCents = row['amount_cents'] as int? ?? 0;
      final homeAmountCents = row['home_amount_cents'] as int? ?? 0;
      final conversionRate = row['conversion_rate'];
      final expenseDate = row['expense_date'] as String;

      setState(() {
        _currency = row['currency'] as String? ?? 'MYR';
        _homeCurrency = row['home_currency'] as String? ?? 'MYR';
        _receiptUrl = row['receipt_url'] as String?;
        _isSplitBill = row['source_split_bill_id'] != null ||
            row['source_recurring_split_bill_id'] != null;
        _isRecurring = row['source_recurring_expense_id'] != null ||
            row['source_recurring_split_bill_id'] != null;
        _isCollab = row['collab_id'] != null;
        _selectedCategoryId = row['category_id'] as String?;
        _selectedAccountId = row['account_id'] as String?;
        _selectedDate = DateTime.parse(expenseDate);
        _noteController.text = row['note'] as String? ?? '';
        _amountController.text = (amountCents / 100).toStringAsFixed(2);
        _homeAmountController.text = (homeAmountCents / 100).toStringAsFixed(2);
        _conversionRateController.text = conversionRate != null
            ? conversionRate.toString()
            : '';
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) return 'Today';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final m = months[date.month - 1];
    return date.year == now.year ? '$m ${date.day}' : '$m ${date.day}, ${date.year}';
  }

  Future<void> _pickReceipt() async {
    if (!ref.read(isPremiumProvider)) {
      UpgradeSheet.show(
        context,
        title: 'Receipt photos',
        description: 'Attach receipt photos to your expenses with Premium.',
      );
      return;
    }
    setState(() => _receiptUploading = true);
    final url = await ReceiptUploadService.pickAndUpload(
      context,
      supabase.auth.currentUser!.id,
    );
    if (mounted) {
      setState(() {
        if (url != null) _receiptUrl = url;
        _receiptUploading = false;
      });
    }
  }

  Future<void> _deleteReceipt() async {
    final url = _receiptUrl;
    if (url == null) return;
    setState(() => _receiptUrl = null);
    await ReceiptUploadService.deleteByUrl(url);
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

  Future<void> _save() async {
    final text = _amountController.text.trim();
    if (text.isEmpty) return;
    final amount = double.tryParse(text);
    if (amount == null || amount <= 0) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final amountCents = (amount * 100).round();
      final payload = <String, dynamic>{
        'note': _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        'category_id': _selectedCategoryId,
        'account_id': _selectedAccountId,
        'amount_cents': amountCents,
        'expense_date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'receipt_url': _receiptUrl,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (_isForeignCurrency) {
        final homeAmountText = _homeAmountController.text.trim();
        final homeAmount = double.tryParse(homeAmountText);
        if (homeAmount != null && homeAmount > 0) {
          payload['home_amount_cents'] = (homeAmount * 100).round();
        }
        final rateText = _conversionRateController.text.trim();
        final rate = double.tryParse(rateText);
        payload['conversion_rate'] = rate;
      } else {
        payload['home_amount_cents'] = amountCents;
      }

      await supabase.from('expenses').update(payload).eq('id', widget.expenseId);

      if (mounted) {
        ref.invalidate(homeDataProvider);
        widget.onSaved?.call();
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to save. Please try again.';
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      if (_receiptUrl != null) {
        ReceiptUploadService.deleteByUrl(_receiptUrl!);
      }
      await supabase.from('expenses').update({
        'deleted_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.expenseId);

      if (mounted) {
        ref.invalidate(homeDataProvider);
        widget.onSaved?.call();
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Failed to delete. Please try again.';
        });
      }
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.lg),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  const Text(
                    'Edit Expense',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _saving ? null : _delete,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.withValues(alpha: 0.08),
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(AppSpacing.sm),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
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

            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.6,
              ),
              child: _loading
                  ? const SizedBox(
                      height: 260,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.lg,
                        AppSpacing.xl,
                        AppSpacing.xxl,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Type badges ─────────────────────────────────
                          if (_isSplitBill || _isRecurring || _isCollab || _isForeignCurrency) ...[
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: [
                                if (_isSplitBill)
                                  _InfoBadge(
                                    icon: Icons.call_split_rounded,
                                    label: 'Split Bill',
                                  ),
                                if (_isRecurring)
                                  _InfoBadge(
                                    icon: Icons.repeat_rounded,
                                    label: 'Recurring',
                                  ),
                                if (_isCollab)
                                  _InfoBadge(
                                    icon: Icons.group_outlined,
                                    label: 'Collab',
                                  ),
                                if (_isForeignCurrency)
                                  _InfoBadge(
                                    icon: Icons.language_rounded,
                                    label: _currency,
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xl),
                          ],

                          // ── Amount ──────────────────────────────────────
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
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  _currency,
                                  style: const TextStyle(
                                    fontSize: 28,
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

                          // ── Home amount + rate (foreign currency only) ───
                          if (_isForeignCurrency) ...[
                            const SizedBox(height: AppSpacing.lg),
                            _SectionLabel('Home Amount ($_homeCurrency)'),
                            const SizedBox(height: AppSpacing.md),
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
                                    _homeCurrency,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: TextField(
                                      controller: _homeAmountController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      inputFormatters: [AmountInputFormatter()],
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                      textAlign: TextAlign.right,
                                      decoration: const InputDecoration(
                                        hintText: '0.00',
                                        hintStyle: TextStyle(
                                          color: AppColors.textTertiary,
                                          fontSize: 24,
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
                            const SizedBox(height: AppSpacing.lg),
                            _SectionLabel(
                              'Conversion Rate (1 $_homeCurrency = ? $_currency)',
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextField(
                              controller: _conversionRateController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
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
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg),
                                  borderSide:
                                      const BorderSide(color: AppColors.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg),
                                  borderSide:
                                      const BorderSide(color: AppColors.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg),
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

                          // ── Receipt ─────────────────────────────────────
                          _ReceiptRow(
                            receiptUrl: _receiptUrl,
                            isUploading: _receiptUploading,
                            onAdd: _pickReceipt,
                            onDelete: _deleteReceipt,
                          ),

                          const SizedBox(height: AppSpacing.xxl),

                          // ── Category ────────────────────────────────────
                          const _SectionLabel('Category'),
                          const SizedBox(height: AppSpacing.md),
                          Consumer(
                            builder: (context, ref, _) {
                              final categoriesAsync =
                                  ref.watch(pickerCategoriesProvider);
                              return categoriesAsync.when(
                                data: (cats) => _CategoryPicker(
                                  categories: cats,
                                  selectedId: _selectedCategoryId,
                                  onSelect: (id) =>
                                      setState(() => _selectedCategoryId = id),
                                  onAddTap: () =>
                                      context.push(settingsCategoriesRoute),
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
                              );
                            },
                          ),

                          const SizedBox(height: AppSpacing.xxl),

                          // ── Account ─────────────────────────────────────
                          const _SectionLabel('Account'),
                          const SizedBox(height: AppSpacing.md),
                          Consumer(
                            builder: (context, ref, _) {
                              final accountsAsync =
                                  ref.watch(pickerAccountsProvider);
                              return accountsAsync.when(
                                data: (accounts) => _AccountPicker(
                                  accounts: accounts,
                                  selectedId: _selectedAccountId,
                                  onSelect: (id) =>
                                      setState(() => _selectedAccountId = id),
                                  onAddTap: () =>
                                      context.push(settingsAccountsRoute),
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
                              );
                            },
                          ),

                          const SizedBox(height: AppSpacing.xxl),

                          // ── Date ────────────────────────────────────────
                          const _SectionLabel('Date'),
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
                                borderRadius:
                                    BorderRadius.circular(AppRadius.lg),
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

                          // ── Description ─────────────────────────────────
                          const _SectionLabel('Description'),
                          const SizedBox(height: AppSpacing.md),
                          TextField(
                            controller: _noteController,
                            maxLines: 3,
                            minLines: 1,
                            textCapitalization: TextCapitalization.sentences,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Add a note...',
                              hintStyle: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 14,
                              ),
                              filled: true,
                              fillColor: AppColors.surface,
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.lg),
                                borderSide:
                                    const BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.lg),
                                borderSide:
                                    const BorderSide(color: AppColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.lg),
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

                          // ── Save button ─────────────────────────────────
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: (_saving || _loading) ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: AppColors.accentText,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg),
                                ),
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.accentText,
                                      ),
                                    )
                                  : const Text(
                                      'Save Changes',
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

            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}

// ── Info badge ────────────────────────────────────────────────────────────────

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

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

// ── Category picker ───────────────────────────────────────────────────────────

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    required this.onAddTap,
  });

  final List<CategoryModel> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        ...categories.map((cat) {
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
        }),
        GestureDetector(
          onTap: onAddTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.borderDashed, width: 1.5),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 14, color: AppColors.textSecondary),
                SizedBox(width: 4),
                Text(
                  'Add',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Receipt row ───────────────────────────────────────────────────────────────

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    required this.receiptUrl,
    required this.isUploading,
    required this.onAdd,
    required this.onDelete,
  });

  final String? receiptUrl;
  final bool isUploading;
  final VoidCallback onAdd;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Receipt'),
        const SizedBox(height: AppSpacing.md),
        if (isUploading)
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          )
        else if (receiptUrl == null)
          GestureDetector(
            onTap: onAdd,
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.borderDashed, width: 1.5),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_rounded,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Text(
                    'Add receipt',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Stack(
            children: [
              GestureDetector(
                onTap: () => showReceiptViewer(context, receiptUrl!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: CachedNetworkImage(
                    imageUrl: receiptUrl!,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ── Account picker ────────────────────────────────────────────────────────────

class _AccountPicker extends StatelessWidget {
  const _AccountPicker({
    required this.accounts,
    required this.selectedId,
    required this.onSelect,
    required this.onAddTap,
  });

  final List<AccountModel> accounts;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        ...accounts.map((acc) {
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
        }),
        GestureDetector(
          onTap: onAddTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.borderDashed, width: 1.5),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 14, color: AppColors.textSecondary),
                SizedBox(width: 4),
                Text(
                  'Add',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
