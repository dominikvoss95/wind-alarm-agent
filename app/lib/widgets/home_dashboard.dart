import 'package:flutter/material.dart';

import '../models/location.dart';
import '../services/wind_api_service.dart';
import '../theme/app_theme.dart';
import '../theme/wind_scale.dart';
import '../utils/spot_presentation.dart';
import 'location_card.dart';
import 'mira_controls.dart';

class HomeSpotData {
  final LocationData location;
  final WindMeasurement? measurement;
  final bool settled;
  final bool armed;
  final bool reloading;
  final WindForecast? forecast;
  final List<WindHistoryItem> history;
  final ValueChanged<bool> onArmed;
  final VoidCallback onOpen;
  final VoidCallback onReload;

  const HomeSpotData({
    required this.location,
    required this.measurement,
    required this.settled,
    required this.armed,
    required this.reloading,
    required this.forecast,
    required this.history,
    required this.onArmed,
    required this.onOpen,
    required this.onReload,
  });
}

class HomeDashboard extends StatelessWidget {
  final DateTime now;
  final List<HomeSpotData> spots;

  const HomeDashboard({super.key, required this.now, required this.spots});

  @override
  Widget build(BuildContext context) {
    final mira = context.mira;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(MiraSpace.screen, MiraSpace.screen, MiraSpace.screen, miraBottomInset(context)),
      children: [
        MiraLabel(homeDateLabel(now)),
        const SizedBox(height: 6),
        Text('${greetingFor(now)}, Dominik.', style: mira.h1),
        const SizedBox(height: 4),
        Text(_summary(), style: mira.body.copyWith(color: mira.textSecondary)),
        const SizedBox(height: 24),
        for (var index = 0; index < spots.length; index++) ...[
          if (index > 0) const SizedBox(height: MiraSpace.gap),
          LocationOverviewCard(
            location: spots[index].location,
            measurement: spots[index].measurement,
            settled: spots[index].settled,
            isArmed: spots[index].armed,
            onArmedChanged: spots[index].onArmed,
            onTap: spots[index].onOpen,
            onReload: spots[index].onReload,
            reloading: spots[index].reloading,
            forecast: spots[index].forecast,
            history: spots[index].history,
            now: now,
          ),
        ],
      ],
    );
  }

  String _summary() {
    if (spots.isEmpty || spots.any((spot) => !spot.settled)) {
      return 'Spots werden geprüft';
    }
    final missing = spots.where((spot) {
      final measurement = spot.measurement;
      return measurement == null || !readingIsFresh(measurement, now);
    }).length;
    if (missing > 0) {
      return '$missing von ${spots.length} Spots ohne Live-Daten';
    }
    final rideable = spots.where((spot) => WindScale.isRideable(spot.measurement!.baseWind)).length;
    return '$rideable von ${spots.length} Spots fahrbar';
  }
}
