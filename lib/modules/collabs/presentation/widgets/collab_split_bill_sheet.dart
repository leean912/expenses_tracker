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
import '../../../home/providers/home/home_provider.dart';
import '../../../split_bills/providers/split_bills_provider.dart';
import '../../data/models/collab_model.dart';
import '../../providers/collab_expenses_provider.dart';

class CollabExpenseSheet extends ConsumerStatefulWidget {
  const CollabExpenseSheet({
    super.key,
    required this.collab,
    this.initialTab = 0,
  });

  final CollabModel collab;
  final int initialTab;

  @override
  ConsumerState<CollabExpenseSheet> createState() => _CollabExpenseSheetState();
}

class _CollabExpenseSheetState extends ConsumerState<CollabExpenseSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // ── Expense tab state ──────────────────────────────────────────────────────
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _rateController = TextEditingController();
  String? _categoryId;
  String? _accountId;
  DateTime _date = DateTime.now();
  bool _expenseLoading = false;
  String? _expenseError;

  // ── Split bill tab state ───────────────────────────────────────────────────
  final _splitAmountController = TextEditingController();
  final _splitNoteController = TextEditingController();
  final _splitRateController = TextEditingController();
  String? _splitCategoryId;
  String? _splitAccountId;
  DateTime _splitDate = DateTime.now();
  final List<_Participant> _participants = [];
  bool _equalSplit = true;
  bool _splitLoading = false;
  String? _splitError;

  CollabModel get collab => widget.collab;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    if (collab.isForeignCurrency && collab.exchangeRate != null) {
      final rateStr = collab.exchangeRate!.toStringAsFixed(
        collab.exchangeRate! >= 10 ? 0 : 4,
      );
      _rateController.text = rateStr;
      _splitRateController.text = rateStr;
    }

    final userId = supabase.auth.currentUser?.id ?? '';
    final you = _Participant(userId: userId, displayName: 'You', isMe: true);
    you.controller.addListener(_onParticipantChanged);
    _participants.add(you);

    for (final member in collab.members.where(
      (m) => m.isActive && m.userId != userId,
    )) {
      final p = _Participant(
        userId: member.userId,
        displayName: member.displayName,
        isMe: false,
      );
      p.controller.addListener(_onParticipantChanged);
      _participants.add(p);
    }

    _splitAmountController.addListener(_onSplitAmountChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _rateController.dispose();
    _splitAmountController.dispose();
    _splitNoteController.dispose();
    _splitRateController.dispose();
    for (final p in _participants) {
      p.controller.dispose();
    }
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _onParticipantChanged() {
    if (mounted) setState(() {});
  }

  void _onSplitAmountChanged() {
    if (_equalSplit) _applyEqualSplit();
    if (mounted) setState(() {});
  }

  int get _splitTotalCents {
    final v = double.tryParse(_splitAmountController.text.trim());
    if (v == null || v <= 0) return 0;
    return (v * 100).round();
  }

  int get _splitRemainingCents {
    final total = _splitTotalCents;
    var allocated = 0;
    for (final p in _participants) {
      final v = double.tryParse(p.controller.text.trim());
      if (v != null && v > 0) allocated += (v * 100).round();
    }
    return total - allocated;
  }

  bool get _splitCanSubmit {
    if (_splitLoading ||
        _splitTotalCents <= 0 ||
        _splitCategoryId == null ||
        _splitAccountId == null) {
      return false;
    }
    if (collab.isForeignCurrency) {
      final rate = double.tryParse(_splitRateController.text.trim());
      if (rate == null || rate <= 0) return false;
    }
    return _participants.any(
      (p) => !p.isMe && (double.tryParse(p.controller.text.trim()) ?? 0) > 0,
    );
  }

  void _applyEqualSplit() {
    final total = _splitTotalCents;
    final count = _participants.length;
    if (count == 0 || total == 0) return;
    final base = total ~/ count;
    final remainder = total - (base * count);
    for (var i = 0; i < count; i++) {
      final cents = i < remainder ? base + 1 : base;
      _participants[i].controller.text = (cents / 100).toStringAsFixed(2);
    }
  }

  void _removeParticipant(int index) {
    setState(() {
      _participants[index].controller
        ..removeListener(_onParticipantChanged)
        ..dispose();
      _participants.removeAt(index);
      if (_equalSplit) _applyEqualSplit();
    });
  }

  Future<void> _pickDate({required bool isSplit}) async {
    final current = isSplit ? _splitDate : _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
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
    if (picked == null) return;
    setState(() => isSplit ? _splitDate = picked : _date = picked);
  }

  // ── Expense submit ─────────────────────────────────────────────────────────

  Future<void> _submitExpense() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      setState(() => _expenseError = 'Please enter an amount.');
      return;
    }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      setState(() => _expenseError = 'Invalid amount.');
      return;
    }

    double? rate;
    if (collab.isForeignCurrency) {
      rate = double.tryParse(_rateController.text.trim());
      if (rate == null || rate <= 0) {
        setState(() => _expenseError = 'Please enter a valid exchange rate.');
        return;
      }
    }

    setState(() {
      _expenseLoading = true;
      _expenseError = null;
    });

    try {
      final amountCents = (amount * 100).round();
      final homeAmountCents = (collab.isForeignCurrency && rate != null)
          ? (amountCents / rate).round()
          : amountCents;

      final payload = <String, dynamic>{
        'user_id': supabase.auth.currentUser!.id,
        'type': 'expense',
        'source': 'manual',
        'collab_id': collab.id,
        'amount_cents': amountCents,
        'currency': collab.currency,
        'home_amount_cents': homeAmountCents,
        'home_currency': collab.homeCurrency,
        'expense_date': DateFormat('yyyy-MM-dd').format(_date),
      };

      if (collab.isForeignCurrency && rate != null) {
        payload['conversion_rate'] = rate;
      }
      if (_categoryId != null) payload['category_id'] = _categoryId;
      if (_accountId != null) payload['account_id'] = _accountId;
      final note = _noteController.text.trim();
      if (note.isNotEmpty) payload['note'] = note;

      await supabase.from('expenses').insert(payload);

      if (mounted) {
        ref.read(collabExpensesProvider(collab.id).notifier).refresh();
        context.pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _expenseError = 'Failed to add expense. Please try again.';
          _expenseLoading = false;
        });
      }
    }
  }

  // ── Split bill submit ──────────────────────────────────────────────────────

  Future<void> _submitSplitBill() async {
    if (!_splitCanSubmit) return;

    double? rate;
    int homeAmountCents;

    if (collab.isForeignCurrency) {
      rate = double.tryParse(_splitRateController.text.trim())!;
      homeAmountCents = (_splitTotalCents / rate).round();
    } else {
      homeAmountCents = _splitTotalCents;
    }

    final shares = _participants
        .map((p) {
          final v = double.tryParse(p.controller.text.trim());
          if (v == null || v <= 0) return null;
          return <String, dynamic>{
            'user_id': p.userId,
            'share_cents': (v * 100).round(),
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    setState(() {
      _splitLoading = true;
      _splitError = null;
    });

    try {
      await supabase.rpc(
        'create_split_bill',
        params: {
          'p_paid_by': supabase.auth.currentUser!.id,
          'p_total_amount_cents': _splitTotalCents,
          'p_currency': collab.currency,
          'p_note': _splitNoteController.text.trim(),
          'p_expense_date': DateFormat('yyyy-MM-dd').format(_splitDate),
          'p_category_id': _splitCategoryId,
          'p_collab_id': collab.id,
          'p_group_id': null,
          'p_google_place_id': null,
          'p_place_name': null,
          'p_latitude': null,
          'p_longitude': null,
          'p_receipt_url': null,
          'p_shares': shares,
          'p_home_amount_cents': homeAmountCents,
          'p_home_currency': collab.homeCurrency,
          'p_conversion_rate': rate,
          'p_account_id': _splitAccountId,
        },
      );

      if (mounted) {
        ref.invalidate(splitBillsProvider);
        ref.invalidate(homeDataProvider);
        ref.read(collabExpensesProvider(collab.id).notifier).refresh();
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Split bill created.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.textPrimary,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _splitError = 'Failed to create split bill. Please try again.';
          _splitLoading = false;
        });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final isExpenseTab = _tabController.index == 0;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        height: MediaQuery.sizeOf(context).height * .8,
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
              // ── Header ────────────────────────────────────────────────────
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
                            'Add to Collab',
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

              // ── Tabs ──────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppColors.textPrimary,
                  unselectedLabelColor: AppColors.textTertiary,
                  indicatorColor: AppColors.textPrimary,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                  tabs: const [
                    Tab(text: 'Add Expense'),
                    Tab(text: 'Split Bill'),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),

              // ── Body ──────────────────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _ExpenseForm(
                      collab: collab,
                      amountController: _amountController,
                      noteController: _noteController,
                      rateController: _rateController,
                      categoryId: _categoryId,
                      accountId: _accountId,
                      date: _date,
                      error: _expenseError,
                      categoriesAsync: categoriesAsync,
                      accountsAsync: accountsAsync,
                      onCategorySelect: (id) =>
                          setState(() => _categoryId = id),
                      onAccountSelect: (id) => setState(() => _accountId = id),
                      onDateTap: () => _pickDate(isSplit: false),
                    ),
                    _SplitBillForm(
                      collab: collab,
                      amountController: _splitAmountController,
                      noteController: _splitNoteController,
                      rateController: _splitRateController,
                      categoryId: _splitCategoryId,
                      accountId: _splitAccountId,
                      date: _splitDate,
                      participants: _participants,
                      equalSplit: _equalSplit,
                      remainingCents: _splitRemainingCents,
                      splitTotalCents: _splitTotalCents,
                      error: _splitError,
                      categoriesAsync: categoriesAsync,
                      accountsAsync: accountsAsync,
                      onCategorySelect: (id) =>
                          setState(() => _splitCategoryId = id),
                      onAccountSelect: (id) =>
                          setState(() => _splitAccountId = id),
                      onDateTap: () => _pickDate(isSplit: true),
                      onEqualSplitToggle: (v) {
                        setState(() => _equalSplit = v);
                        if (v) _applyEqualSplit();
                      },
                      onRemoveParticipant: _removeParticipant,
                    ),
                  ],
                ),
              ),

              // ── Submit ────────────────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  AppSpacing.xl + MediaQuery.of(context).padding.bottom,
                ),
                child: isExpenseTab
                    ? FilledButton(
                        onPressed: _expenseLoading ? null : _submitExpense,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.accentText,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                        ),
                        child: _expenseLoading
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
                      )
                    : FilledButton(
                        onPressed: _splitCanSubmit ? _submitSplitBill : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.accentText,
                          disabledBackgroundColor: AppColors.surfaceMuted,
                          disabledForegroundColor: AppColors.textTertiary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                        ),
                        child: _splitLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accentText,
                                ),
                              )
                            : const Text(
                                'Create Split Bill',
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

// ── Expense form ──────────────────────────────────────────────────────────────

class _ExpenseForm extends StatelessWidget {
  const _ExpenseForm({
    required this.collab,
    required this.amountController,
    required this.noteController,
    required this.rateController,
    required this.categoryId,
    required this.accountId,
    required this.date,
    required this.error,
    required this.categoriesAsync,
    required this.accountsAsync,
    required this.onCategorySelect,
    required this.onAccountSelect,
    required this.onDateTap,
  });

  final CollabModel collab;
  final TextEditingController amountController;
  final TextEditingController noteController;
  final TextEditingController rateController;
  final String? categoryId;
  final String? accountId;
  final DateTime date;
  final String? error;
  final AsyncValue<List<CategoryModel>> categoriesAsync;
  final AsyncValue<List<AccountModel>> accountsAsync;
  final ValueChanged<String?> onCategorySelect;
  final ValueChanged<String?> onAccountSelect;
  final VoidCallback onDateTap;

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    return DateFormat('d MMM yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
              crossAxisAlignment: CrossAxisAlignment.center,
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
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
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

          if (error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              error!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFE24B4A)),
            ),
          ],

          // Exchange rate (foreign currency only)
          if (collab.isForeignCurrency) ...[
            const SizedBox(height: AppSpacing.xxl),
            _SectionLabel('1 ${collab.homeCurrency} = ? ${collab.currency}'),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: rateController,
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
              decoration: _rateDecoration,
            ),
          ],

          const SizedBox(height: AppSpacing.xxl),

          // Category
          const _SectionLabel('Category'),
          const SizedBox(height: AppSpacing.md),
          categoriesAsync.when(
            data: (cats) => _CategoryPicker(
              categories: cats,
              selectedId: categoryId,
              onSelect: onCategorySelect,
              onAddTap: () => context.push(settingsCategoriesRoute),
            ),
            loading: () => const _LoadingPicker(),
            error: (_, _) => const Text(
              'Failed to load categories',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Account
          const _SectionLabel('Account'),
          const SizedBox(height: AppSpacing.md),
          accountsAsync.when(
            data: (accounts) => _AccountPicker(
              accounts: accounts,
              selectedId: accountId,
              onSelect: onAccountSelect,
              onAddTap: () => context.push(settingsAccountsRoute),
            ),
            loading: () => const _LoadingPicker(),
            error: (_, _) => const Text(
              'Failed to load accounts',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Date
          const _SectionLabel('Date'),
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: onDateTap,
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
                    _formatDate(date),
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
          const _SectionLabel('Note (optional)'),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: noteController,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: "What's this for?",
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

          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

// ── Split bill form ───────────────────────────────────────────────────────────

class _SplitBillForm extends StatelessWidget {
  const _SplitBillForm({
    required this.collab,
    required this.amountController,
    required this.noteController,
    required this.rateController,
    required this.categoryId,
    required this.accountId,
    required this.date,
    required this.participants,
    required this.equalSplit,
    required this.remainingCents,
    required this.splitTotalCents,
    required this.error,
    required this.categoriesAsync,
    required this.accountsAsync,
    required this.onCategorySelect,
    required this.onAccountSelect,
    required this.onDateTap,
    required this.onEqualSplitToggle,
    required this.onRemoveParticipant,
  });

  final CollabModel collab;
  final TextEditingController amountController;
  final TextEditingController noteController;
  final TextEditingController rateController;
  final String? categoryId;
  final String? accountId;
  final DateTime date;
  final List<_Participant> participants;
  final bool equalSplit;
  final int remainingCents;
  final int splitTotalCents;
  final String? error;
  final AsyncValue<List<CategoryModel>> categoriesAsync;
  final AsyncValue<List<AccountModel>> accountsAsync;
  final ValueChanged<String?> onCategorySelect;
  final ValueChanged<String?> onAccountSelect;
  final VoidCallback onDateTap;
  final ValueChanged<bool> onEqualSplitToggle;
  final ValueChanged<int> onRemoveParticipant;

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    return DateFormat('d MMM yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
              crossAxisAlignment: CrossAxisAlignment.center,
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
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
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

          if (error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              error!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFE24B4A)),
            ),
          ],

          // Exchange rate (foreign currency only)
          if (collab.isForeignCurrency) ...[
            const SizedBox(height: AppSpacing.xxl),
            _SectionLabel('1 ${collab.homeCurrency} = ? ${collab.currency}'),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: rateController,
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
              decoration: _rateDecoration,
            ),
            if (splitTotalCents > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Builder(
                builder: (_) {
                  final rate = double.tryParse(rateController.text.trim());
                  if (rate == null || rate <= 0) return const SizedBox.shrink();
                  final home = splitTotalCents / rate / 100;
                  return Text(
                    '≈ ${collab.homeCurrency} ${home.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  );
                },
              ),
            ],
          ],

          const SizedBox(height: AppSpacing.xxl),

          // Category
          const _SectionLabel('Category'),
          const SizedBox(height: AppSpacing.md),
          categoriesAsync.when(
            data: (cats) => _CategoryPicker(
              categories: cats,
              selectedId: categoryId,
              onSelect: onCategorySelect,
              onAddTap: () => context.push(settingsCategoriesRoute),
            ),
            loading: () => const _LoadingPicker(),
            error: (_, _) => const Text(
              'Failed to load categories',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Account
          const _SectionLabel('Account'),
          const SizedBox(height: AppSpacing.md),
          accountsAsync.when(
            data: (accounts) => _AccountPicker(
              accounts: accounts,
              selectedId: accountId,
              onSelect: onAccountSelect,
              onAddTap: () => context.push(settingsAccountsRoute),
            ),
            loading: () => const _LoadingPicker(),
            error: (_, _) => const Text(
              'Failed to load accounts',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Date
          const _SectionLabel('Date'),
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: onDateTap,
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
                    _formatDate(date),
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
          const _SectionLabel('Description'),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: noteController,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: "What's this for?",
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

          const SizedBox(height: AppSpacing.xxl),

          // Split with
          Row(
            children: [
              const _SectionLabel('Split with'),
              const Spacer(),
              const Text(
                'Equal split',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Switch(
                value: equalSplit,
                onChanged: onEqualSplitToggle,
                activeThumbColor: AppColors.accentText,
                activeTrackColor: AppColors.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Participants
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (int i = 0; i < participants.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.border,
                    ),
                  _ParticipantRow(
                    participant: participants[i],
                    currency: collab.currency,
                    readOnly: equalSplit,
                    onRemove: participants[i].isMe
                        ? null
                        : () => onRemoveParticipant(i),
                  ),
                ],
              ],
            ),
          ),

          if (!equalSplit && remainingCents != 0) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text(
                  'Remaining: ',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
                Text(
                  remainingCents < 0
                      ? '${collab.currency} ${(remainingCents.abs() / 100).toStringAsFixed(2)} over'
                      : '${collab.currency} ${(remainingCents / 100).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: remainingCents < 0
                        ? const Color(0xFFE24B4A)
                        : AppColors.budgetOverallBar,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

// ── Shared rate field decoration ──────────────────────────────────────────────

InputDecoration get _rateDecoration => InputDecoration(
  hintText: 'e.g. 30',
  hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
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
    borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
  ),
  contentPadding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.lg,
  ),
);

// ── Participant data class ────────────────────────────────────────────────────

class _Participant {
  _Participant({
    required this.userId,
    required this.displayName,
    required this.isMe,
  });

  final String userId;
  final String displayName;
  final bool isMe;
  final TextEditingController controller = TextEditingController();
}

// ── Participant row ───────────────────────────────────────────────────────────

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.currency,
    required this.readOnly,
    this.onRemove,
  });

  final _Participant participant;
  final String currency;
  final bool readOnly;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: Text(
              participant.displayName[0].toUpperCase(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participant.displayName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  currency,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 88,
            child: TextField(
              controller: participant.controller,
              readOnly: readOnly,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [AmountInputFormatter()],
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: readOnly
                    ? AppColors.textTertiary
                    : AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: readOnly
                    ? AppColors.surfaceMuted
                    : AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(
                    color: AppColors.accent,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                isDense: true,
              ),
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.xs),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ] else
            const SizedBox(width: 24),
        ],
      ),
    );
  }
}

// ── Small shared widgets ──────────────────────────────────────────────────────

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

class _LoadingPicker extends StatelessWidget {
  const _LoadingPicker();

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
                Icon(
                  Icons.add_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
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
                Icon(
                  Icons.add_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
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
