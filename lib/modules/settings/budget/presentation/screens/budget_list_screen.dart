import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/utils/amount_input_formatter.dart';
import '../../../../../service_locator.dart';
import '../../../../expenses/providers/categories_provider.dart';
import '../../../../expenses/utils/expense_ui_helpers.dart';
import '../../providers/budget_provider.dart';

class BudgetListScreen extends ConsumerStatefulWidget {
  const BudgetListScreen({super.key});

  @override
  ConsumerState<BudgetListScreen> createState() => _BudgetListScreenState();
}

class _BudgetListScreenState extends ConsumerState<BudgetListScreen> {
  final _deletedIds = <String>{};

  Future<void> _delete(String id) async {
    setState(() => _deletedIds.add(id));
    await supabase
        .from('budgets')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
    ref.invalidate(budgetsProvider);
  }

  void _openForm({BudgetItem? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetFormSheet(
        existing: existing,
        onSaved: () => ref.invalidate(budgetsProvider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final budgetsAsync = ref.watch(budgetsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Budgets',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: budgetsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Failed to load budgets.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.invalidate(budgetsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (budgets) {
          final visibleBudgets = budgets
              .where((b) => !_deletedIds.contains(b.id))
              .toList();
          if (visibleBudgets.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 48,
                    color: AppColors.textTertiary,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No budgets yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tap + to set a spending limit.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            );
          }
          const periodOrder = ['daily', 'weekly', 'monthly', 'yearly'];
          const periodLabels = {
            'daily': 'Daily',
            'weekly': 'Weekly',
            'monthly': 'Monthly',
            'yearly': 'Yearly',
          };

          final grouped = <String, List<BudgetItem>>{};
          for (final b in visibleBudgets) {
            grouped.putIfAbsent(b.period, () => []).add(b);
          }

          final sections = periodOrder
              .where((p) => grouped.containsKey(p))
              .toList();

          final items = <Object>[];
          for (final period in sections) {
            items.add(period);
            items.addAll(grouped[period]!);
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 100),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              if (item is String) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: Text(
                    periodLabels[item] ?? item,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textTertiary,
                      letterSpacing: 0.5,
                    ),
                  ),
                );
              }
              final budget = item as BudgetItem;
              final groupBudgets = grouped[budget.period]!;
              final isLast = groupBudgets.last.id == budget.id;
              return Column(
                children: [
                  _BudgetTile(
                    budget: budget,
                    onEdit: () => _openForm(existing: budget),
                    onDelete: () => _delete(budget.id),
                  ),
                  if (!isLast)
                    const Divider(height: 1, color: AppColors.border),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.accentText,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Budget',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ── Budget tile ───────────────────────────────────────────────────────────────

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({
    required this.budget,
    required this.onEdit,
    required this.onDelete,
  });

  final BudgetItem budget;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Color get _barColor {
    final pct = budget.percentUsed;
    if (pct >= 90) return const Color(0xFFE24B4A);
    if (pct >= 75) return const Color(0xFFF59E0B);
    return AppColors.positiveDark;
  }

  String _periodLabel(String period) {
    switch (period) {
      case 'daily':
        return 'Daily';
      case 'weekly':
        return 'Weekly';
      case 'monthly':
        return 'Monthly';
      case 'yearly':
        return 'Yearly';
      default:
        return period;
    }
  }

  String _fmtCents(int cents) {
    final value = cents / 100;
    final whole = value.truncate();
    final frac = ((value - whole) * 100).round();
    final str = whole.toString();
    final buf = StringBuffer('RM ');
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write(',');
      buf.write(str[i]);
    }
    buf.write('.');
    buf.write(frac.toString().padLeft(2, '0'));
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final barColor = _barColor;
    final progress = budget.progress.clamp(0.0, 1.0);
    final pct = budget.percentUsed;

    return Dismissible(
      key: Key(budget.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: const Text(
              'Delete budget?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            content: const Text(
              "This won't affect your existing expenses.",
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => ctx.pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => ctx.pop(true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Color(0xFFE24B4A)),
                ),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        color: const Color(0xFFE24B4A),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.lg,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: barColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: budget.isOverall
                      ? Icon(
                          Icons.pie_chart_outline_rounded,
                          size: 18,
                          color: barColor,
                        )
                      : Text(
                          budget.label.isNotEmpty
                              ? budget.label[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: barColor,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            budget.label,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            _periodLabel(budget.period),
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_fmtCents(budget.spentCents)} of ${_fmtCents(budget.limitCents)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: AppColors.surfaceMuted,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '$pct% used',
                      style: TextStyle(
                        fontSize: 11,
                        color: barColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Budget form sheet ─────────────────────────────────────────────────────────

class _BudgetFormSheet extends ConsumerStatefulWidget {
  const _BudgetFormSheet({this.existing, required this.onSaved});

  final BudgetItem? existing;
  final VoidCallback onSaved;

  @override
  ConsumerState<_BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends ConsumerState<_BudgetFormSheet> {
  String? _categoryId;
  String _categoryLabel = 'Overall';
  String _period = 'monthly';
  final _limitController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final e = widget.existing!;
      _categoryId = e.categoryId;
      _categoryLabel = e.isOverall ? 'Overall' : e.label;
      _period = e.period;
      final v = e.limitCents / 100;
      _limitController.text = v == v.truncateToDouble()
          ? v.truncate().toString()
          : v.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _pickCategory() async {
    final categories = ref.read(categoriesProvider).valueOrNull ?? [];
    final result = await showDialog<({String? id, String name})>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Select Category',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceMuted,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.pie_chart_outline_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
                title: const Text(
                  'Overall',
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                ),
                subtitle: const Text(
                  'All spending',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
                selected: _categoryId == null,
                onTap: () => ctx.pop((id: null, name: 'Overall')),
              ),
              const Divider(height: 1, color: AppColors.border),
              ...categories.map((cat) {
                final color = hexToColor(cat.color);
                return ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(iconForName(cat.icon), size: 18, color: color),
                  ),
                  title: Text(
                    cat.name,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  selected: _categoryId == cat.id,
                  onTap: () =>
                      ctx.pop((id: cat.id, name: cat.name)),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() {
        _categoryId = result.id;
        _categoryLabel = result.name;
      });
    }
  }

  Future<void> _save() async {
    final limitStr = _limitController.text.trim();
    final limitRm = double.tryParse(limitStr);
    if (limitRm == null || limitRm <= 0) {
      setState(() => _error = 'Enter a valid amount greater than 0');
      return;
    }
    final limitCents = (limitRm * 100).round();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.existing != null) {
        await supabase
            .from('budgets')
            .update({
              'category_id': _categoryId,
              'limit_cents': limitCents,
              'period': _period,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', widget.existing!.id);
      } else {
        await supabase.from('budgets').insert({
          'user_id': supabase.auth.currentUser!.id,
          'category_id': _categoryId,
          'limit_cents': limitCents,
          'period': _period,
          'currency': 'MYR',
        });
      }
      widget.onSaved();
      if (mounted) context.pop();
    } catch (_) {
      setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pre-load categories so they're ready when user opens picker.
    ref.watch(categoriesProvider);
    final isEdit = widget.existing != null;

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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
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
              const SizedBox(height: AppSpacing.xl),
              Text(
                isEdit ? 'Edit Budget' : 'Add Budget',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Category
              const _Label('Category'),
              const SizedBox(height: AppSpacing.md),
              GestureDetector(
                onTap: _pickCategory,
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
                      Expanded(
                        child: Text(
                          _categoryLabel,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textTertiary,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // Period
              const _Label('Period'),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  for (final entry in const [
                    ('daily', 'Day'),
                    ('weekly', 'Week'),
                    ('monthly', 'Month'),
                    ('yearly', 'Year'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: entry.$1 != 'yearly' ? AppSpacing.sm : 0,
                        ),
                        child: GestureDetector(
                          onTap: () => setState(() => _period = entry.$1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _period == entry.$1
                                  ? AppColors.accent
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              border: Border.all(
                                color: _period == entry.$1
                                    ? AppColors.accent
                                    : AppColors.border,
                              ),
                            ),
                            child: Text(
                              entry.$2,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _period == entry.$1
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

              // Limit
              const _Label('Spending Limit (RM)'),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _limitController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [AmountInputFormatter()],
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. 1000',
                  hintStyle: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 14,
                  ),
                  prefixText: 'RM ',
                  prefixStyle: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
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

              SizedBox(
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
                          isEdit ? 'Update' : 'Save',
                          style: const TextStyle(
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

// ── Sheet label ───────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  const _Label(this.text);

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
