import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';

class CollabSummaryData {
  const CollabSummaryData({
    required this.totalSpentCents,
    required this.totalActualCents,
    required this.memberSpentCents,
    required this.memberActualCents,
  });

  /// Sum of home_amount_cents for all non-settlement expense rows.
  final int totalSpentCents;

  /// Sum of actual_amount_cents (falls back to home_amount_cents) for all
  /// non-settlement expense rows.
  final int totalActualCents;

  /// userId → sum of home_amount_cents (total mode) for that member.
  final Map<String, int> memberSpentCents;

  /// userId → sum of actual_amount_cents (actual mode) for that member.
  final Map<String, int> memberActualCents;
}

/// Calls the [collab_summary] RPC — all-time totals for a collab, no date
/// filter.  Settlement rows are excluded so split bill settlements are not
/// double-counted against the original payer expense.  Returns both total
/// (home_amount_cents) and actual (actual_amount_cents) aggregates so the
/// Flutter toggle works without a second RPC call.
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
  final memberActualCents = <String, int>{
    for (final r in memberRows)
      (r['user_id'] as String): asInt(r['actual_cents']),
  };

  return CollabSummaryData(
    totalSpentCents: asInt(rpc['total_spent_cents']),
    totalActualCents: asInt(rpc['total_actual_cents']),
    memberSpentCents: memberSpentCents,
    memberActualCents: memberActualCents,
  );
});
