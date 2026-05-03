import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../providers/analysis_state.dart';

class SpendingBarChart extends StatelessWidget {
  const SpendingBarChart({super.key, required this.buckets});

  final List<PeriodBucket> buckets;

  String _fmt(double cents) {
    final rm = cents / 100;
    if (rm >= 1000) return 'RM${(rm / 1000).toStringAsFixed(1)}K';
    return 'RM${rm.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty || buckets.every((b) => b.spendCents == 0 && b.incomeCents == 0)) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'No data this period',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
        ),
      );
    }

    final hasIncome = buckets.any((b) => b.incomeCents > 0);

    final maxVal = buckets
        .map((b) => hasIncome
            ? [b.spendCents, b.incomeCents].reduce((a, c) => a > c ? a : c)
            : b.spendCents)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    final adjustedMax = maxVal == 0 ? 10000.0 : maxVal * 1.3;
    final yInterval = adjustedMax / 4;

    final barGroups = buckets.asMap().entries.map((entry) {
      final i = entry.key;
      final b = entry.value;

      if (hasIncome) {
        return BarChartGroupData(
          x: i,
          barsSpace: 3,
          barRods: [
            BarChartRodData(
              toY: b.spendCents.toDouble(),
              color: const Color(0xFFD84040),
              width: 8,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(3)),
            ),
            BarChartRodData(
              toY: b.incomeCents.toDouble(),
              color: AppColors.incomeDark,
              width: 8,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ],
        );
      } else {
        return BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: b.spendCents.toDouble(),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFD84040),
                  const Color(0xFFD84040).withValues(alpha: 0.65),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              width: buckets.length <= 7 ? 18 : 10,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: adjustedMax,
                color: AppColors.surfaceMuted,
              ),
            ),
          ],
        );
      }
    }).toList();

    return Column(
      children: [
        if (hasIncome)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _LegendDot(color: const Color(0xFFD84040), label: 'Spend'),
                const SizedBox(width: AppSpacing.lg),
                _LegendDot(color: AppColors.incomeDark, label: 'Income'),
              ],
            ),
          ),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: adjustedMax,
              barGroups: barGroups,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: yInterval,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: AppColors.border,
                  strokeWidth: 0.8,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 54,
                    interval: yInterval,
                    getTitlesWidget: (value, meta) {
                      if (value == 0 || value == adjustedMax) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          _fmt(value),
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppColors.textTertiary,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= buckets.length) {
                        return const SizedBox.shrink();
                      }
                      // Thin out labels when there are many buckets
                      if (buckets.length > 8) {
                        final step = (buckets.length / 6).ceil();
                        if (i % step != 0 && i != buckets.length - 1) {
                          return const SizedBox.shrink();
                        }
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          buckets[i].label,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => AppColors.surface,
                  tooltipBorder:
                      const BorderSide(color: AppColors.border, width: 0.5),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final isIncome = hasIncome && rodIndex == 1;
                    final label = isIncome
                        ? 'Income  ${_fmt(rod.toY)}'
                        : 'Spend  ${_fmt(rod.toY)}';
                    return BarTooltipItem(
                      label,
                      TextStyle(
                        color: isIncome
                            ? AppColors.incomeDark
                            : const Color(0xFFD84040),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style:
              const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
