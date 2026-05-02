import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
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
  Future<SplitBillsData> build() => _fetch();

  Future<SplitBillsData> _fetch() async {
    final userId = supabase.auth.currentUser!.id;

    final billsRaw = await supabase
        .from('split_bills')
        .select(
          '*, shares:split_bill_shares(*, user:profiles(id, username, display_name, avatar_url)), payer:profiles!paid_by(id, username, display_name, avatar_url)',
        )
        .eq('created_by', userId)
        .isFilter('deleted_at', null)
        .order('expense_date', ascending: false);

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
        .order('created_at', ascending: false);

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
}

final splitBillsProvider =
    AsyncNotifierProvider<SplitBillsNotifier, SplitBillsData>(
  SplitBillsNotifier.new,
);
