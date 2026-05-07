import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/amount_input_formatter.dart';
import '../../../../service_locator.dart';
import '../../../contacts/data/models/contact_model.dart';
import '../../../contacts/providers/contacts_provider.dart';
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
  String _splitMethod = 'equal';
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
      _splitMethod = e.splitMethod;
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
        _participants.add(p);
      }
    } else {
      _participants.add(
          _Participant(userId: userId, displayName: 'You', isMe: true));
    }

    _amountController.addListener(() {
      if (mounted) setState(() {});
    });
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

  double get _totalRm => double.tryParse(_amountController.text) ?? 0;

  double get _customAllocatedRm => _participants.fold(
      0, (sum, p) => sum + (double.tryParse(p.controller.text) ?? 0));

  double get _customRemainingRm => _totalRm - _customAllocatedRm;

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

  Future<void> _openParticipantPicker(List<ContactModel> contacts) async {
    final myId = supabase.auth.currentUser?.id ?? '';
    final selectedIds = _participants.map((p) => p.userId).toSet();

    final updated = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        final localSelected = Set<String>.from(selectedIds);
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text('Select Participants',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            contentPadding:
                const EdgeInsets.symmetric(vertical: AppSpacing.md),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  CheckboxListTile(
                    value: true,
                    onChanged: null,
                    title: const Text('You (payer)',
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textPrimary)),
                    activeColor: AppColors.accent,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (contacts.isNotEmpty)
                    const Divider(height: 1, color: AppColors.border),
                  ...contacts.map((c) => CheckboxListTile(
                        value: localSelected.contains(c.friendId),
                        onChanged: (v) => setLocal(() {
                          if (v == true) {
                            localSelected.add(c.friendId);
                          } else {
                            localSelected.remove(c.friendId);
                          }
                        }),
                        title: Text(
                          c.nickname ?? c.displayName,
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.textPrimary),
                        ),
                        subtitle: c.username != null
                            ? Text('@${c.username}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textTertiary))
                            : null,
                        activeColor: AppColors.accent,
                        controlAffinity: ListTileControlAffinity.leading,
                      )),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => ctx.pop(),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () => ctx.pop(localSelected),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.accentText),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      },
    );

    if (updated == null) return;

    setState(() {
      final newList = [
        _Participant(userId: myId, displayName: 'You', isMe: true),
      ];

      for (final id in updated) {
        if (id == myId) continue;
        final contact = contacts.firstWhere((c) => c.friendId == id);
        final existing = _participants.firstWhere(
          (p) => p.userId == id,
          orElse: () => _Participant(
            userId: id,
            displayName: contact.nickname ?? contact.displayName,
            isMe: false,
          ),
        );
        newList.add(existing);
      }

      for (final p in _participants) {
        if (!newList.any((n) => n.userId == p.userId)) p.dispose();
      }

      _participants
        ..clear()
        ..addAll(newList);
    });
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

    if (_splitMethod == 'custom') {
      final totalCustom = _participants.fold<int>(0, (sum, p) {
        final v = double.tryParse(p.controller.text) ?? 0;
        return sum + (v * 100).round();
      });
      if (totalCustom != amountCents) {
        setState(() => _error =
            'Custom amounts must sum to RM ${amountRm.toStringAsFixed(2)}. Currently: RM ${(totalCustom / 100).toStringAsFixed(2)}');
        return;
      }
    }

    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();

    final shares = _participants.map((p) {
      final map = <String, dynamic>{'user_id': p.userId};
      if (_splitMethod == 'custom') {
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
        splitMethod: _splitMethod,
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
        splitMethod: _splitMethod,
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
    final contactsAsync = ref.watch(contactsProvider);
    final contacts = contactsAsync.valueOrNull ?? [];

    final participantCount = _participants.length;
    final equalShareRm =
        participantCount > 0 ? _totalRm / participantCount : 0.0;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary, size: 20),
            onPressed: () => context.pop(),
          ),
          title: Text(
            _isEdit ? 'Edit Recurring Split' : 'New Recurring Split',
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FormLabel('Title'),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _titleController,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary),
                decoration:
                    formInputDecoration(hint: 'e.g. House rent, Internet'),
              ),

              const SizedBox(height: AppSpacing.xxl),

              const FormLabel('Total Amount (RM)'),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [AmountInputFormatter()],
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary),
                decoration:
                    formInputDecoration(hint: '0.00', prefix: 'RM '),
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
                      horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        DateFormat('d MMM yyyy').format(_runAt),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded,
                          size: 18, color: AppColors.textTertiary),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              const FormLabel('Split Method'),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  for (final entry in [
                    ('equal', 'Equal'),
                    ('custom', 'Custom'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            right: entry.$1 == 'equal' ? AppSpacing.sm : 0),
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _splitMethod = entry.$1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _splitMethod == entry.$1
                                  ? AppColors.accent
                                  : AppColors.surface,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.lg),
                              border: Border.all(
                                color: _splitMethod == entry.$1
                                    ? AppColors.accent
                                    : AppColors.border,
                              ),
                            ),
                            child: Text(
                              entry.$2,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _splitMethod == entry.$1
                                    ? AppColors.accentText
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: AppSpacing.xxl),

              Row(
                children: [
                  const Expanded(child: FormLabel('Participants')),
                  GestureDetector(
                    onTap: () => _openParticipantPicker(contacts),
                    child: Text(
                      _participants.length <= 1
                          ? 'Add people'
                          : 'Edit (${_participants.length})',
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              if (_participants.isEmpty)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Center(
                    child: Text('No participants added yet.',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textTertiary)),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < _participants.length; i++) ...[
                        _ParticipantRow(
                          participant: _participants[i],
                          showAmountField: _splitMethod == 'custom',
                          equalShareText: _totalRm > 0
                              ? 'RM ${equalShareRm.toStringAsFixed(2)}'
                              : '—',
                          onChanged: () => setState(() {}),
                        ),
                        if (i < _participants.length - 1)
                          const Divider(height: 1, color: AppColors.border),
                      ],
                    ],
                  ),
                ),

              if (_splitMethod == 'custom' && _participants.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Remaining: RM ${_customRemainingRm.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: _customRemainingRm.abs() < 0.01
                        ? AppColors.positiveDark
                        : const Color(0xFFE24B4A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.xxl),

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
                error: (_, _) => const _PickerError('Failed to load categories'),
              ),

              const SizedBox(height: AppSpacing.xxl),

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

              const FormLabel('Note (Optional)'),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _noteController,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary),
                decoration: formInputDecoration(hint: 'Add a note'),
              ),

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(_error!,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFE24B4A))),
              ],

              const SizedBox(height: AppSpacing.xxl),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.accentText,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accentText),
                        )
                      : Text(
                          _isEdit ? 'Update' : 'Save',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
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
                  horizontal: AppSpacing.lg, vertical: AppSpacing.md),
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
                  Icon(iconOf(item),
                      size: 14,
                      color: isSelected ? Colors.white : color),
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
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
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
              strokeWidth: 2, color: AppColors.textTertiary),
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
    return Text(message,
        style: const TextStyle(fontSize: 12, color: AppColors.textTertiary));
  }
}

// ── Participant row ───────────────────────────────────────────────────────────

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.participant,
    required this.showAmountField,
    required this.equalShareText,
    required this.onChanged,
  });

  final _Participant participant;
  final bool showAmountField;
  final String equalShareText;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                participant.displayName.isNotEmpty
                    ? participant.displayName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(participant.displayName,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary)),
          ),
          if (showAmountField)
            SizedBox(
              width: 110,
              child: TextField(
                controller: participant.controller,
                onChanged: (_) => onChanged(),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [AmountInputFormatter()],
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '0.00',
                  hintStyle: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 13),
                  prefixText: 'RM ',
                  prefixStyle: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.background,
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
                        color: AppColors.accent, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 8),
                ),
              ),
            )
          else
            Text(equalShareText,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
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

  void dispose() => controller.dispose();
}
