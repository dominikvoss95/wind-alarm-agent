import 'package:flutter/material.dart';

import '../models/location.dart';
import '../services/wind_api_service.dart';
import '../theme/app_theme.dart';
import '../theme/wind_scale.dart';
import '../utils/spot_presentation.dart';
import 'compass.dart';
import 'mira_controls.dart';
import 'wind_charts.dart';

class LocationOverviewCard extends StatelessWidget {
  final LocationData location;
  final WindMeasurement? measurement;
  final bool settled;
  final bool isArmed;
  final ValueChanged<bool> onArmedChanged;
  final VoidCallback onTap;
  final VoidCallback onReload;
  final bool reloading;
  final WindForecast? forecast;
  final List<WindHistoryItem> history;
  final DateTime now;

  const LocationOverviewCard({
    super.key,
    required this.location,
    required this.measurement,
    required this.settled,
    required this.isArmed,
    required this.onArmedChanged,
    required this.onTap,
    required this.onReload,
    required this.now,
    this.reloading = false,
    this.forecast,
    this.history = const [],
  });

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    final live = settled && measurement != null && readingIsFresh(measurement!, now);
    final knots = live ? measurement!.baseWind : null;
    final color = knots == null ? mira.textSecondary : WindScale.numberColor(knots);
    final window = displayWindow(location.activeWindow);
    final statusColor = isArmed ? mira.accent : mira.textSecondary;
    final series = seriesLast12Hours(history, now, live: live ? measurement : null);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MiraSpace.radius),
        child: Ink(
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
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(location.name, style: mira.h2)),
                        const SizedBox(width: 8),
                        _verdict(mira, live, knots),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${isArmed ? 'Überwachung aktiv' : 'Standby'} · $window',
                            style: mira.caption.copyWith(color: statusColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                        MiraSwitch(value: isArmed, onChanged: onArmedChanged),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _reading(mira, live, knots, color)),
                        const SizedBox(width: 12),
                        if (settled) _trailing(mira, live, color),
                      ],
                    ),
                    const SizedBox(height: 16),
                    WindSparkline(points: series, minimum: location.alarmThresholdKnots, now: now),
                    if (forecast != null) ...[
                      const SizedBox(height: 14),
                      _ForecastLine(forecast: forecast!),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                constraints: const BoxConstraints(minHeight: MiraSpace.touch),
                padding: const EdgeInsets.fromLTRB(MiraSpace.card, 0, 8, 0),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: mira.outline)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_outlined, size: 18, color: mira.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: mira.caption,
                          children: [
                            const TextSpan(text: 'Nächstes Prüffenster '),
                            TextSpan(
                              text: nextCheckLabel(location.activeWindow, now),
                              style: mira.caption.copyWith(
                                color: mira.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: mira.textTertiary, size: 22),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _verdict(MiraTheme mira, bool live, double? knots) {
    if (!settled) {
      return MiraPill(label: 'Wird geladen', color: mira.textSecondary);
    }
    if (!live || knots == null) {
      return MiraPill(
        label: 'Keine Live-Daten',
        color: mira.textSecondary,
        leading: Icon(Icons.cloud_off_rounded, size: 16, color: mira.textSecondary),
      );
    }
    final color = WindScale.barColor(knots);
    return MiraPill(label: WindScale.todayVerdict(knots), color: color);
  }

  Widget _reading(MiraTheme mira, bool live, double? knots, Color color) {
    final number = knots == null ? '––' : knots.toInt().toString();
    final updated = measurement == null ? null : measurementTime(measurement!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                number,
                style: mira.display.copyWith(
                  color: color,
                  letterSpacing: knots == null ? -3.3 : mira.display.letterSpacing,
                ),
              ),
              const SizedBox(width: 6),
              Text('kts', style: mira.title.copyWith(color: mira.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 2),
        if (!settled)
          Text('Wird geladen', style: mira.caption)
        else if (live && knots != null)
          Text(
            '${WindScale.capitalizedVerdict(knots)} · live ${updated == null ? '' : agoLabel(updated, now)}'.trim(),
            style: mira.caption,
          )
        else
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 16, color: MiraColors.windStrong),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  updated == null
                      ? 'Keine Live-Daten'
                      : 'Keine Live-Daten seit ${clockLabel(updated)}',
                  style: mira.caption,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _trailing(MiraTheme mira, bool live, Color color) {
    if (live && measurement != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DirectionArrow(direction: location.defaultDirection, color: color),
              const SizedBox(width: 8),
              Text(location.defaultDirection, style: mira.title),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: mira.caption,
              children: [
                const TextSpan(text: 'Böen '),
                TextSpan(
                  text: measurement!.gust.toInt().toString(),
                  style: mira.caption.copyWith(color: mira.textPrimary, fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: ' kts'),
              ],
            ),
          ),
        ],
      );
    }
    final last = measurement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (last != null) ...[
          Text('Letzter Wert', style: mira.caption),
          const SizedBox(height: 2),
          Text(
            '${last.baseWind.toInt()} kts · ${location.defaultDirection}',
            style: mira.title,
          ),
          const SizedBox(height: 8),
        ],
        _ReloadButton(reloading: reloading, onReload: onReload),
      ],
    );
  }
}

class _ReloadButton extends StatelessWidget {
  final bool reloading;
  final VoidCallback onReload;

  const _ReloadButton({required this.reloading, required this.onReload});

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    return TextButton(
      onPressed: reloading ? null : onReload,
      style: TextButton.styleFrom(
        foregroundColor: mira.accent,
        minimumSize: const Size(MiraSpace.touch, MiraSpace.touch),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: reloading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: mira.accent),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh_rounded, size: 16, color: mira.accent),
                const SizedBox(width: 4),
                Text(
                  'Erneut laden',
                  style: mira.caption.copyWith(color: mira.accent, fontWeight: FontWeight.w700),
                ),
              ],
            ),
    );
  }
}

class _ForecastLine extends StatelessWidget {
  final WindForecast forecast;

  const _ForecastLine({required this.forecast});

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: mira.surface2,
        borderRadius: BorderRadius.circular(MiraSpace.radiusInset),
      ),
      child: Row(
        children: [
          Icon(Icons.psychology_rounded, color: mira.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KI-Chance morgen ${forecast.windProbabilityPercent}%',
                  style: mira.caption.copyWith(color: mira.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${forecast.expectedWindMin}–${forecast.expectedWindMax} kts ${forecast.expectedDirection} · ${compactHourWindow(forecast.bestTimeWindow)}',
                  style: mira.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
