import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../providers/analysis_state.dart';

class SpendingBarChart extends StatelessWidget {
  const SpendingBarChart({super.key, required this.buckets});

  final List<PeriodBucket> buckets;

  String _fmt(double cents) {
    final rm = cents / 100;
    final abs = rm.abs();
    final formatted = abs.toStringAsFixed(0);
    final buf = StringBuffer();
    final chars = formatted.split('').reversed.toList();
    for (var i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 == 0) buf.write(',');
      buf.write(chars[i]);
    }
    final result = buf.toString().split('').reversed.join();
    return rm < 0 ? '-RM $result' : 'RM $result';
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
        .expand((b) => hasIncome ? [b.spendCents, b.incomeCents] : [b.spendCents])
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    final adjustedMax = maxVal == 0 ? 10000.0 : maxVal * 1.3;
    final yInterval = adjustedMax / 4;

    final rodWidth = hasIncome
        ? (buckets.length <= 7 ? 10.0 : 6.0)
        : (buckets.length <= 7 ? 18.0 : 10.0);

    final barGroups = buckets.asMap().entries.map((entry) {
      final i = entry.key;
      final b = entry.value;
      return BarChartGroupData(
        x: i,
        barsSpace: hasIncome ? 3 : 0,
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
            width: rodWidth,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: adjustedMax,
              color: AppColors.surfaceMuted,
            ),
          ),
          if (hasIncome)
            BarChartRodData(
              toY: b.incomeCents.toDouble(),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF4DC8A0),
                  const Color(0xFF4DC8A0).withValues(alpha: 0.65),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              width: rodWidth,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: adjustedMax,
                color: AppColors.surfaceMuted,
              ),
            ),
        ],
      );
    }).toList();

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: adjustedMax,
              barGroups: barGroups,
              groupsSpace: buckets.length <= 7 ? 12 : 6,
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
                    reservedSize: 68,
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
                    return BarTooltipItem(
                      '${isIncome ? 'Income' : 'Spend'}  ${_fmt(rod.toY)}',
                      TextStyle(
                        color: isIncome
                            ? const Color(0xFF4DC8A0)
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
        if (hasIncome) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendDot(color: const Color(0xFFD84040), label: 'Expenses'),
              const SizedBox(width: 16),
              _LegendDot(color: const Color(0xFF4DC8A0), label: 'Income'),
            ],
          ),
        ],
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
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
