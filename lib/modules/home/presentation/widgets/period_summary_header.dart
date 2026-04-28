import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Section header above the expense list: "Today's expenses" + total.
class PeriodSummaryHeader extends StatelessWidget {
  const PeriodSummaryHeader({
    super.key,
    required this.title,
    required this.totalCents,
  });

  final String title;
  final int totalCents;

  String _fmtTotal(int cents) {
    final value = (cents / 100).abs();
    final whole = value.toStringAsFixed(2);
    final parts = whole.split('.');
    final intPart = parts[0];
    final formatted = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) formatted.write(',');
      formatted.write(intPart[i]);
    }
    return 'RM $formatted.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            _fmtTotal(totalCents),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
