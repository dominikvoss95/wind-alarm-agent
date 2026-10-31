import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/wind_api_service.dart';
import '../theme/app_theme.dart';
import '../utils/spot_presentation.dart';
import 'mira_controls.dart';

class ForecastCard extends StatefulWidget {
  final WindForecast forecast;
  final DateTime now;

  const ForecastCard({super.key, required this.forecast, required this.now});

  @override
  State<ForecastCard> createState() => _ForecastCardState();
}

class _ForecastCardState extends State<ForecastCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    final forecast = widget.forecast;
    final sources = forecast.sourcesAnalyzed;
    final header = <Widget>[
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: mira.accent.withValues(alpha: MiraColors.pillTint),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.psychology_rounded, color: mira.accent, size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('KI-Prognose', style: mira.title),
                  Text(tomorrowCaption(widget.now), style: mira.caption),
                ],
              ),
            ],
          ),
          _ConfidenceChip(confidence: forecast.confidence),
        ],
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          _ChanceRing(percent: forecast.windProbabilityPercent),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MiraLabel('Erwartet'),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      style: mira.h1,
                      children: [
                        TextSpan(text: '${forecast.expectedWindMin}–${forecast.expectedWindMax} '),
                        TextSpan(text: 'kts', style: mira.title.copyWith(color: mira.textSecondary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _Meta(
                      icon: Icons.north_rounded,
                      label: 'aus ${forecast.expectedDirection}',
                      rotation: ((bearingOf(forecast.expectedDirection) ?? 0) + 180) * math.pi / 180,
                    ),
                    _Meta(
                      icon: Icons.schedule_outlined,
                      label: compactHourWindow(forecast.bestTimeWindow),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ];
    if (forecast.summary.isNotEmpty) {
      header
        ..add(const SizedBox(height: 18))
        ..add(Text(forecast.summary, style: mira.body));
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: mira.surface,
        borderRadius: BorderRadius.circular(MiraSpace.radius),
        border: Border.all(color: mira.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(MiraSpace.card, MiraSpace.card, MiraSpace.card, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: header,
            ),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: mira.outline),
          Padding(
            padding: const EdgeInsets.fromLTRB(MiraSpace.card, 0, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: sources.isEmpty ? null : () => setState(() => _expanded = !_expanded),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Modell-Konsens', style: mira.title.copyWith(fontSize: 15)),
                              Text(
                                forecast.modelConsensus.isEmpty ? 'Keine Modellangabe' : forecast.modelConsensus,
                                style: mira.caption,
                              ),
                            ],
                          ),
                        ),
                        if (sources.isNotEmpty)
                          Icon(
                            _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                            color: mira.textSecondary,
                          ),
                      ],
                    ),
                  ),
                ),
                if (_expanded)
                  for (final source in sources)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(source.name, style: mira.title.copyWith(fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(source.summary, style: mira.caption),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _Meta extends StatelessWidget {
  final IconData icon;
  final String label;
  final double rotation;

  const _Meta({required this.icon, required this.label, this.rotation = 0});

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(
          angle: rotation,
          child: Icon(icon, size: 16, color: mira.accent),
        ),
        const SizedBox(width: 4),
        Text(label, style: mira.caption.copyWith(color: mira.textPrimary, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  final String confidence;

  const _ConfidenceChip({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    final level = _level(confidence);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: mira.surface2,
        borderRadius: BorderRadius.circular(MiraSpace.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Konfidenz ${_label(confidence)}',
            style: mira.caption.copyWith(color: mira.textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var index = 0; index < 3; index++)
                Container(
                  width: 3,
                  height: 6.0 + index * 3,
                  margin: const EdgeInsets.only(left: 2),
                  decoration: BoxDecoration(
                    color: index < level ? mira.accent : MiraColors.windTooLittle,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  int _level(String raw) {
    switch (raw.toLowerCase()) {
      case 'high':
        return 3;
      case 'medium':
        return 2;
      default:
        return 1;
    }
  }

  String _label(String raw) {
    switch (raw.toLowerCase()) {
      case 'high':
        return 'hoch';
      case 'medium':
        return 'mittel';
      case 'low':
        return 'niedrig';
      default:
        return raw.toLowerCase();
    }
  }
}

class _ChanceRing extends StatelessWidget {
  final int percent;

  const _ChanceRing({required this.percent});

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    final value = (percent.clamp(0, 100)) / 100;
    return SizedBox(
      width: 96,
      height: 96,
      child: CustomPaint(
        painter: _RingPainter(value: value, track: mira.outline, color: mira.accent),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$percent%', style: mira.h2.copyWith(fontSize: 24, height: 28 / 24, fontWeight: FontWeight.w800)),
              Text('Chance', style: mira.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color track;
  final Color color;

  _RingPainter({required this.value, required this.track, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4.5;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawCircle(center, radius, base);
    final sweep = 2 * math.pi * value;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.value != value;
}
