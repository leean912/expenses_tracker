import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/upgrade_sheet.dart';
import '../../../subscription/providers/subscription_provider.dart';
import '../../providers/recurring_expenses_provider.dart';
import '../../providers/recurring_split_bills_provider.dart';
import '../widgets/recurring_expense_tile.dart';
import '../widgets/recurring_split_bill_tile.dart';

class RecurringListScreen extends ConsumerWidget {
  const RecurringListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
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
          title: const Text(
            'Recurring',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          bottom: const TabBar(
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textTertiary,
            indicatorColor: AppColors.accent,
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: [
              Tab(text: 'Expenses'),
              Tab(text: 'Split Bills'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ExpensesTab(),
            _SplitBillsTab(),
          ],
        ),
      ),
    );
  }
}

// ── Expenses tab ──────────────────────────────────────────────────────────────

class _ExpensesTab extends ConsumerWidget {
  const _ExpensesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recurringExpensesProvider);
    final isPremium = ref.watch(isPremiumProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _ErrorView(
        onRetry: () => ref.invalidate(recurringExpensesProvider),
      ),
      data: (items) => Stack(
        children: [
          items.isEmpty
              ? _EmptyView(
                  icon: Icons.repeat_rounded,
                  label: 'No recurring expenses',
                  hint: 'Tap + to set up a recurring expense.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 100),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return RecurringExpenseTile(
                      item: item,
                      onTap: () => context.push(
                        recurringExpenseFormRoute,
                        extra: item,
                      ),
                      onToggle: (v) => ref
                          .read(recurringExpensesProvider.notifier)
                          .toggle(item.id, isActive: v),
                      onDelete: () => ref
                          .read(recurringExpensesProvider.notifier)
                          .delete(item.id),
                    );
                  },
                ),
          Positioned(
            right: AppSpacing.xl,
            bottom: AppSpacing.xl,
            child: FloatingActionButton.extended(
              heroTag: 'add_recurring_expense',
              onPressed: () {
                if (!isPremium && items.length >= 5) {
                  UpgradeSheet.show(
                    context,
                    title: 'Upgrade for unlimited recurring expenses',
                    description:
                        'Free plan allows up to 5 recurring expenses. Go Premium for unlimited.',
                  );
                  return;
                }
                context.push(recurringExpenseFormRoute);
              },
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.accentText,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add Recurring',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Split Bills tab ───────────────────────────────────────────────────────────

class _SplitBillsTab extends ConsumerWidget {
  const _SplitBillsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recurringSplitBillsProvider);
    final isPremium = ref.watch(isPremiumProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _ErrorView(
        onRetry: () => ref.invalidate(recurringSplitBillsProvider),
      ),
      data: (items) => Stack(
        children: [
          items.isEmpty
              ? _EmptyView(
                  icon: Icons.call_split_rounded,
                  label: 'No recurring split bills',
                  hint: 'Tap + to automate a recurring split.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 100),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return RecurringSplitBillTile(
                      item: item,
                      onTap: () => context.push(
                        recurringSplitBillFormRoute,
                        extra: item,
                      ),
                      onToggle: (v) => ref
                          .read(recurringSplitBillsProvider.notifier)
                          .toggle(item.id, isActive: v),
                      onDelete: () => ref
                          .read(recurringSplitBillsProvider.notifier)
                          .delete(item.id),
                    );
                  },
                ),
          Positioned(
            right: AppSpacing.xl,
            bottom: AppSpacing.xl,
            child: FloatingActionButton.extended(
              heroTag: 'add_recurring_split',
              onPressed: () {
                if (!isPremium && items.isNotEmpty) {
                  UpgradeSheet.show(
                    context,
                    title: 'Upgrade for unlimited recurring splits',
                    description:
                        'Free plan allows 1 recurring split bill. Go Premium for unlimited.',
                  );
                  return;
                }
                context.push(recurringSplitBillFormRoute);
              },
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.accentText,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add Recurring',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.icon,
    required this.label,
    required this.hint,
  });

  final IconData icon;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Failed to load.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
