import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import '../../analysis/providers/analysis_state.dart';

class CollabAnalysisFilter {
  const CollabAnalysisFilter({
    required this.collabId,
    required this.defaultStart,
    required this.defaultEnd,
    this.customStart,
    this.customEnd,
  });

  final String collabId;
  final DateTime defaultStart;
  final DateTime defaultEnd;
  final DateTime? customStart;
  final DateTime? customEnd;

  DateTime get effectiveStart => customStart ?? defaultStart;
  DateTime get effectiveEnd => customEnd ?? defaultEnd;

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String get startIso => _iso(effectiveStart);
  String get endIso => _iso(effectiveEnd);

  @override
  bool operator ==(Object other) =>
      other is CollabAnalysisFilter &&
      other.collabId == collabId &&
      other.defaultStart == defaultStart &&
      other.defaultEnd == defaultEnd &&
      other.customStart == customStart &&
      other.customEnd == customEnd;

  @override
  int get hashCode => Object.hash(
        collabId,
        defaultStart,
        defaultEnd,
        customStart,
        customEnd,
      );
}

class MemberPeriodSeries {
  const MemberPeriodSeries({
    required this.userId,
    required this.displayName,
    required this.color,
    required this.spendCentsByBucket,
  });

  final String userId;
  final String displayName;
  final Color color;
  final List<int> spendCentsByBucket;
}

class CollabAnalysisData {
  const CollabAnalysisData({
    required this.selfCategoryBreakdown,
    required this.selfAccountBreakdown,
    required this.totalSpentCents,
    required this.totalIncomeCents,
    required this.memberPeriodSeries,
    required this.bucketDates,
    required this.currentUserId,
  });

  final List<CategorySpend> selfCategoryBreakdown;
  final List<CategorySpend> selfAccountBreakdown;
  final int totalSpentCents;
  final int totalIncomeCents;
  final List<MemberPeriodSeries> memberPeriodSeries;
  final List<DateTime> bucketDates;
  final String currentUserId;
}

final collabAnalysisProvider =
    FutureProvider.family<CollabAnalysisData, CollabAnalysisFilter>((
  ref,
  filter,
) async {
  final rows = await supabase
      .from('expenses')
      .select(
        'home_amount_cents, type, expense_date, '
        'category_id, account_id, user_id, '
        'category:categories(name, color), '
        'account:accounts(name), '
        'owner:profiles!user_id(display_name)',
      )
      .eq('collab_id', filter.collabId)
      .gte('expense_date', filter.startIso)
      .lte('expense_date', filter.endIso)
      .isFilter('deleted_at', null)
      .isFilter('archived_at', null)
      .order('expense_date', ascending: true) as List<dynamic>;

  final currentUserId = supabase.auth.currentUser?.id ?? '';
  final startDate = filter.effectiveStart;
  final endDate = filter.effectiveEnd;

  int totalSpentCents = 0;
  int totalIncomeCents = 0;

  final Map<String, ({int cents, String name, String? colorHex})> selfCatMap = {};
  final Map<String, ({int cents, String name})> selfAccountMap = {};
  final Map<String, String> memberNames = {};
  final Map<String, List<dynamic>> memberRowsMap = {};

  for (final r in rows) {
    final row = r as Map<String, dynamic>;
    final homeCents = row['home_amount_cents'] as int? ?? 0;
    final isIncome = row['type'] == 'income';
    final userId = row['user_id'] as String? ?? 'unknown';
    final ownerData = row['owner'] as Map<String, dynamic>?;
    final displayName = ownerData?['display_name'] as String? ?? 'Unknown';

    memberNames[userId] = displayName;
    memberRowsMap.putIfAbsent(userId, () => []).add(r);

    if (isIncome) {
      totalIncomeCents += homeCents;
    } else {
      totalSpentCents += homeCents;

      if (userId == currentUserId) {
        final catId = row['category_id'] as String? ?? 'uncategorized';
        final catData = row['category'] as Map<String, dynamic>?;
        final catName = catData?['name'] as String? ?? 'Other';
        final colorHex = catData?['color'] as String?;
        final accountId = row['account_id'] as String? ?? 'none';
        final accountData = row['account'] as Map<String, dynamic>?;
        final accountName = accountData?['name'] as String? ?? 'No Account';

        final existingCat = selfCatMap[catId];
        selfCatMap[catId] = (
          cents: (existingCat?.cents ?? 0) + homeCents,
          name: catName,
          colorHex: colorHex ?? existingCat?.colorHex,
        );

        final existingAcc = selfAccountMap[accountId];
        selfAccountMap[accountId] = (
          cents: (existingAcc?.cents ?? 0) + homeCents,
          name: accountName,
        );
      }
    }
  }

  // Self category breakdown
  final selfCatTotal = selfCatMap.values.fold(0, (s, e) => s + e.cents);
  final selfCategoryBreakdown = selfCatMap.entries
      .where((e) => e.value.cents > 0)
      .map((e) {
        final color = _hexToColor(e.value.colorHex) ?? const Color(0xFF888780);
        return CategorySpend(
          categoryId: e.key,
          categoryName: e.value.name,
          color: color,
          totalCents: e.value.cents,
          percentage: selfCatTotal <= 0 ? 0 : e.value.cents / selfCatTotal * 100,
        );
      })
      .toList()
    ..sort((a, b) => b.totalCents.compareTo(a.totalCents));

  // Self account breakdown
  final sortedSelfAccounts = selfAccountMap.entries
      .where((e) => e.value.cents > 0)
      .toList()
    ..sort((a, b) => b.value.cents.compareTo(a.value.cents));
  final selfAccountTotal = sortedSelfAccounts.fold(0, (s, e) => s + e.value.cents);
  final selfAccountBreakdown = sortedSelfAccounts.indexed.map((entry) {
    final (i, e) = entry;
    return CategorySpend(
      categoryId: e.key,
      categoryName: e.value.name,
      color: _accountPalette[i % _accountPalette.length],
      totalCents: e.value.cents,
      percentage: selfAccountTotal <= 0 ? 0 : e.value.cents / selfAccountTotal * 100,
    );
  }).toList();

  // Always daily buckets for the bar chart
  final dayCount = endDate.difference(startDate).inDays + 1;
  final bucketDates = List.generate(
    dayCount > 0 ? dayCount : 0,
    (i) => startDate.add(Duration(days: i)),
  );

  // Per-member total spend (for ordering and filtering)
  final memberTotalSpend = <String, int>{};
  for (final entry in memberRowsMap.entries) {
    final userRows = entry.value;
    final total = userRows.fold(0, (sum, r) {
      final row = r as Map<String, dynamic>;
      return row['type'] != 'income'
          ? sum + (row['home_amount_cents'] as int? ?? 0)
          : sum;
    });
    memberTotalSpend[entry.key] = total;
  }

  final sortedMemberEntries = memberTotalSpend.entries
      .where((e) => e.value > 0)
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final memberPeriodSeries = sortedMemberEntries.indexed.map((entry) {
    final (colorIdx, memberEntry) = entry;
    final userId = memberEntry.key;
    final userRows = memberRowsMap[userId] ?? [];
    final memberBuckets = dayCount > 0
        ? _bucketByDay(userRows, startDate, dayCount)
        : <PeriodBucket>[];
    return MemberPeriodSeries(
      userId: userId,
      displayName: memberNames[userId] ?? 'Unknown',
      color: _memberPalette[colorIdx % _memberPalette.length],
      spendCentsByBucket: memberBuckets.map((b) => b.spendCents).toList(),
    );
  }).toList();

  return CollabAnalysisData(
    selfCategoryBreakdown: selfCategoryBreakdown,
    selfAccountBreakdown: selfAccountBreakdown,
    totalSpentCents: totalSpentCents,
    totalIncomeCents: totalIncomeCents,
    memberPeriodSeries: memberPeriodSeries,
    bucketDates: bucketDates,
    currentUserId: currentUserId,
  );
});

// ── Period bucket builders ────────────────────────────────────────────────────

List<PeriodBucket> _bucketByDay(
  List<dynamic> rows,
  DateTime startDate,
  int count,
) {
  const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final spendBuckets = List.filled(count, 0);
  final incomeBuckets = List.filled(count, 0);

  for (final r in rows) {
    final row = r as Map<String, dynamic>;
    final date = DateTime.parse(row['expense_date'] as String);
    final idx = date.difference(startDate).inDays;
    if (idx < 0 || idx >= count) continue;
    final cents = row['home_amount_cents'] as int? ?? 0;
    if (row['type'] == 'income') {
      incomeBuckets[idx] += cents;
    } else {
      spendBuckets[idx] += cents;
    }
  }

  return List.generate(count, (i) {
    final date = startDate.add(Duration(days: i));
    final label = count <= 7 ? weekdayLabels[date.weekday - 1] : '${date.day}';
    return PeriodBucket(
      label: label,
      spendCents: spendBuckets[i],
      incomeCents: incomeBuckets[i],
    );
  });
}

// ── Palettes & helpers ────────────────────────────────────────────────────────

const _memberPalette = [
  Color(0xFF5B8CFF),
  Color(0xFFFF7C5B),
  Color(0xFF4DC8A0),
  Color(0xFFFFB347),
  Color(0xFFA78BFA),
  Color(0xFFFF6B9D),
  Color(0xFF34C6CD),
  Color(0xFFFFD166),
];

const _accountPalette = [
  Color(0xFF5B8CFF),
  Color(0xFFFF7C5B),
  Color(0xFF4DC8A0),
  Color(0xFFFFB347),
  Color(0xFFA78BFA),
  Color(0xFFFF6B9D),
  Color(0xFF34C6CD),
  Color(0xFFFFD166),
];

Color? _hexToColor(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return null;
  return Color(int.parse('FF$h', radix: 16));
}
