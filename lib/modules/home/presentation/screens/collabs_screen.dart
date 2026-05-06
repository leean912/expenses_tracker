import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currencies.dart';
import '../../../../service_locator.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../auth/providers/states/auth_state.dart';
import '../../../collabs/data/models/collab_model.dart';
import '../../../collabs/providers/collabs_provider.dart';

enum _CollabFilter { all, ongoing, closed }

class CollabsScreen extends ConsumerStatefulWidget {
  const CollabsScreen({super.key});

  @override
  ConsumerState<CollabsScreen> createState() => _CollabsScreenState();
}

class _CollabsScreenState extends ConsumerState<CollabsScreen> {
  _CollabFilter _filter = _CollabFilter.all;

  @override
  Widget build(BuildContext context) {
    final collabsAsync = ref.watch(collabsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Collabs',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          _FilterMenuButton(
            current: _filter,
            onSelected: (f) => setState(() => _filter = f),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      floatingActionButton: _CreateButton(collabsAsync: collabsAsync),
      body: collabsAsync.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Failed to load collabs.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.invalidate(collabsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (collabs) {
          final List<CollabModel> visible;
          if (_filter == _CollabFilter.ongoing) {
            visible = collabs.where((c) => c.isActive).toList();
          } else if (_filter == _CollabFilter.closed) {
            visible = collabs.where((c) => c.isClosed).toList();
          } else {
            visible = collabs;
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(collabsProvider.future),
            color: AppColors.accent,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.xxl,
              ),
              children: [
                if (visible.isEmpty)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.65,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.group_work_outlined,
                              size: 28,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Text(
                            _filter == _CollabFilter.closed
                                ? 'No closed collabs.'
                                : _filter == _CollabFilter.ongoing
                                ? 'No ongoing collabs.'
                                : 'No collabs yet.',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (_filter != _CollabFilter.closed) ...[
                            const SizedBox(height: AppSpacing.sm),
                            const Text(
                              'Create one to share expenses\nwith friends on a trip or event.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else
                  ...visible.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _CollabTile(collab: c),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Filter menu button ─────────────────────────────────────────────────────────

class _FilterMenuButton extends StatelessWidget {
  const _FilterMenuButton({required this.current, required this.onSelected});

  final _CollabFilter current;
  final ValueChanged<_CollabFilter> onSelected;

  String get _label => switch (current) {
    _CollabFilter.all => 'All',
    _CollabFilter.ongoing => 'Ongoing',
    _CollabFilter.closed => 'Closed',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_CollabFilter>(
      onSelected: onSelected,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.border),
      ),
      offset: const Offset(0, 40),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: current != _CollabFilter.all
              ? AppColors.accent
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: current != _CollabFilter.all
                ? AppColors.accent
                : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: current != _CollabFilter.all
                    ? AppColors.accentText
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: current != _CollabFilter.all
                  ? AppColors.accentText
                  : AppColors.textTertiary,
            ),
          ],
        ),
      ),
      itemBuilder: (_) => [
        _menuItem(_CollabFilter.all, 'All', current),
        _menuItem(_CollabFilter.ongoing, 'Ongoing', current),
        _menuItem(_CollabFilter.closed, 'Closed', current),
      ],
    );
  }

  PopupMenuItem<_CollabFilter> _menuItem(
    _CollabFilter value,
    String label,
    _CollabFilter current,
  ) {
    final isSelected = value == current;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (isSelected)
            const Icon(
              Icons.check_rounded,
              size: 16,
              color: AppColors.textPrimary,
            ),
        ],
      ),
    );
  }
}

// ── Create button ──────────────────────────────────────────────────────────────

class _CreateButton extends ConsumerWidget {
  const _CreateButton({required this.collabsAsync});

  final AsyncValue<List<CollabModel>> collabsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton.extended(
      onPressed: () async {
        final authState = ref.read(authProvider);
        final homeCurrency =
            authState.whenOrNull(
              authenticated: (user) => user.defaultCurrency,
            ) ??
            'MYR';
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _CreateCollabSheet(homeCurrency: homeCurrency),
        );
      },
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.accentText,
      icon: const Icon(Icons.add_rounded),
      label: const Text(
        'Create Collab',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Collab tile ────────────────────────────────────────────────────────────────

class _CollabTile extends ConsumerWidget {
  const _CollabTile({required this.collab});

  final CollabModel collab;

  String _formatDate(DateTime d) => '${d.day} ${_monthAbbr(d.month)} ${d.year}';

  String _monthAbbr(int m) => const [
    '',
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
  ][m];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = supabase.auth.currentUser?.id;
    final isOwner = collab.ownerId == currentUserId;
    final activeMembers = collab.members.where((m) => m.isActive).length;

    return Dismissible(
      key: Key(collab.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(
              isOwner ? 'Delete collab?' : 'Leave collab?',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            content: Text(
              isOwner
                  ? '"${collab.name}" and all its data will be removed.'
                  : 'You will no longer see "${collab.name}".',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => context.pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: () => context.pop(true),
                child: Text(
                  isOwner ? 'Delete' : 'Leave',
                  style: const TextStyle(color: Color(0xFF993C1D)),
                ),
              ),
            ],
          ),
        );
        if (confirmed != true) return false;
        if (isOwner) {
          await ref.read(collabsProvider.notifier).deleteCollab(collab.id);
        } else {
          await ref.read(collabsProvider.notifier).leaveCollab(collab.id);
        }
        return true;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEB),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(
          isOwner ? Icons.delete_outline_rounded : Icons.logout_rounded,
          color: const Color(0xFF993C1D),
          size: 20,
        ),
      ),
      child: GestureDetector(
        onTap: () => context.push('$collabDetailRoute/${collab.id}'),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      collab.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: collab.isClosed
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (collab.isForeignCurrency) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        collab.currency,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: collab.isClosed
                          ? const Color(0xFFFFEBEB)
                          : const Color(0xFFE6F9F0),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      collab.isClosed ? 'Closed' : 'Ongoing',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: collab.isClosed
                            ? const Color(0xFF993C1D)
                            : const Color(0xFF1A7A4A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Icon(
                    Icons.people_outline_rounded,
                    size: 13,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$activeMembers member${activeMembers == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  if (collab.startDate != null) ...[
                    const SizedBox(width: AppSpacing.lg),
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 12,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      collab.endDate != null
                          ? '${_formatDate(collab.startDate!)} – ${_formatDate(collab.endDate!)}'
                          : 'From ${_formatDate(collab.startDate!)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Create collab sheet ────────────────────────────────────────────────────────

class _CreateCollabSheet extends ConsumerStatefulWidget {
  const _CreateCollabSheet({required this.homeCurrency});

  final String homeCurrency;

  @override
  ConsumerState<_CreateCollabSheet> createState() => _CreateCollabSheetState();
}

class _CreateCollabSheetState extends ConsumerState<_CreateCollabSheet> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _exchangeRateController = TextEditingController();
  final _budgetController = TextEditingController();

  late String _currency;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currency = widget.homeCurrency;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _exchangeRateController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  bool get _isForeign => _currency != widget.homeCurrency;

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  void _pickCurrency() {
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CurrencyPickerSheet(selected: _currency),
    ).then((picked) {
      if (picked != null && picked != _currency) {
        setState(() {
          _currency = picked;
          if (!_isForeign) _exchangeRateController.clear();
        });
      }
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a collab name.');
      return;
    }
    if (_isForeign) {
      final rateText = _exchangeRateController.text.trim();
      if (rateText.isEmpty || double.tryParse(rateText) == null) {
        setState(() => _error = 'Please enter a valid exchange rate.');
        return;
      }
    }
    if (_startDate != null &&
        _endDate != null &&
        _endDate!.isBefore(_startDate!)) {
      setState(() => _error = 'End date must be after start date.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    int? budgetCents;
    final budgetText = _budgetController.text.trim();
    if (budgetText.isNotEmpty) {
      final budgetAmount = double.tryParse(budgetText);
      if (budgetAmount != null) budgetCents = (budgetAmount * 100).round();
    }

    double? exchangeRate;
    if (_isForeign) {
      exchangeRate = double.tryParse(_exchangeRateController.text.trim());
    }

    final error = await ref
        .read(collabsProvider.notifier)
        .createCollab(
          name: name,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          startDate: _startDate,
          endDate: _endDate,
          currency: _currency,
          homeCurrency: widget.homeCurrency,
          exchangeRate: exchangeRate,
          budgetCents: budgetCents,
        );

    if (!mounted) return;
    if (error == null) {
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Collab created.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.textPrimary,
        ),
      );
    } else {
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  String _formatDate(DateTime d) => '${d.day} ${_monthAbbr(d.month)} ${d.year}';

  String _monthAbbr(int m) => const [
    '',
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
  ][m];

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
              const Text(
                'New Collab',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Name
              const _Label('Name'),
              const SizedBox(height: AppSpacing.md),
              _TextField(
                controller: _nameController,
                hint: 'e.g. Japan 2026, Chalet Weekend',
                capitalization: TextCapitalization.words,
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Description
              const _Label('Description (optional)'),
              const SizedBox(height: AppSpacing.md),
              _TextField(
                controller: _descriptionController,
                hint: "What's this collab about?",
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Dates
              const _Label('Dates (optional)'),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _DateButton(
                      label: _startDate != null
                          ? _formatDate(_startDate!)
                          : 'Start date',
                      onTap: _pickStartDate,
                      placeholder: _startDate == null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _DateButton(
                      label: _endDate != null
                          ? _formatDate(_endDate!)
                          : 'End date',
                      onTap: _pickEndDate,
                      placeholder: _endDate == null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Currency
              const _Label('Currency'),
              const SizedBox(height: AppSpacing.md),
              GestureDetector(
                onTap: _pickCurrency,
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
                          '$_currency — ${AppCurrency.nameFor(_currency)}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),

              // Exchange rate (shown only for foreign currency)
              if (_isForeign) ...[
                const SizedBox(height: AppSpacing.xxl),
                _Label(
                  'Exchange Rate (1 ${widget.homeCurrency} = ? $_currency)',
                ),
                const SizedBox(height: AppSpacing.md),
                _TextField(
                  controller: _exchangeRateController,
                  hint: 'e.g. 30',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                ),
              ],

              const SizedBox(height: AppSpacing.xxl),

              // Budget
              _Label('Budget in ${widget.homeCurrency} (optional)'),
              const SizedBox(height: AppSpacing.md),
              _TextField(
                controller: _budgetController,
                hint: 'e.g. 2000.00',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
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
                      : const Text(
                          'Create Collab',
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

// ── Currency picker sheet ──────────────────────────────────────────────────────

class _CurrencyPickerSheet extends StatelessWidget {
  const _CurrencyPickerSheet({required this.selected});

  final String selected;

  @override
  Widget build(BuildContext context) {
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
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              AppSpacing.xxl,
              AppSpacing.xxl,
              AppSpacing.lg,
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Select Currency',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => context.pop(),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: AppCurrency.all.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, index) {
                final currency = AppCurrency.all[index];
                final isSelected = currency.code == selected;
                return ListTile(
                  onTap: () => context.pop(currency.code),
                  title: Text(
                    '${currency.code} — ${currency.name}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: AppColors.textPrimary,
                        )
                      : null,
                  dense: true,
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

// ── Small shared widgets ───────────────────────────────────────────────────────

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

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.hint,
    this.capitalization = TextCapitalization.none,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String hint;
  final TextCapitalization capitalization;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textCapitalization: capitalization,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
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
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.onTap,
    required this.placeholder,
  });

  final String label;
  final VoidCallback onTap;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
              Icons.calendar_today_outlined,
              size: 14,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: placeholder
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
