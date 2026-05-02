import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/home/home_state.dart';

/// Section header above the expense list: "Today's expenses" + total.
class PeriodSummaryHeader extends StatelessWidget {
  const PeriodSummaryHeader({
    super.key,
    required this.title,
    required this.totalCents,
    required this.filter,
  });

  final String title;
  final int totalCents;
  final HomeFilter filter;

  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _fmtDate(String iso) {
    final parts = iso.split('-');
    final day = int.parse(parts[2]);
    final month = _months[int.parse(parts[1])];
    return '$day $month';
  }

  String get _dateRangeLabel {
    final (start, end) = filter.toDateRange();
    if (start == end) return _fmtDate(start);
    return '${_fmtDate(start)} – ${_fmtDate(end)}';
  }

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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _dateRangeLabel,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
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
