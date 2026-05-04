class GroupMemberPreview {
  const GroupMemberPreview({
    required this.id,
    this.username,
    required this.displayName,
  });

  final String id;
  final String? username;
  final String displayName;

  factory GroupMemberPreview.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    return GroupMemberPreview(
      id: user['id'] as String? ?? '',
      username: user['username'] as String?,
      displayName: user['display_name'] as String? ?? '',
    );
  }
}

class GroupModel {
  const GroupModel({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.members,
  });

  final String id;
  final String name;
  final String icon;
  final String color;
  final List<GroupMemberPreview> members;

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'] as List? ?? [];
    return GroupModel(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? 'group',
      color: json['color'] as String? ?? '#378ADD',
      members: rawMembers
          .map((m) => GroupMemberPreview.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}
