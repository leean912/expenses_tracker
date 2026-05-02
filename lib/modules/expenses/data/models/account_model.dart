class AccountModel {
  const AccountModel({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.currency,
    required this.isDefault,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String icon;
  final String color;
  final String currency;
  final bool isDefault;
  final int sortOrder;

  factory AccountModel.fromJson(Map<String, dynamic> json) => AccountModel(
        id: json['id'] as String,
        name: json['name'] as String,
        icon: json['icon'] as String,
        color: json['color'] as String,
        currency: json['currency'] as String,
        isDefault: json['is_default'] as bool,
        sortOrder: json['sort_order'] as int,
      );
}
