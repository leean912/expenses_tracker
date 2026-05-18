import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';

class CollabSummaryData {
  const CollabSummaryData({
    required this.totalSpentCents,
    required this.totalIncomeCents,
    required this.memberSpentCents,
  });

  /// Net total across all members (expenses − income) in home currency.
  final int totalSpentCents;
  final int totalIncomeCents;

  /// userId → net spent cents (expenses − income) for that member.
  final Map<String, int> memberSpentCents;
}

/// Calls the [collab_summary] RPC — all-time totals for a collab, no date
/// filter.  Immune to the 1000-row PostgREST limit because aggregation runs
/// entirely inside PostgreSQL.
final collabSummaryProvider =
    FutureProvider.family<CollabSummaryData, String>((ref, collabId) async {
  final rpc = await supabase.rpc(
    'collab_summary',
    params: {'p_collab_id': collabId},
  ) as Map<String, dynamic>;

  int asInt(dynamic v) => (v as num? ?? 0).toInt();

  final memberRows =
      (rpc['member_totals'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

  final memberSpentCents = <String, int>{
    for (final r in memberRows)
      (r['user_id'] as String): asInt(r['spent_cents']),
  };

  return CollabSummaryData(
    totalSpentCents: asInt(rpc['total_spent_cents']),
    totalIncomeCents: asInt(rpc['total_income_cents']),
    memberSpentCents: memberSpentCents,
  );
});
