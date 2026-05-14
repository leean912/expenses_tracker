class ContactRequestModel {
  const ContactRequestModel({
    required this.id,
    required this.fromUserId,
    this.username,
    required this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String fromUserId;
  final String? username;
  final String displayName;
  final String? avatarUrl;

  factory ContactRequestModel.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] as Map<String, dynamic>? ?? {};
    return ContactRequestModel(
      id: json['id'] as String,
      fromUserId: json['owner_id'] as String? ?? sender['id'] as String? ?? '',
      username: sender['username'] as String?,
      displayName: sender['display_name'] as String? ?? '',
      avatarUrl: sender['avatar_url'] as String?,
    );
  }
}
