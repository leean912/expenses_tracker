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
    final from = json['from'] as Map<String, dynamic>? ?? {};
    return ContactRequestModel(
      id: json['id'] as String,
      fromUserId: from['id'] as String? ?? '',
      username: from['username'] as String?,
      displayName: from['display_name'] as String? ?? '',
      avatarUrl: from['avatar_url'] as String?,
    );
  }
}
