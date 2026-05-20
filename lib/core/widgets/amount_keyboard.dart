import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AmountKeyboard extends StatefulWidget {
  const AmountKeyboard({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<AmountKeyboard> createState() => _AmountKeyboardState();
}

class _AmountKeyboardState extends State<AmountKeyboard> {
  double? _leftVal;
  String? _operator;
  bool _freshOperand = false;

  static const double _max = 99999999.99;

  @override
  void didUpdateWidget(AmountKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _leftVal = null;
      _operator = null;
      _freshOperand = false;
    }
  }

  void _setText(String text) {
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  String get _text => widget.controller.text;

  void _onKey(String key) {
    if (key == '⌫') {
      if (_freshOperand) {
        setState(() {
          _operator = null;
          _freshOperand = false;
        });
        _setText(_leftVal != null ? _numStr(_leftVal!) : '');
      } else if (_text.isNotEmpty) {
        _setText(_text.substring(0, _text.length - 1));
      }
      return;
    }

    if (key == '=') {
      if (_leftVal == null || _operator == null || _freshOperand) return;
      final right = double.tryParse(_text);
      if (right == null) return;
      final result = _eval(_leftVal!, _operator!, right);
      if (result == null) return;
      setState(() {
        _leftVal = null;
        _operator = null;
        _freshOperand = false;
      });
      _setText(result.toStringAsFixed(2));
      return;
    }

    if (key == '+' || key == '−' || key == '×' || key == '÷') {
      if (_freshOperand) {
        setState(() => _operator = key);
        return;
      }
      final current = double.tryParse(_text);
      if (current == null) return;
      if (_leftVal != null && _operator != null) {
        final result = _eval(_leftVal!, _operator!, current);
        if (result == null) return;
        _leftVal = result;
        _setText(result.toStringAsFixed(2));
      } else {
        _leftVal = current;
      }
      setState(() {
        _operator = key;
        _freshOperand = true;
      });
      return;
    }

    if (key == '.') {
      if (_freshOperand) {
        _setText('0.');
        setState(() => _freshOperand = false);
        return;
      }
      if (!_text.contains('.')) {
        _setText(_text.isEmpty ? '0.' : '$_text.');
      }
      return;
    }

    // Digit
    String next;
    if (_freshOperand) {
      next = key;
      setState(() => _freshOperand = false);
    } else if (_text == '0') {
      next = key;
    } else {
      final dotIdx = _text.indexOf('.');
      if (dotIdx != -1 && _text.length - dotIdx > 2) return;
      next = _text + key;
    }
    final val = double.tryParse(next);
    if (val != null && val > _max) return;
    _setText(next);
  }

  double? _eval(double a, String op, double b) {
    switch (op) {
      case '+':
        return a + b;
      case '−':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        return b == 0 ? null : a / b;
    }
    return null;
  }

  String _numStr(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['7', '8', '9', '÷'],
      ['4', '5', '6', '×'],
      ['1', '2', '3', '−'],
      ['.', '0', '⌫', '+'],
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_leftVal != null && _operator != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_numStr(_leftVal!)} $_operator',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
            child: Column(
              children: rows
                  .map(
                    (row) => Row(
                      children: row.map((key) {
                        final isOp =
                            key == '+' ||
                            key == '−' ||
                            key == '×' ||
                            key == '÷';
                        final isBack = key == '⌫';
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Material(
                              color: isOp
                                  ? AppColors.accent.withValues(alpha: 0.08)
                                  : AppColors.background,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                                onTap: () => _onKey(key),
                                child: SizedBox(
                                  height: 50,
                                  child: Center(
                                    child: isBack
                                        ? const Icon(
                                            Icons.backspace_outlined,
                                            size: 20,
                                            color: AppColors.textSecondary,
                                          )
                                        : Text(
                                            key,
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w500,
                                              color: isOp
                                                  ? AppColors.accent
                                                  : AppColors.textPrimary,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  )
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 3, 9, 9),
            child: Material(
              color: (_leftVal != null && _operator != null && !_freshOperand)
                  ? AppColors.accent
                  : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () => _onKey('='),
                child: const SizedBox(
                  height: 50,
                  child: Center(
                    child: Text(
                      '=',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
