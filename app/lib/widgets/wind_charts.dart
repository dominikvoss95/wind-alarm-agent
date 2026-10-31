import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/wind_api_service.dart';
import '../theme/app_theme.dart';
import '../theme/wind_scale.dart';
import '../utils/spot_presentation.dart';

class WindSparkline extends StatelessWidget {
  final List<WindHistoryItem> points;
  final double minimum;
  final DateTime now;

  const WindSparkline({
    super.key,
    required this.points,
    required this.minimum,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                (points.isEmpty ? '12 Std.' : 'Letzte 12 Std.').toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mira.label,
              ),
            ),
            const SizedBox(width: 16, height: 2, child: _DashSample()),
            const SizedBox(width: 6),
            Text('Min. ${minimum.round()} kts', style: mira.caption),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: CustomPaint(
            painter: _SparkPainter(
              points: points,
              minimum: minimum,
              now: now,
              secondary: mira.textSecondary,
              surface: mira.surface,
            ),
          ),
        ),
        const SizedBox(height: 4),
        _SparkLabels(points: points, now: now),
        if (points.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Keine Stundenwerte', style: mira.caption),
          ),
      ],
    );
  }
}

class _DashSample extends StatelessWidget {
  const _DashSample();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashPainter(color: context.mira.textSecondary),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    _dash(
      canvas,
      Offset.zero,
      Offset(size.width, 0),
      Paint()
        ..color = color
        ..strokeWidth = 1,
      dash: 3,
      gap: 3,
    );
  }

  @override
  bool shouldRepaint(covariant _DashPainter oldDelegate) => oldDelegate.color != color;
}

class _SparkLabels extends StatelessWidget {
  final List<WindHistoryItem> points;
  final DateTime now;

  const _SparkLabels({required this.points, required this.now});

  @override
  Widget build(BuildContext context) {
    final style = context.mira.caption.copyWith(fontSize: 12, height: 16 / 12);
    if (points.isEmpty) {
      return Text('Jetzt', style: style);
    }
    final times = _labelTimes(points, now);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [for (final time in times) Text(_axisLabel(time, now), style: style)],
    );
  }
}

List<DateTime> _labelTimes(List<WindHistoryItem> points, DateTime now) {
  final start = points.first.observedAt.toLocal();
  final end = points.last.observedAt.toLocal();
  if (end.difference(start).inMinutes < 1) return [end];
  return [
    start,
    start.add(end.difference(start) * 0.33),
    start.add(end.difference(start) * 0.66),
    end,
  ];
}

String _axisLabel(DateTime time, DateTime now) {
  if (now.difference(time).inMinutes.abs() < 20) return 'Jetzt';
  return '${time.hour.toString().padLeft(2, '0')} Uhr';
}

class _SparkPainter extends CustomPainter {
  final List<WindHistoryItem> points;
  final double minimum;
  final DateTime now;
  final Color secondary;
  final Color surface;

  _SparkPainter({
    required this.points,
    required this.minimum,
    required this.now,
    required this.secondary,
    required this.surface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final values = points.map((point) => point.baseWind).toList();
    final peak = values.fold<double>(minimum, math.max);
    final floor = values.fold<double>(0, math.min);
    final span = math.max(8.0, peak - math.min(floor, 0) + 4);
    final minY = math.min(floor, 0);
    double yFor(double knots) {
      final t = ((knots - minY) / span).clamp(0.0, 1.0);
      return size.height - 4 - t * (size.height - 10);
    }

    _dash(
      canvas,
      Offset(0, yFor(minimum)),
      Offset(size.width, yFor(minimum)),
      Paint()
        ..color = secondary.withValues(alpha: 0.55)
        ..strokeWidth = 1,
    );
    if (points.length < 2) {
      if (points.length == 1) {
        final color = WindScale.barColor(points.first.baseWind);
        canvas.drawCircle(Offset(4, yFor(points.first.baseWind)), 4, Paint()..color = color);
      }
      return;
    }

    final start = points.first.observedAt.toLocal();
    final end = points.last.observedAt.toLocal();
    final duration = math.max(1, end.difference(start).inSeconds);
    final offsets = <Offset>[];
    for (final point in points) {
      final t = point.observedAt.toLocal().difference(start).inSeconds / duration;
      offsets.add(Offset(4 + t * (size.width - 8), yFor(point.baseWind)));
    }

    final fill = Path()..moveTo(offsets.first.dx, size.height);
    for (final offset in offsets) {
      fill.lineTo(offset.dx, offset.dy);
    }
    fill
      ..lineTo(offsets.last.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            MiraColors.accent.withValues(alpha: 0.18),
            MiraColors.accent.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );

    for (var index = 0; index < offsets.length - 1; index++) {
      final color = WindScale.barColor(points[index].baseWind);
      canvas.drawLine(
        offsets[index],
        offsets[index + 1],
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
    final head = WindScale.numberColor(points.first.baseWind);
    canvas.drawCircle(offsets.first, 4, Paint()..color = surface);
    canvas.drawCircle(offsets.first, 3, Paint()..color = head);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.minimum != minimum;
  }
}

class HourlyWindChart extends StatelessWidget {
  final List<HourBin> bins;
  final double minimum;
  final DateTime now;

  const HourlyWindChart({
    super.key,
    required this.bins,
    required this.minimum,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    final hasForecast = bins.any((bin) => bin.forecast);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Heute', style: mira.title),
                  Text('Wind pro Stunde in kts', style: mira.caption),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LegendDot(color: mira.accent, label: 'Gemessen', dashed: false),
                if (hasForecast) ...[
                  const SizedBox(height: 4),
                  _LegendDot(color: mira.accent, label: 'Prognose', dashed: true),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 168,
          child: CustomPaint(
            painter: _HourPainter(
              bins: bins,
              minimum: minimum,
              now: now,
              secondary: mira.textSecondary,
              primary: mira.textPrimary,
              outline: mira.outline,
              surface: mira.surface,
              accent: mira.accent,
            ),
          ),
        ),
        if (bins.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Keine Stundenwerte für heute', style: mira.caption),
          ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;

  const _LegendDot({required this.color, required this.label, required this.dashed});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: dashed ? color.withValues(alpha: 0.22) : color,
            borderRadius: BorderRadius.circular(3),
            border: dashed ? Border.all(color: color.withValues(alpha: 0.7)) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: context.mira.caption),
      ],
    );
  }
}

class _HourPainter extends CustomPainter {
  final List<HourBin> bins;
  final double minimum;
  final DateTime now;
  final Color secondary;
  final Color primary;
  final Color outline;
  final Color surface;
  final Color accent;

  _HourPainter({
    required this.bins,
    required this.minimum,
    required this.now,
    required this.secondary,
    required this.primary,
    required this.outline,
    required this.surface,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const axisWidth = 26.0;
    const labelHeight = 22.0;
    final plot = Rect.fromLTWH(axisWidth, 8, size.width - axisWidth, size.height - labelHeight - 8);
    final peak = bins.fold<double>(minimum, (maxValue, bin) => math.max(maxValue, bin.knots));
    var yMax = 20.0;
    while (yMax < peak) {
      yMax += 10;
    }
    double yFor(double knots) => plot.bottom - (knots / yMax).clamp(0.0, 1.0) * plot.height;

    final grid = Paint()
      ..color = outline
      ..strokeWidth = 1;
    for (final tick in [0.0, yMax / 2, yMax]) {
      final y = yFor(tick);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _text(canvas, tick.round().toString(), Offset(0, y - 6), secondary, FontWeight.w600);
    }

    if (bins.isNotEmpty) {
      final slot = plot.width / bins.length;
      final barWidth = math.min(12.0, slot * 0.62);
      for (var index = 0; index < bins.length; index++) {
        final bin = bins[index];
        final x = plot.left + slot * index + (slot - barWidth) / 2;
        final top = yFor(bin.knots);
        final height = math.max(2.0, plot.bottom - top);
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, plot.bottom - height, barWidth, height),
          const Radius.circular(3),
        );
        final color = WindScale.barColor(bin.knots);
        if (bin.forecast) {
          canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: 0.22));
          _dashPath(
            canvas,
            Path()..addRRect(rect),
            Paint()
              ..color = color.withValues(alpha: 0.7)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        } else {
          canvas.drawRRect(rect, Paint()..color = color);
        }
        final isNow = bin.hour.year == now.year &&
            bin.hour.month == now.month &&
            bin.hour.day == now.day &&
            bin.hour.hour == now.hour;
        final showHour = index.isEven || isNow || bins.length <= 8;
        if (showHour) {
          _text(
            canvas,
            isNow ? 'Jetzt' : bin.hour.hour.toString().padLeft(2, '0'),
            Offset(x + barWidth / 2, plot.bottom + 6),
            isNow ? accent : secondary,
            isNow ? FontWeight.w700 : FontWeight.w600,
            center: true,
          );
        }
        if (isNow) {
          _text(
            canvas,
            bin.knots.round().toString(),
            Offset(x + barWidth / 2, top - 16),
            primary,
            FontWeight.w700,
            center: true,
          );
        }
      }
    }

    final minY = yFor(minimum);
    _dash(
      canvas,
      Offset(plot.left, minY),
      Offset(plot.right, minY),
      Paint()
        ..color = primary.withValues(alpha: 0.7)
        ..strokeWidth = 1.2,
      dash: 5,
      gap: 4,
    );
    final chipTop = minY > plot.top + 22 ? minY - 20 : minY + 4;
    final chipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(plot.left + 2, chipTop, 132, 17),
      const Radius.circular(6),
    );
    canvas.drawRRect(chipRect, Paint()..color = surface);
    _text(
      canvas,
      'Dein Minimum · ${minimum.round()} kts',
      Offset(plot.left + 6, chipTop + 2),
      primary,
      FontWeight.w700,
      fontSize: 11,
    );
  }

  void _text(
    Canvas canvas,
    String value,
    Offset offset,
    Color color,
    FontWeight weight, {
    bool center = false,
    double fontSize = 11,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: MiraType.family,
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center ? offset - Offset(painter.width / 2, 0) : offset);
  }

  @override
  bool shouldRepaint(covariant _HourPainter oldDelegate) {
    return oldDelegate.bins != bins || oldDelegate.minimum != minimum || oldDelegate.now != now;
  }
}

void _dash(Canvas canvas, Offset start, Offset end, Paint paint, {double dash = 4, double gap = 4}) {
  final delta = end - start;
  final length = delta.distance;
  if (length == 0) return;
  final step = delta / length;
  var distance = 0.0;
  while (distance < length) {
    final next = math.min(distance + dash, length);
    canvas.drawLine(start + step * distance, start + step * next, paint);
    distance += dash + gap;
  }
}

void _dashPath(Canvas canvas, Path path, Paint paint) {
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final next = math.min(distance + 3, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance += 5;
    }
  }
}
