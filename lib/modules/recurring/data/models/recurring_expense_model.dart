class RecurringExpenseModel {
  const RecurringExpenseModel({
    required this.id,
    required this.title,
    required this.amountCents,
    required this.type,
    required this.frequency,
    required this.nextRunAt,
    required this.isActive,
    required this.requiresPremium,
    this.categoryId,
    this.accountId,
    this.note,
  });

  final String id;
  final String title;
  final int amountCents;
  final String type;       // 'expense' | 'income'
  final String frequency;  // 'daily' | 'monthly' | 'yearly'
  final DateTime nextRunAt;
  final bool isActive;
  final bool requiresPremium;
  final String? categoryId;
  final String? accountId;
  final String? note;

  factory RecurringExpenseModel.fromJson(Map<String, dynamic> json) =>
      RecurringExpenseModel(
        id: json['id'] as String,
        title: json['title'] as String,
        amountCents: (json['amount_cents'] as num).toInt(),
        type: json['type'] as String,
        frequency: json['frequency'] as String,
        nextRunAt: DateTime.parse(json['next_run_at'] as String),
        isActive: json['is_active'] as bool,
        requiresPremium: json['requires_premium'] as bool? ?? false,
        categoryId: json['category_id'] as String?,
        accountId: json['account_id'] as String?,
        note: json['note'] as String?,
      );

  RecurringExpenseModel copyWith({
    bool? isActive,
  }) =>
      RecurringExpenseModel(
        id: id,
        title: title,
        amountCents: amountCents,
        type: type,
        frequency: frequency,
        nextRunAt: nextRunAt,
        isActive: isActive ?? this.isActive,
        requiresPremium: requiresPremium,
        categoryId: categoryId,
        accountId: accountId,
        note: note,
      );
}
