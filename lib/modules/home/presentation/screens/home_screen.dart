import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../service_locator.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../auth/providers/states/auth_state.dart';
import '../../../expenses/presentation/widgets/add_expense_sheet.dart';
import '../../providers/home/home_provider.dart';
import '../../providers/home/home_state.dart';
import '../widgets/analytics_banner.dart';
import '../widgets/budget_grid.dart';
import '../widgets/custom_bottom_nav.dart';
import '../widgets/expense_tile.dart';
import '../widgets/greeting_header.dart';
import '../widgets/period_summary_header.dart';
import '../widgets/time_filter_chips.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  TimePeriod _selectedPeriod = TimePeriod.today;
  int _navIndex = 0;

  Future<void> _deleteExpense(String id) async {
    await supabase
        .from('expenses')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
    ref.invalidate(homeDataProvider(_selectedPeriod));
  }

  void _showAddExpenseSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddExpenseSheet(),
    );
  }

  String get _periodTitle {
    switch (_selectedPeriod) {
      case TimePeriod.today:
        return "Today's expenses";
      case TimePeriod.week:
        return "This week's expenses";
      case TimePeriod.month:
        return "This month's expenses";
      case TimePeriod.year:
        return "This year's expenses";
      case TimePeriod.custom:
        return "Custom range";
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (prev, next) {
      if (prev != next) {
        next.whenOrNull(
          unauthenticated: () => context.pushReplacement(loginRoute),
        );
      }
    });

    final userName =
        ref
            .watch(authProvider)
            .whenOrNull(authenticated: (user) => user.username) ??
        '';

    final homeAsync = ref.watch(homeDataProvider(_selectedPeriod));
    final homeData = homeAsync.valueOrNull;
    final isLoading = homeAsync.isLoading;
    final hasError = homeAsync.hasError && homeData == null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.accent,
          onRefresh: () async {
            ref.invalidate(homeDataProvider(_selectedPeriod));
            await ref.read(homeDataProvider(_selectedPeriod).future);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
            SliverToBoxAdapter(
              child: GreetingHeader(
                userName: userName,
                onBellTap: () => debugPrint('Bell tapped'),
                onAvatarTap: () => context.push(contactsRoute),
              ),
            ),

            // Thin loading bar shown while refetching (period switch).
            if (isLoading)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: AppColors.surfaceMuted,
                  color: AppColors.accent,
                ),
              ),

            if (hasError)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Failed to load data.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(homeDataProvider(_selectedPeriod)),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              if (homeData != null)
                SliverToBoxAdapter(
                  child: AnalyticsBanner(
                    summary: homeData.analytics,
                    onTap: () => debugPrint('Analytics banner tapped'),
                  ),
                ),

              if (homeData != null)
                SliverToBoxAdapter(
                  child: BudgetGrid(
                    budgets: homeData.budgets,
                    onManageTap: () => debugPrint('Manage budgets tapped'),
                    onBudgetTap: (b) => debugPrint('Budget tapped: ${b.label}'),
                    onAddTap: () => debugPrint('Add budget tapped'),
                  ),
                ),

              SliverToBoxAdapter(
                child: TimeFilterChips(
                  selected: _selectedPeriod,
                  onSelected: (period) =>
                      setState(() => _selectedPeriod = period),
                ),
              ),

              if (homeData != null)
                SliverToBoxAdapter(
                  child: PeriodSummaryHeader(
                    title: _periodTitle,
                    totalCents: homeData.periodTotalCents,
                  ),
                ),

              if (homeData != null)
                SliverToBoxAdapter(
                  child: ExpenseListCard(
                    expenses: homeData.expenses,
                    timePeriod: _selectedPeriod,
                    onTileTap: (e) => debugPrint('Expense tapped: ${e.title}'),
                    onDelete: _deleteExpense,
                  ),
                ),

              if (homeData == null && isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: CustomBottomNav(
          currentIndex: _navIndex,
          onTabTap: (index) {
            if (index == 1) {
              context.push(splitBillsRoute);
              return;
            }
            setState(() => _navIndex = index);
          },
          onAddTap: _showAddExpenseSheet,
        ),
      ),
    );
  }
}
