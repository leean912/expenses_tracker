import 'package:flutter/material.dart';

/// Design tokens for the expense tracker app.
///
/// All colors live here. Don't hardcode hex values in widgets.
class AppColors {
  AppColors._();

  // Surfaces
  static const Color background = Color(0xFFF7F4EE); // warm off-white
  static const Color surface = Color(0xFFFFFFFF); // card white
  static const Color surfaceMuted = Color(0xFFF1EFE8); // bar tracks, dividers

  // Text
  static const Color textPrimary = Color(0xFF2C2C2A); // deep charcoal
  static const Color textSecondary = Color(0xFF5F5E5A); // muted
  static const Color textTertiary = Color(0xFF888780); // hints/captions

  // Accent
  static const Color accent = Color(0xFF2C2C2A); // dark accent for nav, FAB
  static const Color accentText = Color(0xFFF7F4EE); // text on accent

  // Borders
  static const Color border = Color(0x0F000000); // ~6% black
  static const Color borderDashed = Color(0x2E000000); // ~18% black

  // Category palette: each category has a (light bg, dark fg, bar fg)
  static const Color foodLight = Color(0xFFFAECE7);
  static const Color foodDark = Color(0xFF993C1D);
  static const Color foodBar = Color(0xFFD85A30);

  static const Color transportLight = Color(0xFFE6F1FB);
  static const Color transportDark = Color(0xFF185FA5);
  static const Color transportBar = Color(0xFF378ADD);

  static const Color shoppingLight = Color(0xFFFBEAF0);
  static const Color shoppingDark = Color(0xFF993556);
  static const Color shoppingBar = Color(0xFFD4537E);

  static const Color entertainmentLight = Color(0xFFEEEDFE);
  static const Color entertainmentDark = Color(0xFF3C3489);
  static const Color entertainmentBar = Color(0xFF7F77DD);

  static const Color incomeLight = Color(0xFFE1F5EE);
  static const Color incomeDark = Color(0xFF0F6E56);
  static const Color expenseLight = Color(
    0xFFff1919,
  ); // for negative amounts with category
  static const Color expenseDark = Color(
    0xFF6E1E00,
  ); // for negative amounts without category

  static const Color budgetOverallBar = Color(0xFFBA7517);

  // Status colors
  static const Color positiveLight = Color(0xFFEAF3DE);
  static const Color positiveDark = Color(0xFF3B6D11);
}

/// Spacing tokens (4pt grid).
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 24;
}

/// Border radius tokens.
class AppRadius {
  AppRadius._();

  static const double sm = 4;
  static const double md = 10;
  static const double lg = 12;
  static const double xl = 18;
  static const double xxl = 24;
  static const double pill = 999;
}
