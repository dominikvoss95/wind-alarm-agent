import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class WindTrendChart extends StatelessWidget {
  final List<double> data;
  final double height;
  final Color barColor;

  const WindTrendChart({
    super.key,
    required this.data,
    this.height = 100,
    this.barColor = AppColors.accentTeal,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: data.asMap().entries.map((entry) {
          final index = entry.key;
          final value = entry.value;
          final maxVal = data.reduce((a, b) => a > b ? a : b);
          final barHeight = maxVal > 0 ? (value / maxVal) * height : 0.0;
          
          // Determine if this is the "highlighted" bar (mid-chart for demo)
          final isHighlighted = index == data.length ~/ 2;

          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              height: barHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isHighlighted
                      ? [barColor, barColor.withOpacity(0.5)]
                      : [AppColors.textMuted.withOpacity(0.3), AppColors.textMuted.withOpacity(0.1)],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
