import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/models/my_share_item.dart';
import '../data/models/profile_summary.dart';
import '../data/models/split_bill_model.dart';
import '../data/models/split_share_model.dart';

class SplitBillsData {
  const SplitBillsData({required this.myBills, required this.myShares});
  final List<SplitBillModel> myBills;
  final List<MyShareItem> myShares;
}

class SplitBillsNotifier extends AsyncNotifier<SplitBillsData> {
  @override
  Future<SplitBillsData> build() {
    ref.watch(currentUserIdProvider);
    return _fetch();
  }

  Future<SplitBillsData> _fetch() async {
    final userId = supabase.auth.currentUser!.id;

    final billsRaw = await supabase
        .from('split_bills')
        .select(
          '*, shares:split_bill_shares(*, user:profiles(id, username, display_name, avatar_url)), payer:profiles!paid_by(id, username, display_name, avatar_url)',
        )
        .eq('created_by', userId)
        .isFilter('deleted_at', null)
        .order('expense_date', ascending: false)
        .limit(1000);

    final myBills = (billsRaw as List)
        .map((r) => SplitBillModel.fromJson(r as Map<String, dynamic>))
        .toList();

    final sharesRaw = await supabase
        .from('split_bill_shares')
        .select(
          '*, bill:split_bills!inner(id, note, total_amount_cents, currency, expense_date, paid_by, deleted_at, payer:profiles!paid_by(id, username, display_name, avatar_url))',
        )
        .eq('user_id', userId)
        .isFilter('archived_at', null)
        .order('created_at', ascending: false)
        .limit(1000);

    final myShares = (sharesRaw as List)
        .map((r) => r as Map<String, dynamic>)
        .where((r) {
          final bill = r['bill'] as Map<String, dynamic>?;
          return bill != null &&
              bill['paid_by'] != userId &&
              bill['deleted_at'] == null;
        })
        .map((r) {
          final billData = r['bill'] as Map<String, dynamic>;
          final shareData = Map<String, dynamic>.from(r)..remove('bill');
          shareData['split_bill_id'] = billData['id'];
          return MyShareItem(
            share: SplitShareModel.fromJson(shareData),
            billId: billData['id'] as String,
            billNote: billData['note'] as String? ?? '',
            billTotalCents: (billData['total_amount_cents'] as num).toInt(),
            currency: billData['currency'] as String? ?? 'MYR',
            expenseDate: DateTime.parse(billData['expense_date'] as String),
            payer: billData['payer'] != null
                ? ProfileSummary.fromJson(
                    billData['payer'] as Map<String, dynamic>,
                  )
                : null,
          );
        })
        .toList();

    return SplitBillsData(myBills: myBills, myShares: myShares);
  }

  Future<String?> deleteSplitBill(
    String billId, {
    bool deleteRelatedExpenses = false,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();

      if (deleteRelatedExpenses) {
        final userId = supabase.auth.currentUser!.id;

        // Soft-delete the payer's split_payer expense
        await supabase
            .from('expenses')
            .update({'deleted_at': now})
            .eq('source_split_bill_id', billId)
            .eq('user_id', userId)
            .isFilter('deleted_at', null);

        // Find share IDs for this bill
        final sharesRaw = await supabase
            .from('split_bill_shares')
            .select('id')
            .eq('split_bill_id', billId);
        final shareIds =
            (sharesRaw as List).map((r) => r['id'] as String).toList();

        if (shareIds.isNotEmpty) {
          // Find settlement IDs linked to those shares
          final settlementsRaw = await supabase
              .from('settlements')
              .select('id')
              .inFilter('split_bill_share_id', shareIds);
          final settlementIds = (settlementsRaw as List)
              .map((r) => r['id'] as String)
              .toList();

          if (settlementIds.isNotEmpty) {
            // Soft-delete the payer's settlement income rows
            await supabase
                .from('expenses')
                .update({'deleted_at': now})
                .inFilter('source_settlement_id', settlementIds)
                .eq('user_id', userId)
                .isFilter('deleted_at', null);
          }
        }
      }

      await supabase
          .from('split_bills')
          .update({'deleted_at': now})
          .eq('id', billId);
      ref.invalidateSelf();
      return null;
    } catch (e) {
      return 'Failed to delete. Please try again.';
    }
  }

  Future<String?> settleShare({
    required String shareId,
    required String categoryId,
    required String accountId,
  }) async {
    try {
      await supabase.rpc('settle_split_share', params: {
        'p_share_id': shareId,
        'p_category_id': categoryId,
        'p_account_id': accountId,
      });
      ref.invalidateSelf();
      return null;
    } catch (e) {
      return 'Failed to settle. Please try again.';
    }
  }

  Future<String?> updateShareAmount({
    required String shareId,
    required int newCents,
  }) async {
    try {
      await supabase
          .from('split_bill_shares')
          .update({
            'share_cents': newCents,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', shareId);
      ref.invalidateSelf();
      return null;
    } catch (e) {
      return 'Failed to update amount. Please try again.';
    }
  }

  Future<String?> creatorMarkSharePaid(String shareId) async {
    try {
      await supabase
          .rpc('creator_mark_share_paid', params: {'p_share_id': shareId});
      ref.invalidateSelf();
      return null;
    } catch (e) {
      return 'Failed to mark as paid. Please try again.';
    }
  }
}

final splitBillsProvider =
    AsyncNotifierProvider<SplitBillsNotifier, SplitBillsData>(
  SplitBillsNotifier.new,
);
