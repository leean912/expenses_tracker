class ContactModel {
  const ContactModel({
    required this.id,
    required this.friendId,
    this.nickname,
    this.username,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String friendId;
  final String? nickname;
  final String? username;
  final String? displayName;
  final String? avatarUrl;

  String get displayLabel => nickname ?? username ?? friendId;

  factory ContactModel.fromJson(Map<String, dynamic> json) {
    final friend = json['friend'] as Map<String, dynamic>? ?? {};
    return ContactModel(
      id: json['id'] as String,
      friendId: friend['id'] as String? ?? '',
      nickname: json['nickname'] as String?,
      username: friend['username'] as String?,
      displayName: friend['display_name'] as String?,
      avatarUrl: friend['avatar_url'] as String?,
    );
  }
}
