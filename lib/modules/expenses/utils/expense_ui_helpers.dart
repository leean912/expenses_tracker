import 'package:flutter/material.dart';

Color hexToColor(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

IconData iconForName(String name) {
  const map = <String, IconData>{
    'restaurant': Icons.restaurant,
    'directions_car': Icons.directions_car,
    'shopping_bag': Icons.shopping_bag,
    'receipt_long': Icons.receipt_long,
    'movie': Icons.movie,
    'favorite': Icons.favorite,
    'flight': Icons.flight,
    'school': Icons.school,
    'redeem': Icons.redeem,
    'category': Icons.category,
    'luggage': Icons.luggage,
    'payments': Icons.payments,
    'account_balance': Icons.account_balance,
    'account_balance_wallet': Icons.account_balance_wallet,
    'local_cafe': Icons.local_cafe,
    'sports': Icons.sports,
    'home': Icons.home,
    'work': Icons.work,
    'pets': Icons.pets,
    'fitness_center': Icons.fitness_center,
    'local_hospital': Icons.local_hospital,
    'computer': Icons.computer,
    'music_note': Icons.music_note,
  };
  return map[name] ?? Icons.category;
}

const kIconNames = [
  'restaurant',
  'local_cafe',
  'directions_car',
  'shopping_bag',
  'receipt_long',
  'movie',
  'favorite',
  'flight',
  'school',
  'redeem',
  'luggage',
  'payments',
  'account_balance',
  'account_balance_wallet',
  'sports',
  'home',
  'work',
  'pets',
  'fitness_center',
  'local_hospital',
  'computer',
  'music_note',
  'category',
];

const kCategoryColors = [
  '#FF6B6B',
  '#FF9F43',
  '#FECA57',
  '#1DD1A1',
  '#48DBFB',
  '#6C5CE7',
  '#A29BFE',
  '#FD79A8',
  '#0984E3',
  '#00B894',
  '#E17055',
  '#636E72',
];
