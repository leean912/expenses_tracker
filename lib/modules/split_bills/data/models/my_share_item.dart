import 'profile_summary.dart';
import 'split_share_model.dart';

class MyShareItem {
  const MyShareItem({
    required this.share,
    required this.billId,
    required this.billNote,
    required this.billTotalCents,
    required this.currency,
    required this.expenseDate,
    this.payer,
  });

  final SplitShareModel share;
  final String billId;
  final String billNote;
  final int billTotalCents;
  final String currency;
  final DateTime expenseDate;
  final ProfileSummary? payer;
}
