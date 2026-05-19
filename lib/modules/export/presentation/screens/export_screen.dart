import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/upgrade_sheet.dart';
import '../../../expenses/data/models/account_model.dart';
import '../../../expenses/data/models/category_model.dart';
import '../../../expenses/providers/accounts_provider.dart';
import '../../../expenses/providers/categories_provider.dart';
import '../../../expenses/utils/expense_ui_helpers.dart';
import '../../../subscription/providers/subscription_provider.dart';
import '../../providers/export_provider.dart';
import '../../../tags/data/models/tag_model.dart';
import '../../../tags/providers/tags_provider.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  bool _exporting = false;

  Future<void> _export(
    List<CategoryModel> cats,
    List<AccountModel> accs,
  ) async {
    setState(() => _exporting = true);
    try {
      await ref.read(exportPdfProvider.notifier).export(cats, accs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(exportPdfProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final tagsAsync = ref.watch(tagsProvider);
    final isPremium = ref.watch(isPremiumProvider);

    final isPdf = filter.exportFormat == ExportFormat.pdf;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'Export',
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
          actions: [
            PopupMenuButton<ExportFormat>(
              initialValue: filter.exportFormat,
              onSelected: (f) =>
                  ref.read(exportPdfProvider.notifier).setExportFormat(f),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: ExportFormat.pdf,
                  child: Row(
                    children: [
                      Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 18,
                        color: filter.exportFormat == ExportFormat.pdf
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'PDF',
                        style: TextStyle(
                          fontWeight: filter.exportFormat == ExportFormat.pdf
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: filter.exportFormat == ExportFormat.pdf
                              ? AppColors.accent
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: ExportFormat.excel,
                  child: Row(
                    children: [
                      Icon(
                        Icons.table_chart_rounded,
                        size: 18,
                        color: filter.exportFormat == ExportFormat.excel
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Excel (.xlsx)',
                        style: TextStyle(
                          fontWeight: filter.exportFormat == ExportFormat.excel
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: filter.exportFormat == ExportFormat.excel
                              ? AppColors.accent
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPdf
                          ? Icons.picture_as_pdf_rounded
                          : Icons.table_chart_rounded,
                      size: 16,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isPdf ? 'PDF' : 'Excel',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_drop_down,
                      size: 18,
                      color: AppColors.accent,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            // ── Date range ──────────────────────────────────────────────────
            _SectionLabel('Date Range'),
            const SizedBox(height: AppSpacing.md),
            _MonthRangePicker(
              start: filter.startDate,
              end: filter.endDate,
              onChanged: (s, e) =>
                  ref.read(exportPdfProvider.notifier).setDateRange(s, e),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // ── Transaction type ────────────────────────────────────────────
            _SectionLabel('Transaction Type'),
            const SizedBox(height: AppSpacing.md),
            _SegmentedPicker<ExportTransactionType>(
              options: const [
                (ExportTransactionType.all, 'All'),
                (ExportTransactionType.expensesOnly, 'Expenses'),
                (ExportTransactionType.incomeOnly, 'Settlements'),
              ],
              selected: filter.transactionType,
              onSelect: (v) =>
                  ref.read(exportPdfProvider.notifier).setTransactionType(v),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // ── Categories ──────────────────────────────────────────────────
            _SectionLabel('Categories'),
            const SizedBox(height: AppSpacing.md),
            categoriesAsync.when(
              loading: () => const _LoadingChips(),
              error: (_, _) => const _ErrorChips('categories'),
              data: (cats) => _CategoryPicker(
                categories: cats,
                selectedIds: filter.selectedCategoryIds,
                onToggle: (id) =>
                    ref.read(exportPdfProvider.notifier).toggleCategory(id),
                onSelectAll: () =>
                    ref.read(exportPdfProvider.notifier).selectAllCategories(),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // ── Accounts ────────────────────────────────────────────────────
            _SectionLabel('Accounts'),
            const SizedBox(height: AppSpacing.md),
            accountsAsync.when(
              loading: () => const _LoadingChips(),
              error: (_, _) => const _ErrorChips('accounts'),
              data: (accs) => _AccountPicker(
                accounts: accs,
                selectedIds: filter.selectedAccountIds,
                onToggle: (id) =>
                    ref.read(exportPdfProvider.notifier).toggleAccount(id),
                onSelectAll: () =>
                    ref.read(exportPdfProvider.notifier).selectAllAccounts(),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // ── Tags ─────────────────────────────────────────────────────────
            _SectionLabel('Tags'),
            const SizedBox(height: AppSpacing.md),
            tagsAsync.when(
              loading: () => const _LoadingChips(),
              error: (_, _) => const _ErrorChips('tags'),
              data: (tags) => tags.isEmpty
                  ? const Text(
                      'No tags yet. Create tags in Settings.',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textTertiary),
                    )
                  : _TagPicker(
                      tags: tags,
                      selectedIds: filter.selectedTagIds,
                      onToggle: (id) =>
                          ref.read(exportPdfProvider.notifier).toggleTag(id),
                      onSelectAll: () =>
                          ref.read(exportPdfProvider.notifier).selectAllTags(),
                    ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // ── Sort order ──────────────────────────────────────────────────
            _SectionLabel('Sort By'),
            const SizedBox(height: AppSpacing.md),
            _SegmentedPicker<ExportSortOrder>(
              options: const [
                (ExportSortOrder.dateDesc, 'Newest First'),
                (ExportSortOrder.dateAsc, 'Oldest First'),
                (ExportSortOrder.amountDesc, 'Highest Amount'),
              ],
              selected: filter.sortOrder,
              onSelect: (v) =>
                  ref.read(exportPdfProvider.notifier).setSortOrder(v),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // ── Toggles ─────────────────────────────────────────────────────
            _SectionLabel('Include'),
            const SizedBox(height: AppSpacing.md),
            _ToggleTile(
              label: 'Split bill expenses',
              value: filter.includeSplitBill,
              onChanged: (v) =>
                  ref.read(exportPdfProvider.notifier).setIncludeSplitBill(v),
            ),
            const Divider(
              height: 1,
              indent: AppSpacing.xl,
              color: AppColors.border,
            ),
            _ToggleTile(
              label: 'Recurring expenses',
              value: filter.includeRecurring,
              onChanged: (v) =>
                  ref.read(exportPdfProvider.notifier).setIncludeRecurring(v),
            ),
            const Divider(
              height: 1,
              indent: AppSpacing.xl,
              color: AppColors.border,
            ),
            if (isPdf)
              _ToggleTile(
                label: 'Receipts (images embedded in PDF)',
                value: filter.includeReceipts,
                onChanged: (v) =>
                    ref.read(exportPdfProvider.notifier).setIncludeReceipts(v),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Receipt images are only available in PDF export.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xxl),

            // ── Export button ───────────────────────────────────────────────
            categoriesAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (cats) => accountsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (accs) => SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      if (!isPremium) {
                        UpgradeSheet.show(
                          context,
                          title: 'Export PDF is a Pro feature',
                          description:
                              'Upgrade to Spendz Pro to export your transactions as a PDF report.',
                        );
                        return;
                      }

                      _exporting ? null : _export(cats, accs);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.accentText,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                    ),
                    icon: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accentText,
                            ),
                          )
                        : Icon(
                            isPdf
                                ? Icons.picture_as_pdf_rounded
                                : Icons.table_chart_rounded,
                            size: 18,
                          ),
                    label: Text(
                      _exporting
                          ? 'Generating…'
                          : isPdf
                          ? 'Export PDF'
                          : 'Export Excel',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }

}

// ── Month range picker ────────────────────────────────────────────────────────

class _MonthRangePicker extends StatefulWidget {
  const _MonthRangePicker({
    required this.start,
    required this.end,
    required this.onChanged,
  });

  final DateTime start;
  final DateTime end;
  final void Function(DateTime, DateTime) onChanged;

  @override
  State<_MonthRangePicker> createState() => _MonthRangePickerState();
}

class _MonthRangePickerState extends State<_MonthRangePicker> {
  late int _year;
  int? _anchorMonth;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _year = widget.start.year;
  }

  DateTime _lastDayOfMonth(int year, int month) {
    final now = DateTime.now();
    if (year == now.year && month == now.month) return now;
    return DateTime(year, month + 1, 0);
  }

  void _changeYear(int delta) {
    final now = DateTime.now();
    final newYear = _year + delta;
    if (newYear > now.year || newYear < 2020) return;
    setState(() {
      _year = newYear;
      _anchorMonth = null;
    });
    final newStart = DateTime(newYear, 1, 1);
    final newEnd = newYear == now.year ? now : DateTime(newYear, 12, 31);
    widget.onChanged(newStart, newEnd);
  }

  void _onMonthTap(int month) {
    final now = DateTime.now();
    if (_year == now.year && month > now.month) return;

    if (_anchorMonth == null) {
      setState(() => _anchorMonth = month);
      widget.onChanged(
        DateTime(_year, month, 1),
        _lastDayOfMonth(_year, month),
      );
    } else {
      final anchor = _anchorMonth!;
      setState(() => _anchorMonth = null);
      if (month < anchor) {
        widget.onChanged(
          DateTime(_year, month, 1),
          _lastDayOfMonth(_year, month),
        );
      } else {
        widget.onChanged(
          DateTime(_year, anchor, 1),
          _lastDayOfMonth(_year, month),
        );
      }
    }
  }

  bool _isFuture(int month) {
    final now = DateTime.now();
    return _year > now.year || (_year == now.year && month > now.month);
  }

  bool _isInRange(int month) {
    if (widget.start.year != _year || widget.end.year != _year) return false;
    return month >= widget.start.month && month <= widget.end.month;
  }

  bool _isEdge(int month) =>
      (widget.start.year == _year && widget.start.month == month) ||
      (widget.end.year == _year && widget.end.month == month);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final rangeLabel = () {
      if (_anchorMonth != null) return 'Select end month…';
      final s = widget.start;
      final e = widget.end;
      final months = (e.year - s.year) * 12 + (e.month - s.month) + 1;
      final label = months == 1
          ? DateFormat('MMM yyyy').format(s)
          : '${DateFormat('MMM').format(s)} – ${DateFormat('MMM yyyy').format(e)}';
      return months == 1 ? label : '$label  ($months months)';
    }();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Year selector
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 22),
              color: _year > 2020
                  ? AppColors.textPrimary
                  : AppColors.textTertiary,
              onPressed: _year > 2020 ? () => _changeYear(-1) : null,
            ),
            Text(
              '$_year',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 22),
              color: _year < now.year
                  ? AppColors.textPrimary
                  : AppColors.textTertiary,
              onPressed: _year < now.year ? () => _changeYear(1) : null,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // Month grid
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          childAspectRatio: 2.2,
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          children: List.generate(12, (i) {
            final month = i + 1;
            final future = _isFuture(month);
            final edge = _isEdge(month);
            final inRange = _isInRange(month);
            final isAnchor = _anchorMonth == month;

            final Color bg;
            final Color fg;
            if (future) {
              bg = Colors.transparent;
              fg = AppColors.textTertiary.withValues(alpha: 0.35);
            } else if (edge || isAnchor) {
              bg = AppColors.accent;
              fg = AppColors.accentText;
            } else if (inRange) {
              bg = AppColors.accent.withValues(alpha: 0.12);
              fg = AppColors.textPrimary;
            } else {
              bg = AppColors.surface;
              fg = AppColors.textPrimary;
            }

            return GestureDetector(
              onTap: future ? null : () => _onMonthTap(month),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: (edge || isAnchor)
                        ? AppColors.accent
                        : AppColors.border,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _months[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: (edge || inRange || isAnchor)
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: fg,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        // Range label
        Text(
          rangeLabel,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: _anchorMonth != null
                ? AppColors.accent
                : AppColors.textSecondary,
            fontWeight: _anchorMonth != null
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

// ── Segmented picker ──────────────────────────────────────────────────────────

class _SegmentedPicker<T> extends StatelessWidget {
  const _SegmentedPicker({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<(T, String)> options;
  final T selected;
  final void Function(T) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: options.map((opt) {
          final (value, label) = opt;
          final isSelected = value == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Category picker ───────────────────────────────────────────────────────────

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.categories,
    required this.selectedIds,
    required this.onToggle,
    required this.onSelectAll,
  });

  final List<CategoryModel> categories;
  final Set<String>? selectedIds;
  final void Function(String) onToggle;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    final isAll = selectedIds == null;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        _Chip(label: 'All', selected: isAll, onTap: onSelectAll),
        ...categories.map((cat) {
          final isSelected = !isAll && selectedIds!.contains(cat.id);
          final color = hexToColor(cat.color);
          return _Chip(
            label: cat.name,
            selected: isSelected,
            color: isSelected ? color : null,
            onTap: () => onToggle(cat.id),
          );
        }),
      ],
    );
  }
}

// ── Account picker ────────────────────────────────────────────────────────────

class _AccountPicker extends StatelessWidget {
  const _AccountPicker({
    required this.accounts,
    required this.selectedIds,
    required this.onToggle,
    required this.onSelectAll,
  });

  final List<AccountModel> accounts;
  final Set<String>? selectedIds;
  final void Function(String) onToggle;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    final isAll = selectedIds == null;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        _Chip(label: 'All', selected: isAll, onTap: onSelectAll),
        ...accounts.map((acc) {
          final isSelected = !isAll && selectedIds!.contains(acc.id);
          final color = hexToColor(acc.color);
          return _Chip(
            label: acc.name,
            selected: isSelected,
            color: isSelected ? color : null,
            onTap: () => onToggle(acc.id),
          );
        }),
      ],
    );
  }
}

// ── Tag picker ────────────────────────────────────────────────────────────────

class _TagPicker extends StatelessWidget {
  const _TagPicker({
    required this.tags,
    required this.selectedIds,
    required this.onToggle,
    required this.onSelectAll,
  });

  final List<TagModel> tags;
  final Set<String>? selectedIds;
  final void Function(String) onToggle;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    final isAll = selectedIds == null;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        _Chip(label: 'All', selected: isAll, onTap: onSelectAll),
        ...tags.map((tag) {
          final isSelected = !isAll && selectedIds!.contains(tag.id);
          final color = hexToColor(tag.color);
          return _Chip(
            label: tag.name,
            selected: isSelected,
            color: isSelected ? color : null,
            onTap: () => onToggle(tag.id),
          );
        }),
      ],
    );
  }
}

// ── Chip ──────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? (color?.withValues(alpha: 0.15) ??
              AppColors.accent.withValues(alpha: 0.1))
        : AppColors.surface;
    final fg = selected
        ? (color ?? AppColors.textPrimary)
        : AppColors.textSecondary;
    final border = selected
        ? (color ?? AppColors.textPrimary)
        : AppColors.border;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: fg,
          ),
        ),
      ),
    );
  }
}

// ── Toggle tile ───────────────────────────────────────────────────────────────

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

// ── Loading / error states ────────────────────────────────────────────────────

class _LoadingChips extends StatelessWidget {
  const _LoadingChips();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 32,
    child: Center(child: CircularProgressIndicator()),
  );
}

class _ErrorChips extends StatelessWidget {
  const _ErrorChips(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
    'Failed to load $label',
    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
  );
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.textTertiary,
      letterSpacing: 0.8,
    ),
  );
}
