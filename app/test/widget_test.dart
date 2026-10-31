import 'package:app/main.dart';
import 'package:app/models/location.dart';
import 'package:app/services/wind_api_service.dart';
import 'package:app/theme/app_theme.dart';
import 'package:app/utils/alarm_history.dart';
import 'package:app/utils/alarm_status.dart';
import 'package:app/widgets/activity_dashboard.dart';
import 'package:app/widgets/home_dashboard.dart';
import 'package:app/widgets/mira_scaffold.dart';
import 'package:app/widgets/setup_dashboard.dart';
import 'package:app/widgets/spot_detail_view.dart';
import 'package:app/widgets/wave_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 31, 16, 48);

  testWidgets('home shows a live verdict and a missing-data fallback', (tester) async {
    await _pump(
      tester,
      MiraScaffold(
        index: 0,
        onChanged: (_) {},
        body: HomeDashboard(
          now: now,
          spots: [
            _spot(
              appLocations[WindLocation.kochelsee]!,
              measurement: _measurement(now.subtract(const Duration(hours: 3)), wind: 9, gust: 12),
              history: [_point(now.subtract(const Duration(hours: 2)), 11)],
            ),
            _spot(
              appLocations[WindLocation.gardasee]!,
              measurement: _measurement(now.subtract(const Duration(minutes: 3)), wind: 18, gust: 24),
              history: [_point(now.subtract(const Duration(hours: 1)), 16)],
              armed: false,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Guten Tag, Dominik.'), findsOneWidget);
    expect(find.text('1 von 2 Spots ohne Live-Daten'), findsOneWidget);
    expect(find.text('Keine Live-Daten'), findsWidgets);
    expect(find.text('Erneut laden'), findsOneWidget);
    expect(find.text('Heute gut'), findsOneWidget);
    expect(find.text('––'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('LETZTE 12 STD.'), findsWidgets);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Orte'), findsOneWidget);
    expect(find.text('Verlauf'), findsOneWidget);
    expect(find.text('Setup'), findsOneWidget);
  });

  testWidgets('detail degrades without hourly samples and keeps the forecast title', (tester) async {
    await _pump(
      tester,
      MiraScaffold(
        padTop: false,
        index: 1,
        onChanged: (_) {},
        body: SpotDetailView(
          location: appLocations[WindLocation.kochelsee]!,
          monitoringArmed: true,
          fetchSettled: true,
          measurement: _measurement(now.subtract(const Duration(minutes: 3))),
          windKnots: 14,
          gustKnots: 19,
          history: const [],
          forecast: _forecast(),
          snoozeIfCalm: true,
          onSnooze: (_) {},
          onBack: () {},
          now: now,
        ),
      ),
    );

    expect(find.text('KI-Prognose'), findsOneWidget);
    expect(find.text('Konfidenz mittel'), findsOneWidget);
    expect(find.text('Keine Stundenwerte für heute'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Überwachung & Kriterien'), 300);
    expect(find.text('Überwachung & Kriterien'), findsOneWidget);
    expect(find.text('Prüfung alle 5 Min.'), findsOneWidget);
    expect(find.text('Modell-Konsens'), findsOneWidget);
    expect(find.text('Morgenthermik'), findsNothing);

    await tester.ensureVisible(find.text('Modell-Konsens'));
    await tester.pump();
    await tester.tap(find.text('Modell-Konsens'));
    await tester.pump();
    expect(find.text('Windfinder Superforecast'), findsOneWidget);
  });

  testWidgets('activity empty, loading and list states', (tester) async {
    await _pump(
      tester,
      MiraScaffold(
        index: 2,
        onChanged: (_) {},
        body: ActivityDashboard(
          loading: false,
          alarms: const [],
          monitoredCaption: monitoredCaption(),
          onSendTest: () {},
        ),
      ),
    );
    expect(find.text('Noch keine Alarme'), findsOneWidget);
    expect(find.text('Test-Alarm senden'), findsOneWidget);
    expect(find.text('Verlauf wird geladen …'), findsNothing);
    expect(find.textContaining('Überwacht:'), findsOneWidget);

    await _pump(
      tester,
      MiraScaffold(
        index: 2,
        onChanged: (_) {},
        body: const ActivityDashboard(
          loading: true,
          alarms: [],
          monitoredCaption: '',
          onSendTest: _noop,
        ),
      ),
    );
    expect(find.text('Verlauf wird geladen …'), findsOneWidget);
    expect(find.text('Noch keine Alarme'), findsNothing);

    await _pump(
      tester,
      MiraScaffold(
        index: 2,
        onChanged: (_) {},
        body: ActivityDashboard(
          loading: false,
          alarms: [
            AlarmEntry(
              locationId: 'gardasee',
              locationName: 'Gardasee',
              direction: 'N',
              at: now,
              knots: 22,
              gust: 26,
            ),
          ],
          monitoredCaption: monitoredCaption(),
          onSendTest: () {},
        ),
      ),
    );
    expect(find.text('Gardasee'), findsWidgets);
    expect(find.text('Alle'), findsOneWidget);
    expect(find.textContaining('1 Alarm'), findsOneWidget);
  });

  testWidgets('setup uses one accent and names this device', (tester) async {
    await _pump(
      tester,
      MiraScaffold(
        index: 3,
        onChanged: (_) {},
        body: SetupDashboard(
          status: AlarmChannelStatus.unsupported,
          now: now,
          onTestKochelsee: () {},
          onTestGardasee: () {},
        ),
      ),
    );
    expect(find.text('Setup & Test'), findsOneWidget);
    expect(find.textContaining('auf diesem Gerät'), findsOneWidget);
    expect(find.text('Kochelsee-Alarm testen'), findsOneWidget);
    expect(find.text('Gardasee-Alarm testen'), findsOneWidget);
    expect(find.text('Auf diesem System nicht verfügbar'), findsOneWidget);
    expect(find.text('iPhone'), findsNothing);
  });

  testWidgets('a missing hero image stays on the wave fallback', (tester) async {
    await _pump(
      tester,
      const SpotHero(asset: 'assets/images/does-not-exist.png', height: 200),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('app shell builds the start tab', (tester) async {
    await tester.pumpWidget(const WindAlarmApp());
    await tester.pump();
    expect(find.textContaining('Dominik'), findsOneWidget);
    expect(find.text('Kochelsee'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 12));
  });
}

void _noop() {}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: child,
    ),
  );
  await tester.pump();
}

HomeSpotData _spot(
  LocationData location, {
  WindMeasurement? measurement,
  List<WindHistoryItem> history = const [],
  bool armed = true,
}) {
  return HomeSpotData(
    location: location,
    measurement: measurement,
    settled: true,
    armed: armed,
    reloading: false,
    forecast: _forecast(),
    history: history,
    onArmed: (_) {},
    onOpen: () {},
    onReload: () {},
  );
}

WindMeasurement _measurement(DateTime updated, {double wind = 14, double gust = 19}) {
  return WindMeasurement(
    location: 'spot',
    baseWind: wind,
    gust: gust,
    fetchStatus: 'success',
    isFresh: true,
    thresholdExceeded: false,
    errorMessage: '',
    updatedAt: updated.toIso8601String(),
  );
}

WindHistoryItem _point(DateTime at, double knots) {
  return WindHistoryItem(observedAt: at, baseWind: knots, gust: knots + 4);
}

WindForecast _forecast() {
  return WindForecast(
    summary: 'Mäßiger Föhnwind am Nachmittag wahrscheinlich.',
    windProbabilityPercent: 65,
    confidence: 'medium',
    expectedWindMin: 10,
    expectedWindMax: 18,
    expectedDirection: 'S',
    bestTimeWindow: '14:00 - 18:00',
    modelConsensus: '3 von 4 Modellen erwarten Südwind',
    sourcesAnalyzed: [
      ForecastSource(name: 'Windfinder Superforecast', summary: 'Südwind ab Mittag.'),
    ],
    updatedAt: '2026-10-31T14:00:00Z',
  );
}
