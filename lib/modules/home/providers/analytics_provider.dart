import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import 'home/home_state.dart';

/// Fetches [AnalyticsSummary] for the given [TimePeriod].
///
/// Makes two Supabase queries:
///   1. Current period — all expense rows with category info (summed in Dart).
///   2. Previous period — all expense rows (total only, for change % calculation).
final analyticsSummaryProvider =
    FutureProvider.family<AnalyticsSummary, TimePeriod>((ref, period) async {
      final userId = supabase.auth.currentUser!.id;
      final (start, end) = period.toDateRange();
      final (prevStart, prevEnd) = period.toPreviousDateRange();

      final results = await Future.wait([
        supabase
            .from('expenses')
            .select('home_amount_cents, actual_amount_cents, category_id, categories(name)')
            .eq('user_id', userId)
            .eq('type', 'expense')
            .gte('expense_date', start)
            .lte('expense_date', end)
            .isFilter('deleted_at', null),
        supabase
            .from('expenses')
            .select('home_amount_cents, actual_amount_cents')
            .eq('user_id', userId)
            .eq('type', 'expense')
            .gte('expense_date', prevStart)
            .lte('expense_date', prevEnd)
            .isFilter('deleted_at', null),
      ]);

      final rows = results[0] as List<dynamic>;
      final prevRows = results[1] as List<dynamic>;

      int totalCents = 0;
      int actualTotalCents = 0;
      final Map<String, ({int cents, String name})> byCategory = {};

      for (final r in rows) {
        final row = r as Map<String, dynamic>;
        final home = row['home_amount_cents'] as int? ?? 0;
        final actual = row['actual_amount_cents'] as int? ?? home;
        totalCents += home;
        actualTotalCents += actual;

        final catId = row['category_id'] as String? ?? '';
        final catName =
            (row['categories'] as Map<String, dynamic>?)?['name'] as String? ??
            catId;
        final existing = byCategory[catId];
        byCategory[catId] = (
          cents: (existing?.cents ?? 0) + home,
          name: catName,
        );
      }

      int prevTotalCents = 0;
      int prevActualCents = 0;
      for (final r in prevRows) {
        final row = r as Map<String, dynamic>;
        final home = row['home_amount_cents'] as int? ?? 0;
        final actual = row['actual_amount_cents'] as int? ?? home;
        prevTotalCents += home;
        prevActualCents += actual;
      }

      final topCategory =
          byCategory.entries
              .fold<MapEntry<String, ({int cents, String name})>?>(
                null,
                (best, e) =>
                    best == null || e.value.cents > best.value.cents ? e : best,
              )
              ?.value
              .name ??
          '—';

      final periodDays =
          DateTime.parse(end).difference(DateTime.parse(start)).inDays + 1;
      final avgPerDayCents = periodDays > 0 ? totalCents ~/ periodDays : 0;
      final actualAvgPerDayCents = periodDays > 0 ? actualTotalCents ~/ periodDays : 0;

      final changeVsLast = totalCents - prevTotalCents;
      final actualChangeVsLast = actualTotalCents - prevActualCents;
      // final changePercent = prevTotalCents == 0
      //     ? 0.0
      //     : (changeVsLast / prevTotalCents) * 100.0;

      return AnalyticsSummary(
        totalSpentCents: totalCents,
        actualSpentCents: actualTotalCents,
        // changePercent: changePercent,
        avgPerDayCents: avgPerDayCents,
        actualAvgPerDayCents: actualAvgPerDayCents,
        topCategory: topCategory,
        changeVsLastMonthCents: changeVsLast,
        actualChangeVsLastMonthCents: actualChangeVsLast,
      );
    });
