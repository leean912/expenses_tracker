import 'recurring_split_bill_share_model.dart';

class RecurringSplitBillModel {
  const RecurringSplitBillModel({
    required this.id,
    required this.title,
    required this.amountCents,
    required this.splitMethod,
    required this.frequency,
    required this.nextRunAt,
    required this.isActive,
    required this.shares,
    this.categoryId,
    this.accountId,
    this.note,
  });

  final String id;
  final String title;
  final int amountCents;
  final String splitMethod; // 'equal' | 'custom'
  final String frequency;   // 'daily' | 'monthly' | 'yearly'
  final DateTime nextRunAt;
  final bool isActive;
  final List<RecurringSplitBillShareModel> shares;
  final String? categoryId;
  final String? accountId;
  final String? note;

  factory RecurringSplitBillModel.fromJson(Map<String, dynamic> json) {
    final sharesRaw = json['shares'] as List? ?? [];
    return RecurringSplitBillModel(
      id: json['id'] as String,
      title: json['title'] as String,
      amountCents: (json['amount_cents'] as num).toInt(),
      splitMethod: json['split_method'] as String,
      frequency: json['frequency'] as String,
      nextRunAt: DateTime.parse(json['next_run_at'] as String),
      isActive: json['is_active'] as bool,
      shares: sharesRaw
          .map((s) => RecurringSplitBillShareModel.fromJson(
                s as Map<String, dynamic>,
              ))
          .toList(),
      categoryId: json['category_id'] as String?,
      accountId: json['account_id'] as String?,
      note: json['note'] as String?,
    );
  }

  RecurringSplitBillModel copyWith({bool? isActive}) => RecurringSplitBillModel(
        id: id,
        title: title,
        amountCents: amountCents,
        splitMethod: splitMethod,
        frequency: frequency,
        nextRunAt: nextRunAt,
        isActive: isActive ?? this.isActive,
        shares: shares,
        categoryId: categoryId,
        accountId: accountId,
        note: note,
      );
}
