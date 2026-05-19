class TagModel {
  const TagModel({
    required this.id,
    required this.name,
    required this.color,
    required this.isDefault,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String color;
  final bool isDefault;
  final int sortOrder;

  factory TagModel.fromJson(Map<String, dynamic> json) => TagModel(
        id: json['id'] as String,
        name: json['name'] as String,
        color: json['color'] as String,
        isDefault: json['is_default'] as bool? ?? false,
        sortOrder: json['sort_order'] as int,
      );
}
