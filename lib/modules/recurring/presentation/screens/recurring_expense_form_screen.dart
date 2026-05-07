import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/amount_input_formatter.dart';
import '../../../expenses/data/models/account_model.dart';
import '../../../expenses/data/models/category_model.dart';
import '../../../expenses/providers/accounts_provider.dart';
import '../../../expenses/providers/categories_provider.dart';
import '../../../expenses/utils/expense_ui_helpers.dart';
import '../../data/models/recurring_expense_model.dart';
import '../../providers/recurring_expenses_provider.dart';
import '../widgets/form_helpers.dart';
import '../widgets/frequency_selector.dart';

class RecurringExpenseFormScreen extends ConsumerStatefulWidget {
  const RecurringExpenseFormScreen({super.key, this.existing});

  final RecurringExpenseModel? existing;

  @override
  ConsumerState<RecurringExpenseFormScreen> createState() =>
      _RecurringExpenseFormScreenState();
}

class _RecurringExpenseFormScreenState
    extends ConsumerState<RecurringExpenseFormScreen> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  String _type = 'expense';
  String _frequency = 'monthly';
  DateTime _runAt = DateTime.now();
  String? _categoryId;
  String? _accountId;
  bool _loading = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleController.text = e.title;
      _amountController.text = (e.amountCents / 100).toStringAsFixed(2);
      _type = e.type;
      _frequency = e.frequency;
      _runAt = e.nextRunAt;
      _categoryId = e.categoryId;
      _accountId = e.accountId;
      _noteController.text = e.note ?? '';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
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
    final amountCents = (amountRm * 100).round();
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();

    setState(() {
      _loading = true;
      _error = null;
    });

    final notifier = ref.read(recurringExpensesProvider.notifier);
    final String? err;

    if (_isEdit) {
      err = await notifier.edit(
        widget.existing!.id,
        title: title,
        amountCents: amountCents,
        frequency: _frequency,
        nextRunAt: _runAt,
        type: _type,
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
        type: _type,
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
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary, size: 20),
            onPressed: () => context.pop(),
          ),
          title: Text(
            _isEdit ? 'Edit Recurring Expense' : 'New Recurring Expense',
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
                    formInputDecoration(hint: 'e.g. Netflix, Gym membership'),
              ),

              const SizedBox(height: AppSpacing.xxl),

              const FormLabel('Type'),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  for (final entry in [
                    ('expense', 'Expense'),
                    ('income', 'Income')
                  ])
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            right: entry.$1 == 'expense' ? AppSpacing.sm : 0),
                        child: GestureDetector(
                          onTap: () => setState(() => _type = entry.$1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _type == entry.$1
                                  ? AppColors.accent
                                  : AppColors.surface,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.lg),
                              border: Border.all(
                                color: _type == entry.$1
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
                                color: _type == entry.$1
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

              const FormLabel('Amount (RM)'),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [AmountInputFormatter()],
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textPrimary),
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

// ── Shared chip picker ────────────────────────────────────────────────────────

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
