class CategoryModel {
  const CategoryModel({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.isDefault,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String icon;
  final String color;
  final bool isDefault;
  final int sortOrder;

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
        id: json['id'] as String,
        name: json['name'] as String,
        icon: json['icon'] as String,
        color: json['color'] as String,
        isDefault: json['is_default'] as bool,
        sortOrder: json['sort_order'] as int,
      );
}
