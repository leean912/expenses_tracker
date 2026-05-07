import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../providers/analysis_state.dart';

class SpendVsBudgetChart extends StatelessWidget {
  const SpendVsBudgetChart({
    super.key,
    required this.points,
    this.spendColor = const Color(0xFFD84040),
  });

  final List<SpendVsBudgetPoint> points;
  final Color spendColor;

  String _fmt(double cents) {
    final rm = cents / 100;
    if (rm >= 10000) return 'RM${(rm / 1000).toStringAsFixed(1)}K';
    if (rm >= 1000) return 'RM${rm.toStringAsFixed(0).replaceAllMapped(_thousands, (m) => '${m[1]},${m[2]}')}';
    return 'RM${rm.toStringAsFixed(0)}';
  }

  static final _thousands = RegExp(r'(\d)(\d{3})$');

  @override
  Widget build(BuildContext context) {
    final hasBudget = points.any((p) => p.cumulativeBudgetCents > 0);
    final hasSpend = points.any((p) => p.cumulativeSpendCents > 0);

    if (!hasSpend && !hasBudget) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'No spending or budget data',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
        ),
      );
    }

    final spendSpots = points
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.cumulativeSpendCents.toDouble()))
        .toList();

    final budgetSpots = points
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.cumulativeBudgetCents.toDouble()))
        .toList();

    final maxVal = points.fold<double>(0, (m, p) {
      final v = p.cumulativeSpendCents > p.cumulativeBudgetCents
          ? p.cumulativeSpendCents.toDouble()
          : p.cumulativeBudgetCents.toDouble();
      return v > m ? v : m;
    });
    final adjustedMax = maxVal == 0 ? 10000.0 : maxVal * 1.25;
    final yInterval = adjustedMax / 4;

    const budgetColor = Color(0xFF888780);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LegendDot(color: spendColor, label: 'Actual spend'),
            const SizedBox(width: 16),
            _LegendDot(color: budgetColor, label: 'Budget pace', dashed: true),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (points.length - 1).toDouble(),
              minY: 0,
              maxY: adjustedMax,
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
                    reservedSize: 22,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= points.length) {
                        return const SizedBox.shrink();
                      }
                      final step = points.length <= 7
                          ? 1
                          : (points.length / 6).ceil();
                      if (i % step != 0 && i != points.length - 1) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          points[i].label,
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                // Budget pace line (dashed)
                LineChartBarData(
                  spots: budgetSpots,
                  isCurved: false,
                  color: budgetColor,
                  barWidth: 1.5,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  dashArray: [6, 4],
                ),
                // Actual spend line
                LineChartBarData(
                  spots: spendSpots,
                  isCurved: true,
                  curveSmoothness: 0.25,
                  color: spendColor,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        spendColor.withValues(alpha: 0.10),
                        spendColor.withValues(alpha: 0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.surface,
                  tooltipBorder:
                      const BorderSide(color: AppColors.border, width: 0.5),
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((s) {
                      final i = s.x.toInt();
                      final label = i < points.length ? points[i].label : '';
                      final isBudget = s.barIndex == 0;
                      return LineTooltipItem(
                        '$label\n',
                        const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                        children: [
                          TextSpan(
                            text: '${isBudget ? 'Budget' : 'Spent'}  ${_fmt(s.y)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isBudget ? budgetColor : spendColor,
                            ),
                          ),
                        ],
                      );
                    }).toList();
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
  const _LegendDot({
    required this.color,
    required this.label,
    this.dashed = false,
  });

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          child: dashed
              ? Row(
                  children: [
                    Container(width: 6, height: 1.5, color: color),
                    const SizedBox(width: 2),
                    Container(width: 6, height: 1.5, color: color),
                  ],
                )
              : Container(height: 2, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
