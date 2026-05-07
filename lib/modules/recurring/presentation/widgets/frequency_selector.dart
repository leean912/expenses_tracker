import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class FrequencySelector extends StatelessWidget {
  const FrequencySelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  static const _options = [
    ('daily', 'Daily'),
    ('monthly', 'Monthly'),
    ('yearly', 'Yearly'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < _options.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: i < _options.length - 1 ? AppSpacing.sm : 0,
              ),
              child: GestureDetector(
                onTap: () => onChanged(_options[i].$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: value == _options[i].$1
                        ? AppColors.accent
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: value == _options[i].$1
                          ? AppColors.accent
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    _options[i].$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: value == _options[i].$1
                          ? AppColors.accentText
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String freqLabel(String f) => switch (f) {
      'daily' => 'Daily',
      'monthly' => 'Monthly',
      'yearly' => 'Yearly',
      _ => f,
    };
