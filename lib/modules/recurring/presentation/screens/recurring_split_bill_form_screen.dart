import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/amount_input_formatter.dart';
import '../../../../service_locator.dart';
import '../../../contacts/data/models/contact_model.dart';
import '../../../contacts/data/models/group_model.dart';
import '../../../contacts/providers/contacts_provider.dart';
import '../../../contacts/providers/groups_provider.dart';
import '../../../expenses/data/models/account_model.dart';
import '../../../expenses/data/models/category_model.dart';
import '../../../expenses/providers/accounts_provider.dart';
import '../../../expenses/providers/categories_provider.dart';
import '../../../expenses/utils/expense_ui_helpers.dart';
import '../../data/models/recurring_split_bill_model.dart';
import '../../providers/recurring_split_bills_provider.dart';
import '../widgets/form_helpers.dart';
import '../widgets/frequency_selector.dart';

class RecurringSplitBillFormScreen extends ConsumerStatefulWidget {
  const RecurringSplitBillFormScreen({super.key, this.existing});

  final RecurringSplitBillModel? existing;

  @override
  ConsumerState<RecurringSplitBillFormScreen> createState() =>
      _RecurringSplitBillFormScreenState();
}

class _RecurringSplitBillFormScreenState
    extends ConsumerState<RecurringSplitBillFormScreen> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  String _frequency = 'monthly';
  DateTime _runAt = DateTime.now();
  bool _equalSplit = true;
  String? _categoryId;
  String? _accountId;
  bool _loading = false;
  String? _error;

  final List<_Participant> _participants = [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final userId = supabase.auth.currentUser?.id ?? '';

    final e = widget.existing;
    if (e != null) {
      _titleController.text = e.title;
      _amountController.text = (e.amountCents / 100).toStringAsFixed(2);
      _frequency = e.frequency;
      _runAt = e.nextRunAt;
      _equalSplit = e.splitMethod == 'equal';
      _categoryId = e.categoryId;
      _accountId = e.accountId;
      _noteController.text = e.note ?? '';

      for (final share in e.shares) {
        final p = _Participant(
          userId: share.userId,
          displayName: share.userId == userId ? 'You' : share.displayName,
          isMe: share.userId == userId,
        );
        if (share.shareCents != null) {
          p.controller.text = (share.shareCents! / 100).toStringAsFixed(2);
        }
        p.controller.addListener(_onParticipantChanged);
        _participants.add(p);
      }
    } else {
      final p = _Participant(userId: userId, displayName: 'You', isMe: true);
      p.controller.addListener(_onParticipantChanged);
      _participants.add(p);
    }

    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    for (final p in _participants) {
      p.dispose();
    }
    super.dispose();
  }

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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _runAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
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
    if (picked != null) setState(() => _runAt = picked);
  }

  void _addParticipant(ContactModel contact) {
    final p = _Participant(
      userId: contact.friendId,
      displayName: contact.nickname ?? contact.displayName,
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

  void _addParticipantsFromGroup(GroupModel group) {
    final addedIds = _participants.map((p) => p.userId).toSet();
    final newMembers = group.members.where((m) => !addedIds.contains(m.id));
    if (newMembers.isEmpty) return;
    setState(() {
      for (final member in newMembers) {
        final p = _Participant(
          userId: member.id,
          displayName: member.displayName,
          isMe: false,
        );
        p.controller.addListener(_onParticipantChanged);
        _participants.add(p);
      }
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

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    final amountRm = double.tryParse(_amountController.text);
    if (amountRm == null || amountRm <= 0) {
      setState(() => _error = 'Enter a valid amount greater than 0.');
      return;
    }
    if (_participants.length < 2) {
      setState(() => _error = 'Add at least one other participant.');
      return;
    }
    final amountCents = (amountRm * 100).round();
    final splitMethod = _equalSplit ? 'equal' : 'custom';

    if (!_equalSplit) {
      final totalCustom = _participants.fold<int>(0, (sum, p) {
        final v = double.tryParse(p.controller.text) ?? 0;
        return sum + (v * 100).round();
      });
      if (totalCustom != amountCents) {
        setState(
          () => _error =
              'Custom amounts must sum to RM ${amountRm.toStringAsFixed(2)}. Currently: RM ${(totalCustom / 100).toStringAsFixed(2)}',
        );
        return;
      }
    }

    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();

    final shares = _participants.map((p) {
      final map = <String, dynamic>{'user_id': p.userId};
      if (!_equalSplit) {
        final v = double.tryParse(p.controller.text) ?? 0;
        map['share_cents'] = (v * 100).round();
      } else {
        map['share_cents'] = null;
      }
      return map;
    }).toList();

    setState(() {
      _loading = true;
      _error = null;
    });

    final notifier = ref.read(recurringSplitBillsProvider.notifier);
    final String? err;

    if (_isEdit) {
      err = await notifier.edit(
        widget.existing!.id,
        title: title,
        amountCents: amountCents,
        frequency: _frequency,
        nextRunAt: _runAt,
        splitMethod: splitMethod,
        shares: shares,
        categoryId: _categoryId,
        accountId: _accountId,
        note: note,
      );
    } else {
      err = await notifier.create(
        title: title,
        amountCents: amountCents,
        frequency: _frequency,
        firstRunAt: _runAt,
        splitMethod: splitMethod,
        shares: shares,
        categoryId: _categoryId,
        accountId: _accountId,
        note: note,
      );
    }

    if (!mounted) return;

    if (err == null) {
      context.pop();
    } else {
      setState(() {
        _loading = false;
        _error = err == 'upgrade_required'
            ? 'Free plan limit reached. Upgrade to Premium.'
            : err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(pickerCategoriesProvider);
    final accountsAsync = ref.watch(pickerAccountsProvider);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary,
              size: 20,
            ),
            onPressed: () => context.pop(),
          ),
          title: Text(
            _isEdit ? 'Edit Recurring Split' : 'New Recurring Split',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FormLabel('Title'),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _titleController,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: formInputDecoration(
                  hint: 'e.g. House rent, Internet',
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              const FormLabel('Total Amount (RM)'),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [AmountInputFormatter()],
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: formInputDecoration(hint: '0.00', prefix: 'RM '),
              ),

              const SizedBox(height: AppSpacing.xxl),

              const FormLabel('Frequency'),
              const SizedBox(height: AppSpacing.md),
              FrequencySelector(
                value: _frequency,
                onChanged: (v) => setState(() => _frequency = v),
              ),

              const SizedBox(height: AppSpacing.xxl),

              FormLabel(_isEdit ? 'Next Run Date' : 'First Run Date'),
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
                        DateFormat('d MMM yyyy').format(_runAt),
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

              // ── Category ──────────────────────────────────────────────────
              const FormLabel('Category (Optional)'),
              const SizedBox(height: AppSpacing.md),
              categoriesAsync.when(
                data: (cats) => _ChipPicker<CategoryModel>(
                  items: cats,
                  selectedId: _categoryId,
                  idOf: (c) => c.id,
                  colorOf: (c) => hexToColor(c.color),
                  iconOf: (c) => iconForName(c.icon),
                  labelOf: (c) => c.name,
                  onSelect: (id) => setState(() => _categoryId = id),
                  onAddTap: () => context.push(settingsCategoriesRoute),
                ),
                loading: () => const _PickerLoading(),
                error: (_, _) =>
                    const _PickerError('Failed to load categories'),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // ── Account ───────────────────────────────────────────────────
              const FormLabel('Account (Optional)'),
              const SizedBox(height: AppSpacing.md),
              accountsAsync.when(
                data: (accs) => _ChipPicker<AccountModel>(
                  items: accs,
                  selectedId: _accountId,
                  idOf: (a) => a.id,
                  colorOf: (a) => hexToColor(a.color),
                  iconOf: (a) => iconForName(a.icon),
                  labelOf: (a) => a.name,
                  onSelect: (id) => setState(() => _accountId = id),
                  onAddTap: () => context.push(settingsAccountsRoute),
                ),
                loading: () => const _PickerLoading(),
                error: (_, _) => const _PickerError('Failed to load accounts'),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // ── Split with ─────────────────────────────────────────────────
              Row(
                children: [
                  const Expanded(child: FormLabel('Split with')),
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
                    onChanged: (value) => setState(() {
                      _equalSplit = value;
                      if (value) _applyEqualSplit();
                    }),
                    activeThumbColor: AppColors.accentText,
                    activeTrackColor: AppColors.accent,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Participants list ──────────────────────────────────────────
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

              // ── Add friend / Add group buttons ─────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
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
                              'Add friend',
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
                      onTap: _showGroupPicker,
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

              // ── Remaining indicator (custom mode only) ─────────────────────
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

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFE24B4A),
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.xxl),

              const FormLabel('Note (Optional)'),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _noteController,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: formInputDecoration(hint: 'Add a note'),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // SizedBox(
              //   width: double.infinity,
              //   child: FilledButton(
              //     onPressed: _loading ? null : _save,
              //     style: FilledButton.styleFrom(
              //       backgroundColor: AppColors.accent,
              //       foregroundColor: AppColors.accentText,
              //       padding: const EdgeInsets.symmetric(vertical: 16),
              //       shape: RoundedRectangleBorder(
              //         borderRadius: BorderRadius.circular(AppRadius.lg),
              //       ),
              //     ),
              //     child: _loading
              //         ? const SizedBox(
              //             width: 20,
              //             height: 20,
              //             child: CircularProgressIndicator(
              //               strokeWidth: 2,
              //               color: AppColors.accentText,
              //             ),
              //           )
              //         : Text(
              //             _isEdit ? 'Update' : 'Save',
              //             style: const TextStyle(
              //               fontSize: 15,
              //               fontWeight: FontWeight.w600,
              //             ),
              //           ),
              //   ),
              // ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _save,
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
                    : Text(
                        _isEdit ? 'Update' : 'Save',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ),
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
              participant.displayName.isNotEmpty
                  ? participant.displayName[0].toUpperCase()
                  : '?',
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
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.xxl,
              AppSpacing.xxl,
              AppSpacing.lg,
            ),
            child: Text(
              'Add friend',
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
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Column(
                    spacing: AppSpacing.sm,
                    children: [
                      const Text(
                        'No contacts yet',
                        style: TextStyle(color: AppColors.textTertiary),
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.add_rounded,
                          color: AppColors.accent,
                        ),
                        title: const Text(
                          'Add Friend',
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
                            leading: const Icon(
                              Icons.add_rounded,
                              color: AppColors.accent,
                            ),
                            title: const Text(
                              'Add Friend',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            onTap: () => context.push(contactsRoute),
                          ),
                          _ContactTile(
                            contact: contact,
                            isAdded: isAdded,
                            onSelect: () {
                              onSelect(contact);
                              context.pop();
                            },
                          ),
                        ],
                      );
                    }
                    return _ContactTile(
                      contact: contact,
                      isAdded: isAdded,
                      onSelect: () {
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

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.isAdded,
    required this.onSelect,
  });

  final ContactModel contact;
  final bool isAdded;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
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
                color: isAdded ? AppColors.textTertiary : AppColors.textPrimary,
              ),
            ),
            TextSpan(
              text: ' @${contact.username}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w300,
                color: isAdded ? AppColors.textTertiary : AppColors.textPrimary,
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
      onTap: isAdded ? null : onSelect,
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

// ── Chip picker ───────────────────────────────────────────────────────────────

class _ChipPicker<T> extends StatelessWidget {
  const _ChipPicker({
    required this.items,
    required this.selectedId,
    required this.idOf,
    required this.colorOf,
    required this.iconOf,
    required this.labelOf,
    required this.onSelect,
    required this.onAddTap,
  });

  final List<T> items;
  final String? selectedId;
  final String Function(T) idOf;
  final Color Function(T) colorOf;
  final IconData Function(T) iconOf;
  final String Function(T) labelOf;
  final ValueChanged<String?> onSelect;
  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        ...items.map((item) {
          final isSelected = idOf(item) == selectedId;
          final color = colorOf(item);
          return GestureDetector(
            onTap: () => onSelect(isSelected ? null : idOf(item)),
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
                    iconOf(item),
                    size: 14,
                    color: isSelected ? Colors.white : color,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    labelOf(item),
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

class _PickerLoading extends StatelessWidget {
  const _PickerLoading();

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

class _PickerError extends StatelessWidget {
  const _PickerError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
    );
  }
}

// ── Participant model ─────────────────────────────────────────────────────────

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

  void dispose() {
    controller.dispose();
  }
}
