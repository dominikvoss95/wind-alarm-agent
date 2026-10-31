import 'package:flutter/material.dart';

import '../models/location.dart';
import '../services/wind_api_service.dart';
import '../theme/app_theme.dart';
import '../theme/wind_scale.dart';
import '../utils/spot_presentation.dart';
import 'compass.dart';
import 'criteria_item.dart';
import 'forecast_card.dart';
import 'mira_controls.dart';
import 'wave_header.dart';
import 'wind_charts.dart';

class SpotDetailView extends StatefulWidget {
  final LocationData location;
  final bool monitoringArmed;
  final bool fetchSettled;
  final WindMeasurement? measurement;
  final double? windKnots;
  final double? gustKnots;
  final List<WindHistoryItem> history;
  final WindForecast? forecast;
  final bool snoozeIfCalm;
  final ValueChanged<bool> onSnooze;
  final VoidCallback onBack;
  final DateTime now;
  final ScrollController? scrollController;

  const SpotDetailView({
    super.key,
    required this.location,
    required this.monitoringArmed,
    required this.fetchSettled,
    required this.measurement,
    required this.windKnots,
    required this.gustKnots,
    required this.history,
    required this.forecast,
    required this.snoozeIfCalm,
    required this.onSnooze,
    required this.onBack,
    required this.now,
    this.scrollController,
  });

  @override
  State<SpotDetailView> createState() => _SpotDetailViewState();
}

class _SpotDetailViewState extends State<SpotDetailView> {
  late final ScrollController _scroll;
  late final bool _ownsController;
  final _criteriaKey = GlobalKey();
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.scrollController == null;
    _scroll = widget.scrollController ?? ScrollController();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    if (_ownsController) _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final collapsed = _scroll.hasClients && _scroll.offset > 120;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  void _scrollToCriteria() {
    final target = _criteriaKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 350),
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    final top = MediaQuery.paddingOf(context).top;
    final live = widget.fetchSettled &&
        widget.measurement != null &&
        widget.windKnots != null &&
        readingIsFresh(widget.measurement!, widget.now);
    final window = displayWindow(widget.location.activeWindow);
    final status = widget.monitoringArmed ? 'Überwachung aktiv · $window' : 'Standby · $window';
    return Stack(
      children: [
        CustomScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: SpotHero(
                asset: widget.location.heroImageUrl,
                foreground: Padding(
                  padding: const EdgeInsets.fromLTRB(MiraSpace.screen, 0, MiraSpace.screen, 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.location.name, style: mira.h1),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: widget.monitoringArmed ? mira.accent : mira.textSecondary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              status,
                              style: mira.caption.copyWith(
                                color: widget.monitoringArmed ? mira.accent : mira.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(MiraSpace.screen, 8, MiraSpace.screen, miraBottomInset(context)),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _WindCard(
                    location: widget.location,
                    settled: widget.fetchSettled,
                    live: live,
                    knots: widget.windKnots,
                    gust: widget.gustKnots,
                    measurement: widget.measurement,
                    now: widget.now,
                  ),
                  const SizedBox(height: MiraSpace.gap),
                  MiraCard(
                    child: HourlyWindChart(
                      bins: hourlyBinsToday(widget.history, widget.now),
                      minimum: widget.location.alarmThresholdKnots,
                      now: widget.now,
                    ),
                  ),
                  if (widget.forecast != null) ...[
                    const SizedBox(height: MiraSpace.gap),
                    ForecastCard(forecast: widget.forecast!, now: widget.now),
                  ],
                  const SizedBox(height: MiraSpace.section),
                  KeyedSubtree(
                    key: _criteriaKey,
                    child: CriteriaGroup(
                      title: 'Überwachung & Kriterien',
                      rows: _criteriaRows(widget.location),
                    ),
                  ),
                  if (widget.location.id == 'gardasee') ...[
                    const SizedBox(height: MiraSpace.section),
                    CriteriaGroup(
                      title: 'Morgenthermik',
                      rows: _morningRows(widget.location),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: mira.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Änderungen gelten ab dem nächsten Prüffenster.',
                          style: mira.caption,
                        ),
                      ),
                    ],
                  ),
                ]),
              ),
            ),
          ],
        ),
        if (_collapsed)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _CollapsedBar(
              top: top,
              title: widget.location.name,
              status: status,
              armed: widget.monitoringArmed,
              onBack: widget.onBack,
            ),
          )
        else
          Positioned(
            top: top + 8,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                MiraCircleButton(
                  icon: Icons.arrow_back_rounded,
                  semanticLabel: 'Zurück',
                  onPressed: widget.onBack,
                ),
                MiraCircleButton(
                  icon: Icons.edit_outlined,
                  semanticLabel: 'Zu den Kriterien',
                  onPressed: _scrollToCriteria,
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<CriteriaRow> _criteriaRows(LocationData location) {
    final directions = '${location.defaultDirection}, S, SE';
    return [
      CriteriaRow(
        icon: Icons.schedule_rounded,
        title: 'Prüf-Zeitfenster',
        subtitle: 'Prüfung ${location.nextCheck}',
        value: displayWindow(location.activeWindow),
      ),
      CriteriaRow(
        icon: Icons.air_rounded,
        title: 'Min. Windstärke',
        subtitle: 'Alarm ab diesem Wert',
        value: '${location.alarmThresholdKnots.round()} kts',
      ),
      CriteriaRow(
        icon: Icons.explore_rounded,
        title: 'Windrichtung',
        subtitle: directions,
        sectors: sectorsOf(directions),
      ),
    ];
  }

  List<CriteriaRow> _morningRows(LocationData location) {
    return [
      const CriteriaRow(
        icon: Icons.schedule_rounded,
        title: 'Prüfzeitraum',
        subtitle: 'Morgensession',
        value: '5:00–9:00',
      ),
      CriteriaRow(
        icon: Icons.air_rounded,
        title: 'Wind-Schwellenwert',
        subtitle: 'Minimum für Ora oder Pelér',
        value: '${location.alarmThresholdKnots.round()} kts',
      ),
      CriteriaRow(
        icon: Icons.bedtime_outlined,
        title: 'Schlummern wenn ruhig',
        subtitle: 'Weiter schlafen wenn kein Wind',
        switchValue: widget.snoozeIfCalm,
        onSwitch: widget.onSnooze,
        showChevron: false,
      ),
    ];
  }
}

class _CollapsedBar extends StatelessWidget {
  final double top;
  final String title;
  final String status;
  final bool armed;
  final VoidCallback onBack;

  const _CollapsedBar({
    required this.top,
    required this.title,
    required this.status,
    required this.armed,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    return Container(
      padding: EdgeInsets.only(top: top),
      decoration: BoxDecoration(
        color: mira.bg.withValues(alpha: 0.92),
        border: Border(bottom: BorderSide(color: mira.outline)),
      ),
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              MiraCircleButton(
                icon: Icons.arrow_back_rounded,
                semanticLabel: 'Zurück',
                bordered: true,
                onPressed: onBack,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: mira.title),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mira.caption.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: armed ? mira.accent : mira.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindCard extends StatelessWidget {
  final LocationData location;
  final bool settled;
  final bool live;
  final double? knots;
  final double? gust;
  final WindMeasurement? measurement;
  final DateTime now;

  const _WindCard({
    required this.location,
    required this.settled,
    required this.live,
    required this.knots,
    required this.gust,
    required this.measurement,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    final color = !live || knots == null ? mira.textSecondary : WindScale.numberColor(knots!);
    final bar = !live || knots == null ? mira.textSecondary : WindScale.barColor(knots!);
    final updated = measurement == null ? null : measurementTime(measurement!);
    final source = location.webcams.isEmpty ? '' : location.webcams.first.sourceDomain;
    return MiraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const MiraLabel('Aktueller Wind'),
              const Spacer(),
              if (!settled)
                MiraPill(label: 'Wird geladen', color: mira.textSecondary)
              else if (!live || knots == null)
                MiraPill(
                  label: 'Keine Live-Daten',
                  color: mira.textSecondary,
                  leading: Icon(Icons.cloud_off_rounded, size: 16, color: mira.textSecondary),
                )
              else
                MiraPill(label: WindScale.capitalizedVerdict(knots!), color: bar),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
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
                            live && knots != null ? knots!.toInt().toString() : '––',
                            style: mira.display.copyWith(color: color),
                          ),
                          const SizedBox(width: 6),
                          Text('kts', style: mira.title.copyWith(color: mira.textSecondary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (live && knots != null)
                      Text.rich(
                        TextSpan(
                          style: mira.body.copyWith(color: mira.textSecondary),
                          children: [
                            const TextSpan(text: 'Böen '),
                            TextSpan(
                              text: '${(gust ?? 0).toInt()} kts',
                              style: mira.body.copyWith(color: mira.textPrimary, fontWeight: FontWeight.w700),
                            ),
                            TextSpan(text: ' · aus ${location.defaultDirection}'),
                          ],
                        ),
                      )
                    else if (measurement != null)
                      Text(
                        updated == null
                            ? 'Letzter Wert ${(knots ?? measurement!.baseWind).toInt()} kts · ${location.defaultDirection}'
                            : 'Keine Live-Daten seit ${clockLabel(updated)} · letzter Wert ${(knots ?? measurement!.baseWind).toInt()} kts',
                        style: mira.caption,
                      )
                    else
                      Text(settled ? 'Keine Live-Daten' : 'Wird geladen', style: mira.caption),
                  ],
                ),
              ),
              if (live && knots != null) CompassDial(direction: location.defaultDirection, color: bar),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: live ? MiraColors.windGood : mira.textTertiary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  live
                      ? '$source · live · ${updated == null ? 'jetzt' : agoLabel(updated, now)}'
                      : '$source · keine Live-Daten',
                  style: mira.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
