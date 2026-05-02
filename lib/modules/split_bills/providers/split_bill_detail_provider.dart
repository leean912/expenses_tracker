import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../service_locator.dart';
import '../data/models/split_bill_model.dart';

final splitBillDetailProvider =
    FutureProvider.autoDispose.family<SplitBillModel, String>((ref, billId) async {
  final raw = await supabase
      .from('split_bills')
      .select(
        '*, shares:split_bill_shares(*, user:profiles(id, username, display_name, avatar_url)), payer:profiles!paid_by(id, username, display_name, avatar_url)',
      )
      .eq('id', billId)
      .single();
  return SplitBillModel.fromJson(raw);
});
