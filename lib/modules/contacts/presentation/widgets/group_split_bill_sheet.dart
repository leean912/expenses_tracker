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
import '../../../contacts/providers/contacts_provider.dart';
import '../../../expenses/data/models/account_model.dart';
import '../../../expenses/data/models/category_model.dart';
import '../../../expenses/providers/accounts_provider.dart';
import '../../../expenses/providers/categories_provider.dart';
import '../../../expenses/utils/expense_ui_helpers.dart';
import '../../../home/providers/home/home_provider.dart';
import '../../../split_bills/providers/split_bills_provider.dart';
import '../../data/models/group_model.dart';

class GroupSplitBillSheet extends ConsumerStatefulWidget {
  const GroupSplitBillSheet({super.key, required this.group});

  final GroupModel group;

  @override
  ConsumerState<GroupSplitBillSheet> createState() =>
      _GroupSplitBillSheetState();
}

class _GroupSplitBillSheetState extends ConsumerState<GroupSplitBillSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String? _categoryId;
  String? _accountId;
  DateTime _date = DateTime.now();
  final List<_Participant> _participants = [];
  bool _equalSplit = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final userId = supabase.auth.currentUser?.id ?? '';
    final you = _Participant(userId: userId, displayName: 'You', isMe: true);
    you.controller.addListener(_onParticipantChanged);
    _participants.add(you);

    for (final member in widget.group.members) {
      final p = _Participant(
        userId: member.id,
        displayName: member.displayName,
        isMe: false,
      );
      p.controller.addListener(_onParticipantChanged);
      _participants.add(p);
    }

    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    for (final p in _participants) {
      p.controller.dispose();
    }
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  void _onParticipantChanged() {
    if (mounted) setState(() {});
  }

  void _onAmountChanged() {
    if (_equalSplit) _applyEqualSplit();
    if (mounted) setState(() {});
  }

  int get _totalCents {
    final v = double.tryParse(_amountController.text.trim());
    if (v == null || v <= 0) return 0;
    return (v * 100).round();
  }

  int get _remainingCents {
    final total = _totalCents;
    var allocated = 0;
    for (final p in _participants) {
      final v = double.tryParse(p.controller.text.trim());
      if (v != null && v > 0) allocated += (v * 100).round();
    }
    return total - allocated;
  }

  bool get _canSubmit {
    if (_loading) return false;
    if (_totalCents <= 0) return false;
    if (_categoryId == null) return false;
    if (_accountId == null) return false;
    return _participants.any(
      (p) => !p.isMe && (double.tryParse(p.controller.text.trim()) ?? 0) > 0,
    );
  }

  void _applyEqualSplit() {
    final total = _totalCents;
    final count = _participants.length;
    if (count == 0 || total == 0) return;
    final base = total ~/ count;
    final remainder = total - (base * count);
    for (var i = 0; i < count; i++) {
      final cents = i < remainder ? base + 1 : base;
      _participants[i].controller.text = (cents / 100).toStringAsFixed(2);
    }
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

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
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
    if (picked != null) setState(() => _date = picked);
  }

  void _addParticipant(ContactModel contact) {
    final p = _Participant(
      userId: contact.friendId,
      displayName: contact.displayName,
      isMe: false,
    );
    p.controller.addListener(_onParticipantChanged);
    setState(() {
      _participants.add(p);
      if (_equalSplit) _applyEqualSplit();
    });
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

  void _showContactPicker() {
    final addedIds = _participants.map((p) => p.userId).toSet();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ContactPickerSheet(
        addedUserIds: addedIds,
        onSelect: _addParticipant,
      ),
    );
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final currency =
        ref
            .read(authProvider)
            .whenOrNull(authenticated: (u) => u.defaultCurrency) ??
        'MYR';

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
      _loading = true;
      _error = null;
    });

    try {
      await supabase.rpc(
        'create_split_bill',
        params: {
          'p_paid_by': supabase.auth.currentUser!.id,
          'p_total_amount_cents': _totalCents,
          'p_currency': currency,
          'p_note': _noteController.text.trim(),
          'p_expense_date': DateFormat('yyyy-MM-dd').format(_date),
          'p_category_id': _categoryId,
          'p_collab_id': null,
          'p_group_id': widget.group.id,
          'p_google_place_id': null,
          'p_place_name': null,
          'p_latitude': null,
          'p_longitude': null,
          'p_receipt_url': null,
          'p_shares': shares,
          'p_home_amount_cents': _totalCents,
          'p_home_currency': currency,
          'p_conversion_rate': null,
          'p_account_id': _accountId,
        },
      );
      if (mounted) {
        ref.invalidate(splitBillsProvider);
        ref.invalidate(homeDataProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Split bill created')));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Failed to create split bill. Please try again.';
          _loading = false;
        });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final accountsAsync = ref.watch(accountsProvider);

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
              // ── Header ──────────────────────────────────────────────────────
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
                      'Create Split Bill',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
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

              // ── Body ────────────────────────────────────────────────────────
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

                      const SizedBox(height: AppSpacing.xxl),

                      // Category
                      const _SectionLabel('Category'),
                      const SizedBox(height: AppSpacing.md),
                      categoriesAsync.when(
                        data: (cats) => _CategoryPicker(
                          categories: cats,
                          selectedId: _categoryId,
                          onSelect: (id) => setState(() => _categoryId = id),
                          onAddTap: () => context.push(settingsCategoriesRoute),
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
                      const _SectionLabel('Account'),
                      const SizedBox(height: AppSpacing.md),
                      accountsAsync.when(
                        data: (accounts) => _AccountPicker(
                          accounts: accounts,
                          selectedId: _accountId,
                          onSelect: (id) => setState(() => _accountId = id),
                          onAddTap: () => context.push(settingsAccountsRoute),
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
                                _formatDate(_date),
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

                      // Split with header
                      Row(
                        children: [
                          const _SectionLabel('Split with'),
                          const Spacer(),
                          const Text(
                            'Equal split',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Switch(
                            value: _equalSplit,
                            onChanged: (v) {
                              setState(() => _equalSplit = v);
                              if (v) _applyEqualSplit();
                            },
                            activeThumbColor: AppColors.accentText,
                            activeTrackColor: AppColors.accent,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // Participants list
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            for (int i = 0; i < _participants.length; i++) ...[
                              if (i > 0)
                                const Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: AppColors.border,
                                ),
                              _ParticipantRow(
                                participant: _participants[i],
                                readOnly: _equalSplit,
                                onRemove: _participants[i].isMe
                                    ? null
                                    : () => _removeParticipant(i),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpacing.md),

                      // Add person button
                      GestureDetector(
                        onTap: _showContactPicker,
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

                      // Remaining indicator
                      if (!_equalSplit && _remainingCents != 0) ...[
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Text(
                              'Remaining: ',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textTertiary,
                              ),
                            ),
                            Text(
                              _remainingCents < 0
                                  ? 'RM ${(_remainingCents.abs() / 100).toStringAsFixed(2)} over'
                                  : 'RM ${(_remainingCents / 100).toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _remainingCents < 0
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
                ),
              ),

              // ── Submit ───────────────────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  AppSpacing.xl + MediaQuery.of(context).padding.bottom,
                ),
                child: FilledButton(
                  onPressed: _canSubmit ? _submit : null,
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
    required this.readOnly,
    this.onRemove,
  });

  final _Participant participant;
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
              final available = contacts
                  .where((c) => !addedUserIds.contains(c.friendId))
                  .toList();
              if (available.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.xxl),
                  child: Text(
                    'All contacts already added',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }
              return LimitedBox(
                maxHeight: 320,
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  itemCount: available.length,
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
                      title: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: contact.displayName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (contact.username != null)
                              TextSpan(
                                text: ' @${contact.username}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w300,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      onTap: () {
                        onSelect(contact);
                        Navigator.of(context).pop();
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
