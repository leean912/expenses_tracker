import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../providers/analysis_state.dart';

class CategoryPieChart extends StatefulWidget {
  const CategoryPieChart({
    super.key,
    required this.categories,
    this.compact = false,
  });

  final List<CategorySpend> categories;
  final bool compact;

  @override
  State<CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<CategoryPieChart> {
  int _touchedIndex = -1;

  String _fmtCents(int cents) {
    final rm = cents / 100;
    final parts = rm.toStringAsFixed(2).split('.');
    final buf = StringBuffer();
    final chars = parts[0].split('').reversed.toList();
    for (var i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 == 0) buf.write(',');
      buf.write(chars[i]);
    }
    return 'RM ${buf.toString().split('').reversed.join()}.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.categories.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'No spending this period',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
        ),
      );
    }

    final touched =
        _touchedIndex >= 0 && _touchedIndex < widget.categories.length
            ? widget.categories[_touchedIndex]
            : null;

    final pieHeight = widget.compact ? 150.0 : 220.0;
    final outerRadius = widget.compact ? 48.0 : 60.0;
    final touchedRadius = widget.compact ? 58.0 : 72.0;
    final centerRadius = widget.compact ? 40.0 : 60.0;

    final sections = widget.categories.asMap().entries.map((entry) {
      final i = entry.key;
      final cat = entry.value;
      final isTouched = i == _touchedIndex;

      return PieChartSectionData(
        value: cat.totalCents.toDouble(),
        color: cat.color,
        radius: isTouched ? touchedRadius : outerRadius,
        title: '',
        showTitle: false,
      );
    }).toList();

    return Column(
      children: [
        SizedBox(
          height: pieHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: centerRadius,
                  sectionsSpace: 2,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            response == null ||
                            response.touchedSection == null) {
                          _touchedIndex = -1;
                          return;
                        }
                        _touchedIndex =
                            response.touchedSection!.touchedSectionIndex;
                      });
                    },
                  ),
                ),
              ),
              touched != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: touched.color.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: touched.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          touched.categoryName,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          _fmtCents(touched.totalCents),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${touched.percentage.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _fmtCents(widget.categories.fold(0, (s, e) => s + e.totalCents)),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const Text(
                          'Total spent',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.sm,
            children: widget.categories.map((cat) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: cat.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    cat.categoryName,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
