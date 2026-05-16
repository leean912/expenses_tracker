import 'dart:math' show max;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../providers/collab_analysis_provider.dart';

class CollabSpendingBarChart extends StatelessWidget {
  const CollabSpendingBarChart({
    super.key,
    required this.bucketDates,
    required this.series,
  });

  final List<DateTime> bucketDates;
  final List<MemberPeriodSeries> series;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _fmt(double cents) {
    final rm = cents / 100;
    final abs = rm.abs();
    final parts = abs.toStringAsFixed(2).split('.');
    final buf = StringBuffer();
    final chars = parts[0].split('').reversed.toList();
    for (var i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 == 0) buf.write(',');
      buf.write(chars[i]);
    }
    final result = '${buf.toString().split('').reversed.join()}.${parts[1]}';
    return rm < 0 ? '-RM $result' : 'RM $result';
  }

  @override
  Widget build(BuildContext context) {
    final dayCount = bucketDates.length;

    if (dayCount == 0 || series.isEmpty) {
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

    final memberCount = series.length;
    final rodWidth = memberCount <= 1
        ? 16.0
        : memberCount <= 2
        ? 12.0
        : 8.0;
    const barsSpace = 2.0;
    const groupsSpace = 8.0;

    final maxPerBucket = List.generate(dayCount, (i) {
      return series.fold(
        0,
        (best, s) => max(
          best,
          i < s.spendCentsByBucket.length ? s.spendCentsByBucket[i] : 0,
        ),
      );
    });
    final maxVal =
        maxPerBucket.isEmpty ? 0 : maxPerBucket.reduce((a, b) => a > b ? a : b);
    final adjustedMax = maxVal == 0 ? 10000.0 : maxVal * 1.3;
    final yInterval = adjustedMax / 4;

    final barGroups = List.generate(dayCount, (i) {
      return BarChartGroupData(
        x: i,
        barsSpace: barsSpace,
        barRods: series.map((s) {
          final spend = (i < s.spendCentsByBucket.length
                  ? s.spendCentsByBucket[i]
                  : 0)
              .toDouble();
          return BarChartRodData(
            toY: spend,
            color: s.color,
            width: rodWidth,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(3)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: adjustedMax,
              color: AppColors.surfaceMuted,
            ),
          );
        }).toList(),
      );
    });

    // Compute minimum chart width for horizontal scroll
    final groupWidth =
        memberCount * rodWidth + (memberCount - 1) * barsSpace;
    const yAxisWidth = 68.0;
    const rightPad = 12.0;
    final minChartWidth =
        dayCount * (groupWidth + groupsSpace) + groupsSpace + yAxisWidth + rightPad;

    // Label height: two lines when showing month, one line otherwise
    const bottomTitleHeight = 36.0;

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final chartWidth = max(constraints.maxWidth, minChartWidth);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth,
                height: 200 + bottomTitleHeight,
                child: BarChart(
                  BarChartData(
                    maxY: adjustedMax,
                    barGroups: barGroups,
                    groupsSpace: groupsSpace,
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
                          reservedSize: yAxisWidth,
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
                          reservedSize: bottomTitleHeight,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= dayCount) {
                              return const SizedBox.shrink();
                            }
                            final date = bucketDates[i];

                            if (dayCount <= 7) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _weekdays[date.weekday - 1],
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              );
                            }

                            final showMonth = date.day == 1 || i == 0;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${date.day}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                  if (showMonth)
                                    Text(
                                      _months[date.month - 1],
                                      style: const TextStyle(
                                        fontSize: 8,
                                        color: AppColors.textTertiary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  else
                                    const SizedBox(height: 10),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => AppColors.surface,
                        tooltipBorder: const BorderSide(
                          color: AppColors.border,
                          width: 0.5,
                        ),
                        fitInsideHorizontally: true,
                        fitInsideVertically: true,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          if (rod.toY == 0) return null;
                          final member = rodIndex < series.length
                              ? series[rodIndex]
                              : null;
                          return BarTooltipItem(
                            '${member?.displayName ?? ''}\n${_fmt(rod.toY)}',
                            TextStyle(
                              color: member?.color ?? AppColors.textPrimary,
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
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: series
              .map((s) => _LegendDot(color: s.color, label: s.displayName))
              .toList(),
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
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
