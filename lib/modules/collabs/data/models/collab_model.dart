class CollabMemberModel {
  const CollabMemberModel({
    required this.id,
    required this.collabId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.leftAt,
    this.personalBudgetCents,
    this.username,
    required this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String collabId;
  final String userId;
  final String role; // 'owner' | 'member'
  final DateTime joinedAt;
  final DateTime? leftAt;
  final int? personalBudgetCents;
  final String? username;
  final String displayName;
  final String? avatarUrl;

  bool get isOwner => role == 'owner';
  bool get isActive => leftAt == null;

  factory CollabMemberModel.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    return CollabMemberModel(
      id: json['id'] as String,
      collabId: json['collab_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String? ?? 'member',
      joinedAt: DateTime.parse(json['joined_at'] as String),
      leftAt: json['left_at'] != null
          ? DateTime.parse(json['left_at'] as String)
          : null,
      personalBudgetCents: json['personal_budget_cents'] as int?,
      username: user['username'] as String?,
      displayName: user['display_name'] as String? ?? '',
      avatarUrl: user['avatar_url'] as String?,
    );
  }

  CollabMemberModel copyWith({int? personalBudgetCents}) {
    return CollabMemberModel(
      id: id,
      collabId: collabId,
      userId: userId,
      role: role,
      joinedAt: joinedAt,
      leftAt: leftAt,
      personalBudgetCents: personalBudgetCents ?? this.personalBudgetCents,
      username: username,
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
  }
}

class CollabModel {
  const CollabModel({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description,
    this.coverPhotoUrl,
    this.startDate,
    this.endDate,
    required this.currency,
    required this.homeCurrency,
    this.exchangeRate,
    this.budgetCents,
    required this.status,
    this.closedAt,
    required this.createdAt,
    this.members = const [],
  });

  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String? coverPhotoUrl;
  final DateTime? startDate;
  final DateTime? endDate;
  final String currency;
  final String homeCurrency;
  final double? exchangeRate; // 1 homeCurrency = X currency
  final int? budgetCents; // in homeCurrency
  final String status; // 'active' | 'closed'
  final DateTime? closedAt;
  final DateTime createdAt;
  final List<CollabMemberModel> members;

  bool get isActive => status == 'active';
  bool get isClosed => status == 'closed';
  bool get isForeignCurrency => currency != homeCurrency;

  factory CollabModel.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'] as List? ?? [];
    return CollabModel(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      coverPhotoUrl: json['cover_photo_url'] as String?,
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'] as String)
          : null,
      endDate: json['end_date'] != null
          ? DateTime.parse(json['end_date'] as String)
          : null,
      currency: json['currency'] as String,
      homeCurrency: json['home_currency'] as String,
      exchangeRate: json['exchange_rate'] != null
          ? double.tryParse(json['exchange_rate'].toString())
          : null,
      budgetCents: json['budget_cents'] as int?,
      status: json['status'] as String? ?? 'active',
      closedAt: json['closed_at'] != null
          ? DateTime.parse(json['closed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      members: rawMembers
          .map((m) => CollabMemberModel.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}
