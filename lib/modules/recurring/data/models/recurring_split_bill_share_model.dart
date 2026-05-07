class RecurringSplitBillShareModel {
  const RecurringSplitBillShareModel({
    required this.id,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.shareCents,
  });

  final String id;
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int? shareCents; // null = equal split; set for custom split

  factory RecurringSplitBillShareModel.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>? ?? {};
    return RecurringSplitBillShareModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      displayName: profile['display_name'] as String? ?? '',
      avatarUrl: profile['avatar_url'] as String?,
      shareCents: json['share_cents'] != null
          ? (json['share_cents'] as num).toInt()
          : null,
    );
  }
}
