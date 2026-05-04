import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../service_locator.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../../auth/providers/states/auth_state.dart';
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
    await supabase
        .from('expenses')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
    ref.invalidate(homeDataProvider(_filter));
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

    final homeAsync = ref.watch(homeDataProvider(_filter));
    final homeData = homeAsync.valueOrNull;
    final isLoading = homeAsync.isLoading;
    final hasError = homeAsync.hasError && homeData == null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: RefreshIndicator(
            color: AppColors.accent,
            onRefresh: () async {
              ref.invalidate(homeDataProvider(_filter));
              await ref.read(homeDataProvider(_filter).future);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
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
                                ref.invalidate(homeDataProvider(_filter)),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  if (homeData != null)
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
                            summary: homeData.analytics,
                          ),
                        ),
                      ),
                      flexibleSpace: FlexibleSpaceBar(
                        background: Column(
                          children: [
                            GreetingHeader(
                              userName: userName,
                              displayName: displayName,
                              onBellTap: () => debugPrint('Bell tapped'),
                              onAvatarTap: () => context.push(contactsRoute),
                            ),
                            AnalyticsBanner(
                              key: _analyticsBannerKey,
                              summary: homeData.analytics,
                              onTap: () => context.push(analysisRoute),
                            ),
                          ],
                        ),
                        centerTitle: false,
                        titlePadding: EdgeInsets.zero,
                      ),
                      pinned: true,
                    ),

                  if (homeData != null &&
                      _selectedPeriod != TimePeriod.custom)
                    SliverToBoxAdapter(
                      child: BudgetGrid(
                        budgets: homeData.budgets,
                        onManageTap: () async {
                          await context.push(budgetsRoute);
                          if (mounted) {
                            ref.invalidate(homeDataProvider(_filter));
                          }
                        },
                        onBudgetTap: (_) async {
                          await context.push(budgetsRoute);
                          if (mounted) {
                            ref.invalidate(homeDataProvider(_filter));
                          }
                        },
                      ),
                    ),

                  SliverToBoxAdapter(
                    child: TimeFilterChips(
                      selected: _selectedPeriod,
                      onSelected: _onPeriodSelected,
                    ),
                  ),

                  if (homeData != null)
                    SliverToBoxAdapter(
                      child: PeriodSummaryHeader(
                        title: _periodTitle,
                        totalCents: homeData.periodTotalCents,
                        filter: _filter,
                      ),
                    ),

                  if (homeData != null)
                    SliverToBoxAdapter(
                      child: ExpenseListCard(
                        expenses: homeData.expenses,
                        timePeriod: _selectedPeriod,
                        onTileTap: (e) =>
                            debugPrint('Expense tapped: ${e.title}'),
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
      ),
    );
  }
}
