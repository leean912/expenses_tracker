import 'profile_summary.dart';

class SplitShareModel {
  const SplitShareModel({
    required this.id,
    required this.userId,
    required this.splitBillId,
    required this.shareCents,
    required this.status,
    this.user,
  });

  final String id;
  final String userId;
  final String splitBillId;
  final int shareCents;
  final String status;
  final ProfileSummary? user;

  bool get isPending => status == 'pending';
  bool get isSettled => status == 'settled';

  factory SplitShareModel.fromJson(Map<String, dynamic> json) => SplitShareModel(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        splitBillId: json['split_bill_id'] as String,
        shareCents: (json['share_cents'] as num).toInt(),
        status: json['status'] as String? ?? 'pending',
        user: json['user'] != null
            ? ProfileSummary.fromJson(json['user'] as Map<String, dynamic>)
            : null,
      );
}
