import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/services/receipt_upload_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../service_locator.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../auth/providers/states/auth_state.dart';
import '../../../expenses/presentation/widgets/edit_expense_sheet.dart';
import 'category_expenses_screen.dart';
import '../../../subscription/providers/subscription_provider.dart';
import '../../providers/home/home_provider.dart';
import '../../providers/home/home_state.dart';
import '../widgets/analytics_banner.dart';
import '../widgets/budget_grid.dart';
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
  DateTimeRange? _customRange;

  final GlobalKey _pinnedHeaderKey = GlobalKey();
  final GlobalKey _analyticsBannerKey = GlobalKey();
  double _compactOpacity = 0;

  RenderSliver? _keyToSliver(GlobalKey key) =>
      key.currentContext?.findAncestorRenderObjectOfType<RenderSliver>();

  bool _handleScrollNotification(ScrollNotification notification) {
    final headerSliver = _keyToSliver(_pinnedHeaderKey);
    final bannerSliver = _keyToSliver(_analyticsBannerKey);
    if (headerSliver != null &&
        bannerSliver != null &&
        bannerSliver.geometry != null) {
      final opacity =
          headerSliver.constraints.scrollOffset >
                  bannerSliver.geometry!.scrollExtent
              ? 1.0
              : 0.0;
      if (opacity != _compactOpacity) setState(() => _compactOpacity = opacity);
    }

    // Trigger next page when within 300 px of the bottom.
    if (notification is ScrollUpdateNotification) {
      final m = notification.metrics;
      if (m.pixels >= m.maxScrollExtent - 300) {
        ref.read(homeExpensesProvider(_filter).notifier).fetchMore();
      }
    }

    return false;
  }

  HomeFilter get _filter => HomeFilter(
        period: _selectedPeriod,
        customStart: _customRange?.start,
        customEnd: _customRange?.end,
      );

  Future<void> _onPeriodSelected(TimePeriod period) async {
    if (period == TimePeriod.custom) {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2026),
        lastDate: now,
        initialEntryMode: DatePickerEntryMode.calendarOnly,
        initialDateRange:
            _customRange ??
            DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
        builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: AppColors.accent),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: SizedBox(
                  width: double.infinity,
                  height: MediaQuery.sizeOf(context).height * 0.7,
                  child: child!,
                ),
              ),
            ),
          ),
        ),
        saveText: 'Apply',
      );
      if (range == null || !mounted) return;
      setState(() {
        _selectedPeriod = TimePeriod.custom;
        _customRange = range;
      });
    } else {
      setState(() {
        _selectedPeriod = period;
        _customRange = null;
      });
    }
  }

  Future<void> _deleteExpense(String id) async {
    final row = await supabase
        .from('expenses')
        .select('receipt_url')
        .eq('id', id)
        .maybeSingle();
    final receiptUrl = row?['receipt_url'] as String?;
    if (receiptUrl != null) {
      ReceiptUploadService.deleteByUrl(receiptUrl);
    }
    await supabase
        .from('expenses')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
    ref.read(homeExpensesProvider(_filter).notifier).removeExpense(id);
    ref.invalidate(homeAnalyticsProvider(_filter));
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

    final authUser = ref
        .watch(authProvider)
        .whenOrNull(authenticated: (u) => u);
    final userName = authUser?.username ?? '';
    final displayName = authUser?.displayName;
    final isPremium = ref.watch(isPremiumProvider);

    final analyticsAsync = ref.watch(homeAnalyticsProvider(_filter));
    final analyticsData = analyticsAsync.valueOrNull;

    final expensesAsync = ref.watch(homeExpensesProvider(_filter));
    final expensesState = expensesAsync.valueOrNull;

    final isLoading = analyticsAsync.isLoading || expensesAsync.isLoading;
    final hasError = analyticsAsync.hasError && analyticsData == null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () async {
              ref.invalidate(homeAnalyticsProvider(_filter));
              ref.invalidate(homeExpensesProvider(_filter));
              await Future.wait([
                ref.read(homeAnalyticsProvider(_filter).future),
                ref.read(homeExpensesProvider(_filter).future),
              ]);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
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
                            onPressed: () {
                              ref.invalidate(homeAnalyticsProvider(_filter));
                              ref.invalidate(homeExpensesProvider(_filter));
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  if (analyticsData != null)
                    SliverAppBar(
                      expandedHeight: 200,
                      collapsedHeight: 60,
                      backgroundColor: AppColors.background,
                      surfaceTintColor: Colors.transparent,
                      scrolledUnderElevation: 0,
                      title: IgnorePointer(
                        ignoring: _compactOpacity == 0,
                        child: AnimatedOpacity(
                          opacity: _compactOpacity,
                          duration: const Duration(milliseconds: 200),
                          child: AnalyticsBannerCompact(
                            key: _pinnedHeaderKey,
                            summary: analyticsData.analytics,
                          ),
                        ),
                      ),
                      flexibleSpace: FlexibleSpaceBar(
                        background: Column(
                          children: [
                            GreetingHeader(
                              userName: userName,
                              displayName: displayName,
                              isPremium: isPremium,
                              onBellTap: () => debugPrint('Bell tapped'),
                              onAvatarTap: () => context.push(contactsRoute),
                            ),
                            AnalyticsBanner(
                              key: _analyticsBannerKey,
                              summary: analyticsData.analytics,
                              onTap: () => context.push(analysisRoute),
                            ),
                          ],
                        ),
                        centerTitle: false,
                        titlePadding: EdgeInsets.zero,
                      ),
                      pinned: true,
                    ),

                  if (kDebugMode)
                    SliverToBoxAdapter(child: _DevPremiumToggle()),

                  SliverToBoxAdapter(
                    child: TimeFilterChips(
                      selected: _selectedPeriod,
                      onSelected: _onPeriodSelected,
                    ),
                  ),

                  if (analyticsData != null &&
                      _selectedPeriod != TimePeriod.custom)
                    SliverToBoxAdapter(
                      child: BudgetGrid(
                        budgets: analyticsData.budgets,
                        onAnalyticsTap: () =>
                            context.push(budgetAnalyticsRoute),
                        onBudgetTap: (budget) async {
                          await context.push(
                            categoryExpensesRoute,
                            extra: CategoryExpensesRouteArgs(
                              filter: _filter,
                              budget: budget,
                            ),
                          );
                          if (mounted) {
                            ref.invalidate(homeAnalyticsProvider(_filter));
                            ref.invalidate(homeExpensesProvider(_filter));
                          }
                        },
                      ),
                    ),

                  if (analyticsData != null)
                    SliverToBoxAdapter(
                      child: PeriodSummaryHeader(
                        title: _periodTitle,
                        totalCents: analyticsData.periodTotalCents,
                        filter: _filter,
                      ),
                    ),

                  if (expensesState != null)
                    SliverToBoxAdapter(
                      child: ExpenseListCard(
                        expenses: expensesState.items,
                        timePeriod: _selectedPeriod,
                        onTileTap: (e) {
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => EditExpenseSheet(
                              expenseId: e.id,
                              onSaved: () {
                                ref.invalidate(
                                    homeAnalyticsProvider(_filter));
                                ref.invalidate(homeExpensesProvider(_filter));
                              },
                            ),
                          );
                        },
                        onDelete: _deleteExpense,
                      ),
                    ),

                  // Load-more spinner — visible when scrolled to bottom and
                  // more pages exist.
                  if (expensesState?.hasMore == true)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    ),

                  if (analyticsData == null && analyticsAsync.isLoading)
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
      ),
    );
  }
}

class _DevPremiumToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final override = ref.watch(devPremiumOverrideProvider);

    final (label, color) = switch (override) {
      true => ('DEV: Force Premium', Colors.amber),
      false => ('DEV: Force Free', Colors.redAccent),
      _ => ('DEV: Real Subscription', Colors.grey),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTap: () {
          final next = switch (override) {
            null => false,
            false => true,
            _ => null,
          };
          ref.read(devPremiumOverrideProvider.notifier).state = next;
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
