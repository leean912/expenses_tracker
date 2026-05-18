import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../settings/expense_type/providers/expense_type_provider.dart';
import '../../providers/home/home_state.dart';

String _fmtCents(int cents) {
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

/// Compact single-row banner pinned at top when the full banner scrolls away.
class AnalyticsBannerCompact extends ConsumerWidget {
  const AnalyticsBannerCompact({super.key, required this.summary});

  final AnalyticsSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActual =
        ref.watch(expenseTypeProvider).valueOrNull == ExpenseType.actual;
    final displayCents = isActual
        ? summary.actualSpentCents
        : summary.totalSpentCents;
    final label = isActual ? 'Actual expenses' : 'Total expenses';

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          const Spacer(),
          Text(
            _fmtCents(displayCents),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: displayCents < 0
                  ? AppColors.incomeDark
                  : AppColors.expenseLight,
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner card showing total spent + 3-stat row.
/// Tappable — navigates to analytics detail.
class AnalyticsBanner extends ConsumerWidget {
  const AnalyticsBanner({super.key, required this.summary, this.onTap});

  final AnalyticsSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // final isDownFromLast = summary.changePercent < 0;
    // final changePct = summary.changePercent.abs().round();
    final isActual =
        ref.watch(expenseTypeProvider).valueOrNull == ExpenseType.actual;
    final displayCents = isActual
        ? summary.actualSpentCents
        : summary.totalSpentCents;
    final avgCents = isActual
        ? summary.actualAvgPerDayCents
        : summary.avgPerDayCents;
    final changeVsLast = isActual
        ? summary.actualChangeVsLastMonthCents
        : summary.changeVsLastMonthCents;
    final label = isActual ? 'Actual expenses' : 'Total expenses';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppColors.border, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withAlpha(5),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _fmtCents(displayCents),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: displayCents < 0
                                ? AppColors.incomeDark
                                : AppColors.expenseLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.bar_chart_rounded,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Text(
                      'View analytics',
                      style: TextStyle(fontSize: 12, color: AppColors.accent),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 15,
                    color: AppColors.accent,
                  ),
                  // _ChangeBadge(isDown: isDownFromLast, percent: changePct),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _StatItem(
                      label: 'Avg/day',
                      value: _fmtCents(avgCents),
                    ),
                  ),
                  Expanded(
                    child: _StatItem(
                      label: 'Top category',
                      value: summary.topCategory,
                    ),
                  ),
                  Expanded(
                    child: _StatItem(
                      label: 'Current vs last month',
                      value:
                          '${changeVsLast < 0 ? "−" : "+"}${_fmtCents(changeVsLast)}',
                      valueColor: changeVsLast < 0
                          ? AppColors.positiveDark
                          : AppColors.expenseLight,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// class _ChangeBadge extends StatelessWidget {
//   const _ChangeBadge({required this.isDown, required this.percent});

//   final bool isDown;
//   final int percent;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
//       decoration: BoxDecoration(
//         color: AppColors.positiveLight,
//         borderRadius: BorderRadius.circular(AppRadius.pill),
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Icon(
//             isDown ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
//             size: 14,
//             color: AppColors.positiveDark,
//           ),
//           Text(
//             '$percent%',
//             style: const TextStyle(
//               fontSize: 11,
//               fontWeight: FontWeight.w500,
//               color: AppColors.positiveDark,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
