class AccountModel {
  const AccountModel({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.currency,
    required this.accountType,
    required this.isDefault,
    required this.requiresPremium,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String icon;
  final String color;
  final String currency;
  final String accountType;
  final bool isDefault;
  final bool requiresPremium;
  final int sortOrder;

  String get accountTypeLabel => switch (accountType) {
        'wallet' => 'Wallet',
        'bank' => 'Bank',
        'cash' => 'Cash',
        'credit_card' => 'Credit Card',
        'investment' => 'Investment',
        'loan' => 'Loan',
        _ => 'Other',
      };

  factory AccountModel.fromJson(Map<String, dynamic> json) => AccountModel(
        id: json['id'] as String,
        name: json['name'] as String,
        icon: json['icon'] as String,
        color: json['color'] as String,
        currency: json['currency'] as String,
        accountType: json['account_type'] as String? ?? 'other',
        isDefault: json['is_default'] as bool,
        requiresPremium: json['requires_premium'] as bool? ?? false,
        sortOrder: json['sort_order'] as int,
      );
}
