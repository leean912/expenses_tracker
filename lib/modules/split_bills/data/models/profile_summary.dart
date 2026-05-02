class ProfileSummary {
  const ProfileSummary({
    required this.id,
    this.username,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String? username;
  final String? displayName;
  final String? avatarUrl;

  String get displayLabel => username ?? 'Unknown';

  factory ProfileSummary.fromJson(Map<String, dynamic> json) => ProfileSummary(
        id: json['id'] as String,
        username: json['username'] as String?,
        displayName: json['display_name'] as String?,
        avatarUrl: json['avatar_url'] as String?,
      );
}
