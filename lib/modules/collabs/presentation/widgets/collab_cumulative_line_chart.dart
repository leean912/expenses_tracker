import 'dart:math' show max;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../providers/collab_analysis_provider.dart';

class CollabCumulativeLineChart extends StatelessWidget {
  const CollabCumulativeLineChart({
    super.key,
    required this.bucketDates,
    required this.series,
  });

  final List<DateTime> bucketDates;
  final List<MemberPeriodSeries> series;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static const _plotHeight = 200.0;
  static const _bottomTitleHeight = 36.0;
  static const _yAxisWidth = 68.0;
  static const _rightPad = 48.0;
  static const _pointSpacing = 28.0;

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

    // Build cumulative spots per member
    final lineBars = series.map((s) {
      int cumulative = 0;
      final spots = <FlSpot>[];
      for (var i = 0; i < dayCount; i++) {
        final daily = i < s.spendCentsByBucket.length
            ? s.spendCentsByBucket[i]
            : 0;
        cumulative += daily;
        spots.add(FlSpot(i.toDouble(), cumulative.toDouble()));
      }
      if (spots.isNotEmpty) {
        spots.add(FlSpot(dayCount.toDouble(), spots.last.y));
      }
      final lighter = Color.lerp(s.color, Colors.white, 0.45)!;
      return LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.3,
        gradient: LinearGradient(colors: [lighter, s.color]),
        barWidth: 2,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      );
    }).toList();

    // Max y across all members (final cumulative value)
    double maxY = 0;
    for (final line in lineBars) {
      if (line.spots.isNotEmpty && line.spots.last.y > maxY) {
        maxY = line.spots.last.y;
      }
    }
    final adjustedMax = maxY == 0 ? 10000.0 : maxY * 2;
    final yInterval = adjustedMax / 4;

    final minScrollWidth = (dayCount + 1) * _pointSpacing + _rightPad;

    return Column(
      children: [
        SizedBox(
          height: _plotHeight + _bottomTitleHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scrollWidth = max(
                constraints.maxWidth - _yAxisWidth,
                minScrollWidth,
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Fixed y-axis ──────────────────────────────────────────
                  SizedBox(
                    width: _yAxisWidth,
                    height: _plotHeight,
                    child: Stack(
                      children: [
                        for (var tick = 1; tick <= 3; tick++)
                          Positioned(
                            top:
                                (1 - (tick * yInterval) / adjustedMax) *
                                    _plotHeight -
                                8,
                            left: 0,
                            right: 4,
                            child: Text(
                              _fmt(tick * yInterval),
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.textTertiary,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // ── Scrollable chart (no left axis) ───────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: scrollWidth,
                        height: _plotHeight + _bottomTitleHeight,
                        child: LineChart(
                          LineChartData(
                            maxY: adjustedMax,
                            minY: 0,
                            lineBarsData: lineBars,
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
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: false,
                                  reservedSize: 0,
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
                                  reservedSize: _bottomTitleHeight,
                                  interval: 1,
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
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipColor: (_) => AppColors.surface,
                                tooltipBorder: const BorderSide(
                                  color: AppColors.border,
                                  width: 0.5,
                                ),
                                fitInsideHorizontally: true,
                                fitInsideVertically: true,
                                getTooltipItems: (touchedSpots) {
                                  return touchedSpots.map((spot) {
                                    final lineColor =
                                        spot.bar.gradient?.colors.last ??
                                        spot.bar.color ??
                                        AppColors.textPrimary;
                                    final member = spot.barIndex < series.length
                                        ? series[spot.barIndex]
                                        : null;
                                    return LineTooltipItem(
                                      '${member?.displayName ?? ''}\n${_fmt(spot.y)}',
                                      TextStyle(
                                        color: lineColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    );
                                  }).toList();
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
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
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
