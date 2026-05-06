import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/amount_input_formatter.dart';
import '../../../../service_locator.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../auth/providers/states/auth_state.dart';
import '../../../contacts/data/models/contact_model.dart';
import '../../../contacts/data/models/group_model.dart';
import '../../../contacts/providers/contacts_provider.dart';
import '../../../contacts/providers/groups_provider.dart';
import '../../../home/providers/home/home_provider.dart';
import '../../../split_bills/providers/split_bills_provider.dart';
import '../../data/models/account_model.dart';
import '../../data/models/category_model.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/categories_provider.dart';
import '../../providers/create_expense_provider.dart';
import '../../utils/expense_ui_helpers.dart';

class AddExpenseSheet extends ConsumerStatefulWidget {
  const AddExpenseSheet({super.key});

  @override
  ConsumerState<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<AddExpenseSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // ── Expense tab state ──────────────────────────────────────────────────────
  final _amountController = TextEditingController();
  String? _selectedCategoryId;
  String? _selectedAccountId;
  DateTime _selectedDate = DateTime.now();
  final _noteController = TextEditingController();

  // ── Split bill tab state ───────────────────────────────────────────────────
  final _splitAmountController = TextEditingController();
  final _splitNoteController = TextEditingController();
  String? _splitCategoryId;
  String? _splitAccountId;
  DateTime _splitDate = DateTime.now();
  final List<_SplitParticipant> _splitParticipants = [];
  bool _equalSplit = false;
  bool _splitLoading = false;
  String? _splitError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    final userId = supabase.auth.currentUser?.id ?? '';
    final you = _SplitParticipant(
      userId: userId,
      displayName: 'You',
      isCurrentUser: true,
    );
    you.controller.addListener(_onParticipantChanged);
    _splitParticipants.add(you);
    _splitAmountController.addListener(_onSplitAmountChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _splitAmountController.dispose();
    _splitNoteController.dispose();
    for (final p in _splitParticipants) {
      p.controller.dispose();
    }
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _onParticipantChanged() {
    if (mounted) setState(() {});
  }

  void _onSplitAmountChanged() {
    if (_equalSplit) _applyEqualSplit();
    if (mounted) setState(() {});
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) return 'Today';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final m = months[date.month - 1];
    return date.year == now.year
        ? '$m ${date.day}'
        : '$m ${date.day}, ${date.year}';
  }

  String get _formattedDate => _formatDate(_selectedDate);
  String get _splitFormattedDate => _formatDate(_splitDate);

  int get _splitTotalCents {
    final v = double.tryParse(_splitAmountController.text.trim());
    if (v == null || v <= 0) return 0;
    return (v * 100).round();
  }

  int get _splitRemainingCents {
    final total = _splitTotalCents;
    var allocated = 0;
    for (final p in _splitParticipants) {
      final v = double.tryParse(p.controller.text.trim());
      if (v != null && v > 0) allocated += (v * 100).round();
    }
    return total - allocated;
  }

  bool get _splitCanSubmit {
    if (_splitLoading) return false;
    if (_splitTotalCents <= 0) return false;
    if (_splitCategoryId == null) return false;
    if (_splitAccountId == null) return false;
    return _splitParticipants.any(
      (p) =>
          !p.isCurrentUser &&
          (double.tryParse(p.controller.text.trim()) ?? 0) > 0,
    );
  }

  void _applyEqualSplit() {
    final total = _splitTotalCents;
    final count = _splitParticipants.length;
    if (count == 0 || total == 0) return;
    final base = total ~/ count;
    final remainder = total - (base * count);
    for (var i = 0; i < count; i++) {
      final cents = i < remainder ? base + 1 : base;
      _splitParticipants[i].controller.text = (cents / 100).toStringAsFixed(2);
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

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

  Future<void> _pickSplitDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _splitDate,
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
    if (picked != null) setState(() => _splitDate = picked);
  }

  void _addSplitParticipant(ContactModel contact) {
    final p = _SplitParticipant(
      userId: contact.friendId,
      displayName: contact.displayName,
      isCurrentUser: false,
    );
    p.controller.addListener(_onParticipantChanged);
    setState(() {
      _splitParticipants.add(p);
      if (_equalSplit) _applyEqualSplit();
    });
  }

  void _removeSplitParticipant(int index) {
    setState(() {
      _splitParticipants[index].controller
        ..removeListener(_onParticipantChanged)
        ..dispose();
      _splitParticipants.removeAt(index);
      if (_equalSplit) _applyEqualSplit();
    });
  }

  void _showContactPicker() {
    final addedIds = _splitParticipants.map((p) => p.userId).toSet();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ContactPickerSheet(
        addedUserIds: addedIds,
        onSelect: _addSplitParticipant,
      ),
    );
  }

  void _addParticipantsFromGroup(GroupModel group) {
    final addedIds = _splitParticipants.map((p) => p.userId).toSet();
    final newMembers = group.members.where((m) => !addedIds.contains(m.id));
    if (newMembers.isEmpty) return;
    setState(() {
      for (final member in newMembers) {
        final p = _SplitParticipant(
          userId: member.id,
          displayName: member.displayName,
          isCurrentUser: false,
        );
        p.controller.addListener(_onParticipantChanged);
        _splitParticipants.add(p);
      }
      if (_equalSplit) _applyEqualSplit();
    });
  }

  void _showGroupPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _GroupPickerSheet(
        onSelect: (group) {
          _addParticipantsFromGroup(group);
          context.pop();
        },
      ),
    );
  }

  Future<void> _submit() async {
    final text = _amountController.text.trim();
    if (text.isEmpty) return;
    final amount = double.tryParse(text);
    if (amount == null || amount <= 0) return;

    final amountCents = (amount * 100).round();
    final currency =
        ref
            .read(authProvider)
            .whenOrNull(authenticated: (user) => user.defaultCurrency) ??
        'MYR';

    final ok = await ref
        .read(createExpenseProvider.notifier)
        .submit(
          amountCents: amountCents,
          currency: currency,
          date: _selectedDate,
          categoryId: _selectedCategoryId,
          accountId: _selectedAccountId,
          note: _noteController.text.trim(),
        );

    if (ok && mounted) {
      ref.invalidate(homeDataProvider);
      context.pop();
    }
  }

  Future<void> _submitSplitBill() async {
    if (!_splitCanSubmit) return;

    final currency =
        ref
            .read(authProvider)
            .whenOrNull(authenticated: (u) => u.defaultCurrency) ??
        'MYR';

    final shares = _splitParticipants
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
          'p_currency': currency,
          'p_note': _splitNoteController.text.trim(),
          'p_expense_date': DateFormat('yyyy-MM-dd').format(_splitDate),
          'p_category_id': _splitCategoryId,
          'p_collab_id': null,
          'p_group_id': null,
          'p_google_place_id': null,
          'p_place_name': null,
          'p_latitude': null,
          'p_longitude': null,
          'p_receipt_url': null,
          'p_shares': shares,
          'p_home_amount_cents': _splitTotalCents,
          'p_home_currency': currency,
          'p_conversion_rate': null,
          'p_account_id': _splitAccountId,
        },
      );

      if (mounted) {
        ref.invalidate(splitBillsProvider);
        ref.invalidate(homeDataProvider);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _splitError = 'Failed to create split bill. Please try again.';
          _splitLoading = false;
        });
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(createExpenseProvider).isLoading;
    final errorMsg = ref.watch(createExpenseProvider).error;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        height: MediaQuery.sizeOf(context).height * .9,
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
              // ── Header ─────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Row(
                  children: [
                    const Text(
                      'Add Transaction',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
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

              // ── Tabs ───────────────────────────────────────────────────────
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
                    Tab(text: 'Expense'),
                    Tab(text: 'Split Bill'),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),

              // ── Body ───────────────────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _ExpenseForm(
                      amountController: _amountController,
                      selectedCategoryId: _selectedCategoryId,
                      selectedAccountId: _selectedAccountId,
                      selectedDate: _selectedDate,
                      formattedDate: _formattedDate,
                      noteController: _noteController,
                      errorMsg: errorMsg,
                      onCategorySelect: (id) =>
                          setState(() => _selectedCategoryId = id),
                      onAccountSelect: (id) =>
                          setState(() => _selectedAccountId = id),
                      onDateTap: _pickDate,
                      onAddCategory: () {
                        context.push(settingsCategoriesRoute);
                      },
                      onAddAccount: () {
                        context.push(settingsAccountsRoute);
                      },
                    ),
                    _SplitBillForm(
                      amountController: _splitAmountController,
                      noteController: _splitNoteController,
                      selectedCategoryId: _splitCategoryId,
                      selectedAccountId: _splitAccountId,
                      formattedDate: _splitFormattedDate,
                      participants: _splitParticipants,
                      equalSplit: _equalSplit,
                      remainingCents: _splitRemainingCents,
                      splitError: _splitError,
                      onCategorySelect: (id) =>
                          setState(() => _splitCategoryId = id),
                      onAccountSelect: (id) =>
                          setState(() => _splitAccountId = id),
                      onDateTap: _pickSplitDate,
                      onEqualSplitToggle: (value) => setState(() {
                        _equalSplit = value;
                        if (value) _applyEqualSplit();
                      }),
                      onAddParticipant: _showContactPicker,
                      onAddGroup: _showGroupPicker,
                      onRemoveParticipant: _removeSplitParticipant,
                      onAddCategory: () {
                        context.push(settingsCategoriesRoute);
                      },
                      onAddAccount: () {
                        context.push(settingsAccountsRoute);
                      },
                    ),
                  ],
                ),
              ),

              // ── Submit ─────────────────────────────────────────────────────
              if (_tabController.index == 0)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.md,
                    AppSpacing.xl,
                    AppSpacing.xl + MediaQuery.of(context).padding.bottom,
                  ),
                  child: FilledButton(
                    onPressed: isLoading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.accentText,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                    ),
                    child: isLoading
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
                )
              else
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.md,
                    AppSpacing.xl,
                    AppSpacing.xl + MediaQuery.of(context).padding.bottom,
                  ),
                  child: FilledButton(
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

class _ExpenseForm extends ConsumerWidget {
  const _ExpenseForm({
    required this.amountController,
    required this.selectedCategoryId,
    required this.selectedAccountId,
    required this.selectedDate,
    required this.formattedDate,
    required this.noteController,
    required this.onCategorySelect,
    required this.onAccountSelect,
    required this.onDateTap,
    required this.onAddCategory,
    required this.onAddAccount,
    this.errorMsg,
  });

  final TextEditingController amountController;
  final String? selectedCategoryId;
  final String? selectedAccountId;
  final DateTime selectedDate;
  final String formattedDate;
  final TextEditingController noteController;
  final ValueChanged<String?> onCategorySelect;
  final ValueChanged<String?> onAccountSelect;
  final VoidCallback onDateTap;
  final VoidCallback onAddCategory;
  final VoidCallback onAddAccount;
  final String? errorMsg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(pickerCategoriesProvider);
    final accountsAsync = ref.watch(pickerAccountsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Amount ─────────────────────────────────────────────────────
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
                const Text(
                  'RM',
                  style: TextStyle(
                    fontSize: 28,
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

          if (errorMsg != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              errorMsg!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFE24B4A)),
            ),
          ],

          const SizedBox(height: AppSpacing.xxl),

          // ── Category ───────────────────────────────────────────────────
          const _SectionLabel('Category'),
          const SizedBox(height: AppSpacing.md),
          categoriesAsync.when(
            data: (cats) => _CategoryPicker(
              categories: cats,
              selectedId: selectedCategoryId,
              onSelect: onCategorySelect,
              onAddTap: onAddCategory,
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
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // ── Account ────────────────────────────────────────────────────
          const _SectionLabel('Account'),
          const SizedBox(height: AppSpacing.md),
          accountsAsync.when(
            data: (accounts) => _AccountPicker(
              accounts: accounts,
              selectedId: selectedAccountId,
              onSelect: onAccountSelect,
              onAddTap: onAddAccount,
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
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // ── Date ───────────────────────────────────────────────────────
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
                    formattedDate,
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

          // ── Note ───────────────────────────────────────────────────────
          const _SectionLabel('Description'),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: noteController,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Add a note...',
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

class _SplitBillForm extends ConsumerWidget {
  const _SplitBillForm({
    required this.amountController,
    required this.noteController,
    required this.selectedCategoryId,
    required this.selectedAccountId,
    required this.formattedDate,
    required this.participants,
    required this.equalSplit,
    required this.remainingCents,
    required this.onCategorySelect,
    required this.onAccountSelect,
    required this.onDateTap,
    required this.onEqualSplitToggle,
    required this.onAddParticipant,
    required this.onAddGroup,
    required this.onRemoveParticipant,
    required this.onAddCategory,
    required this.onAddAccount,
    this.splitError,
  });

  final TextEditingController amountController;
  final TextEditingController noteController;
  final String? selectedCategoryId;
  final String? selectedAccountId;
  final String formattedDate;
  final List<_SplitParticipant> participants;
  final bool equalSplit;
  final int remainingCents;
  final String? splitError;
  final ValueChanged<String?> onCategorySelect;
  final ValueChanged<String?> onAccountSelect;
  final VoidCallback onDateTap;
  final ValueChanged<bool> onEqualSplitToggle;
  final VoidCallback onAddParticipant;
  final VoidCallback onAddGroup;
  final ValueChanged<int> onRemoveParticipant;
  final VoidCallback onAddCategory;
  final VoidCallback onAddAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(pickerCategoriesProvider);
    final accountsAsync = ref.watch(pickerAccountsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Amount ─────────────────────────────────────────────────────
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
                const Text(
                  'RM',
                  style: TextStyle(
                    fontSize: 28,
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

          if (splitError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              splitError!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFE24B4A)),
            ),
          ],

          const SizedBox(height: AppSpacing.xxl),

          // ── Category ───────────────────────────────────────────────────
          const _SectionLabel('Category'),
          const SizedBox(height: AppSpacing.md),
          categoriesAsync.when(
            data: (cats) => _CategoryPicker(
              categories: cats,
              selectedId: selectedCategoryId,
              onSelect: onCategorySelect,
              onAddTap: onAddCategory,
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
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // ── Account ────────────────────────────────────────────────────
          const _SectionLabel('Account'),
          const SizedBox(height: AppSpacing.md),
          accountsAsync.when(
            data: (accounts) => _AccountPicker(
              accounts: accounts,
              selectedId: selectedAccountId,
              onSelect: onAccountSelect,
              onAddTap: onAddAccount,
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
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // ── Date ───────────────────────────────────────────────────────
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
                    formattedDate,
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

          // ── Note ───────────────────────────────────────────────────────
          const _SectionLabel('Description'),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: noteController,
            maxLines: 2,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
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

          // ── Split with ─────────────────────────────────────────────────
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

          // ── Participants list ───────────────────────────────────────────
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
                    readOnly: equalSplit,
                    onRemove: participants[i].isCurrentUser
                        ? null
                        : () => onRemoveParticipant(i),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // ── Add person / Add group buttons ──────────────────────────────
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onAddParticipant,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.lg,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      border: Border.all(color: AppColors.borderDashed),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Text(
                          'Add person',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: GestureDetector(
                  onTap: onAddGroup,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.lg,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      border: Border.all(color: AppColors.borderDashed),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.group_add_rounded,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Text(
                          'Add group',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── Remaining indicator (manual mode only) ──────────────────────
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
                      ? 'RM ${(remainingCents.abs() / 100).toStringAsFixed(2)} over'
                      : 'RM ${(remainingCents / 100).toStringAsFixed(2)}',
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

// ── Participant row ───────────────────────────────────────────────────────────

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.readOnly,
    this.onRemove,
  });

  final _SplitParticipant participant;
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
          // Avatar
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
          // Name
          Expanded(
            child: Text(
              participant.displayName,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.md),

          // Share amount field
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

          // Remove button or spacer
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

// ── Contact picker sheet ──────────────────────────────────────────────────────

class _ContactPickerSheet extends ConsumerWidget {
  const _ContactPickerSheet({
    required this.addedUserIds,
    required this.onSelect,
  });

  final Set<String> addedUserIds;
  final ValueChanged<ContactModel> onSelect;

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
              'Add person',
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
              if (contacts.isEmpty) {
                return Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Column(
                    spacing: AppSpacing.sm,
                    children: [
                      Text(
                        'No contacts yet',
                        style: TextStyle(color: AppColors.textTertiary),
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.add_rounded,
                          color: AppColors.accent,
                        ),
                        title: Text(
                          'Add Contact',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        onTap: () => context.push(contactsRoute),
                      ),
                    ],
                  ),
                );
              }
              return LimitedBox(
                maxHeight: 320,
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  itemCount: contacts.length,
                  itemBuilder: (context, i) {
                    final contact = contacts[i];
                    final isAdded = addedUserIds.contains(contact.friendId);

                    if (i == 0) {
                      return Column(
                        children: [
                          ListTile(
                            leading: Icon(
                              Icons.add_rounded,
                              color: AppColors.accent,
                            ),
                            title: Text(
                              'Add Contact',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            onTap: () => context.push(contactsRoute),
                          ),
                          ListTile(
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
                            title: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: contact.displayName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: isAdded
                                          ? AppColors.textTertiary
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' @${contact.username}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w300,
                                      color: isAdded
                                          ? AppColors.textTertiary
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            trailing: isAdded
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: AppColors.positiveDark,
                                  )
                                : null,
                            onTap: isAdded
                                ? null
                                : () {
                                    onSelect(contact);
                                    context.pop();
                                  },
                          ),
                        ],
                      );
                    }
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
                      title: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: contact.displayName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: isAdded
                                    ? AppColors.textTertiary
                                    : AppColors.textPrimary,
                              ),
                            ),
                            TextSpan(
                              text: ' @${contact.username}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w300,
                                color: isAdded
                                    ? AppColors.textTertiary
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: isAdded
                          ? const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: AppColors.positiveDark,
                            )
                          : null,
                      onTap: isAdded
                          ? null
                          : () {
                              onSelect(contact);
                              context.pop();
                            },
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

// ── Group picker sheet ────────────────────────────────────────────────────────

class _GroupPickerSheet extends ConsumerWidget {
  const _GroupPickerSheet({required this.onSelect});

  final ValueChanged<GroupModel> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(pickerGroupsProvider);

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
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.xxl,
              AppSpacing.xxl,
              AppSpacing.lg,
            ),
            child: Text(
              'Add group',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          groupsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Text(
                'Failed to load groups',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            data: (groups) {
              if (groups.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Text(
                    'No groups yet. Create one in Contacts.',
                    style: TextStyle(color: AppColors.textTertiary),
                  ),
                );
              }
              return LimitedBox(
                maxHeight: 320,
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  itemCount: groups.length,
                  itemBuilder: (context, i) {
                    final group = groups[i];
                    final color = _hexToColor(group.color);
                    final memberCount = group.members.length;
                    return ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.group_rounded,
                          size: 18,
                          color: color,
                        ),
                      ),
                      title: Text(
                        group.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        '$memberCount ${memberCount == 1 ? 'member' : 'members'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      onTap: () => onSelect(group),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Color _hexToColor(String hex) {
    final h = hex.replaceFirst('#', '');
    return Color(int.parse('FF$h', radix: 16));
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

// ── Split participant data class ──────────────────────────────────────────────

class _SplitParticipant {
  _SplitParticipant({
    required this.userId,
    required this.displayName,
    required this.isCurrentUser,
  });

  final String userId;
  final String displayName;
  final bool isCurrentUser;
  final TextEditingController controller = TextEditingController();
}
