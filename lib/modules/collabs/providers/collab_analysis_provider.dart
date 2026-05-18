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

/// Calls the [collab_analytics] RPC and returns pre-aggregated data for the
/// analysis screen.  Immune to the 1000-row PostgREST limit — aggregation runs
/// entirely inside PostgreSQL, returning at most 365 daily rows per period.
final collabAnalysisProvider =
    FutureProvider.family<CollabAnalysisData, CollabAnalysisFilter>((
  ref,
  filter,
) async {
  final currentUserId = supabase.auth.currentUser?.id ?? '';
  final startDate = filter.effectiveStart;
  final endDate = filter.effectiveEnd;

  final rpc = await supabase.rpc('collab_analytics', params: {
    'p_collab_id': filter.collabId,
    'p_start': filter.startIso,
    'p_end': filter.endIso,
  }) as Map<String, dynamic>;

  int asInt(dynamic v) => (v as num? ?? 0).toInt();

  final totalSpentCents = asInt(rpc['total_spent_cents']);
  final totalIncomeCents = asInt(rpc['total_income_cents']);

  // ── Self category breakdown ────────────────────────────────────────────────

  final selfCatRows =
      (rpc['self_category'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  final selfCatTotal =
      selfCatRows.fold<int>(0, (s, r) => s + asInt(r['total_cents']));

  final selfCategoryBreakdown = selfCatRows
      .where((r) => asInt(r['total_cents']) > 0)
      .map((r) {
        final color =
            _hexToColor(r['category_color'] as String?) ?? const Color(0xFF888780);
        final cents = asInt(r['total_cents']);
        return CategorySpend(
          categoryId: r['category_id'] as String? ?? '',
          categoryName: r['category_name'] as String? ?? 'Other',
          color: color,
          totalCents: cents,
          percentage: selfCatTotal <= 0 ? 0 : cents / selfCatTotal * 100,
        );
      })
      .toList()
    ..sort((a, b) => b.totalCents.compareTo(a.totalCents));

  // ── Self account breakdown ─────────────────────────────────────────────────

  final selfAccRows =
      (rpc['self_account'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  final sortedSelfAccRows = selfAccRows
      .where((r) => asInt(r['total_cents']) > 0)
      .toList()
    ..sort((a, b) => asInt(b['total_cents']).compareTo(asInt(a['total_cents'])));
  final selfAccTotal =
      sortedSelfAccRows.fold<int>(0, (s, r) => s + asInt(r['total_cents']));

  final selfAccountBreakdown = sortedSelfAccRows.indexed.map((entry) {
    final (i, r) = entry;
    final cents = asInt(r['total_cents']);
    return CategorySpend(
      categoryId: r['account_id'] as String? ?? '',
      categoryName: r['account_name'] as String? ?? 'No Account',
      color: _accountPalette[i % _accountPalette.length],
      totalCents: cents,
      percentage: selfAccTotal <= 0 ? 0 : cents / selfAccTotal * 100,
    );
  }).toList();

  // ── Daily bucket dates ─────────────────────────────────────────────────────

  final dayCount = endDate.difference(startDate).inDays + 1;
  final bucketDates = List.generate(
    dayCount > 0 ? dayCount : 0,
    (i) => startDate.add(Duration(days: i)),
  );

  // ── Per-member period series ───────────────────────────────────────────────

  final dailyMemberBuckets =
      (rpc['daily_member_buckets'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

  // Accumulate total spend per member to determine sort order and color.
  final Map<String, String> memberNames = {};
  final Map<String, int> memberTotalSpend = {};
  for (final r in dailyMemberBuckets) {
    final userId = r['user_id'] as String? ?? '';
    memberNames[userId] = r['display_name'] as String? ?? 'Unknown';
    memberTotalSpend[userId] =
        (memberTotalSpend[userId] ?? 0) + asInt(r['spend_cents']);
  }

  final sortedMemberEntries = memberTotalSpend.entries
      .where((e) => e.value > 0)
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final memberPeriodSeries = sortedMemberEntries.indexed.map((entry) {
    final (colorIdx, memberEntry) = entry;
    final userId = memberEntry.key;
    final userDailyRows =
        dailyMemberBuckets.where((r) => r['user_id'] == userId).toList();
    final buckets = _buildMemberBuckets(
      userDailyRows,
      startDate,
      dayCount > 0 ? dayCount : 0,
      asInt,
    );
    return MemberPeriodSeries(
      userId: userId,
      displayName: memberNames[userId] ?? 'Unknown',
      color: _memberPalette[colorIdx % _memberPalette.length],
      spendCentsByBucket: buckets,
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

// ── Helpers ───────────────────────────────────────────────────────────────────

List<int> _buildMemberBuckets(
  List<Map<String, dynamic>> dailyRows,
  DateTime startDate,
  int count,
  int Function(dynamic) asInt,
) {
  final buckets = List.filled(count, 0);
  for (final r in dailyRows) {
    final date = DateTime.parse(r['bucket_date'] as String);
    final idx = date.difference(startDate).inDays;
    if (idx < 0 || idx >= count) continue;
    buckets[idx] += asInt(r['spend_cents']);
  }
  return buckets;
}

// ── Palettes & color helpers ──────────────────────────────────────────────────

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
