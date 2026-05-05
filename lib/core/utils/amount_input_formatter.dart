import 'package:flutter/services.dart';

/// Restricts amount input to a maximum of 99,999,999.99.
/// Allows up to 2 decimal places and rejects values exceeding the cap.
class AmountInputFormatter extends TextInputFormatter {
  static const double _max = 99999999.99;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    if (text.isEmpty) return newValue;

    // Allow only digits and a single decimal point.
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(text)) return oldValue;

    // Restrict to 2 decimal places.
    final dotIndex = text.indexOf('.');
    if (dotIndex != -1 && text.length - dotIndex - 1 > 2) return oldValue;

    // Reject values exceeding the maximum.
    final value = double.tryParse(text);
    if (value != null && value > _max) return oldValue;

    return newValue;
  }
}
