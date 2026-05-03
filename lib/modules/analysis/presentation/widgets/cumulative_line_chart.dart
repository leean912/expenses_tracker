import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../providers/analysis_state.dart';

class CumulativeLineChart extends StatelessWidget {
  const CumulativeLineChart({super.key, required this.points});

  final List<DailyPoint> points;

  String _fmt(double cents) {
    final rm = cents / 100;
    if (rm >= 1000) return 'RM${(rm / 1000).toStringAsFixed(1)}K';
    return 'RM${rm.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty || points.every((p) => p.cumulativeCents == 0)) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'No spending data',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
        ),
      );
    }

    final spots = points
        .asMap()
        .entries
        .map((e) =>
            FlSpot(e.key.toDouble(), e.value.cumulativeCents.toDouble()))
        .toList();

    final maxY = points
        .map((p) => p.cumulativeCents)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    final adjustedMax = maxY * 1.25;
    final yInterval = adjustedMax / 4;

    return SizedBox(
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
                  final step = points.length <= 7 ? 1 : (points.length / 5).ceil();
                  if (i % step != 0 && i != points.length - 1) {
                    return const SizedBox.shrink();
                  }
                  final d = points[i].date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${d.day}/${d.month}',
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
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: AppColors.accent,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0.12),
                    AppColors.accent.withValues(alpha: 0.0),
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
              getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
                final i = s.x.toInt();
                final d = i < points.length ? points[i].date : null;
                return LineTooltipItem(
                  d != null ? '${d.day}/${d.month}\n' : '',
                  const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                  children: [
                    TextSpan(
                      text: _fmt(s.y),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
