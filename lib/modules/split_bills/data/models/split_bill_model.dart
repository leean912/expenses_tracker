import 'profile_summary.dart';
import 'split_share_model.dart';

class SplitBillModel {
  const SplitBillModel({
    required this.id,
    required this.note,
    required this.totalAmountCents,
    required this.currency,
    required this.expenseDate,
    required this.createdBy,
    required this.paidBy,
    this.payer,
    this.shares = const [],
  });

  final String id;
  final String note;
  final int totalAmountCents;
  final String currency;
  final DateTime expenseDate;
  final String createdBy;
  final String paidBy;
  final ProfileSummary? payer;
  final List<SplitShareModel> shares;

  int get settledCount => shares.where((s) => s.isSettled).length;

  factory SplitBillModel.fromJson(Map<String, dynamic> json) {
    final sharesRaw = json['shares'] as List? ?? [];
    return SplitBillModel(
      id: json['id'] as String,
      note: json['note'] as String? ?? '',
      totalAmountCents: (json['total_amount_cents'] as num).toInt(),
      currency: json['currency'] as String? ?? 'MYR',
      expenseDate: DateTime.parse(json['expense_date'] as String),
      createdBy: json['created_by'] as String,
      paidBy: json['paid_by'] as String,
      payer: json['payer'] != null
          ? ProfileSummary.fromJson(json['payer'] as Map<String, dynamic>)
          : null,
      shares: sharesRaw
          .map((s) => SplitShareModel.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
