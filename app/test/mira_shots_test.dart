import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 31, 16, 48);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Plus Jakarta Sans');
    for (final file in const [
      'assets/fonts/PlusJakartaSans-Regular.ttf',
      'assets/fonts/PlusJakartaSans-Medium.ttf',
      'assets/fonts/PlusJakartaSans-SemiBold.ttf',
      'assets/fonts/PlusJakartaSans-Bold.ttf',
      'assets/fonts/PlusJakartaSans-ExtraBold.ttf',
    ]) {
      loader.addFont(rootBundle.load(file));
    }
    await loader.load();
    final iconFile = File('/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (iconFile.existsSync()) {
      final icons = iconFile.readAsBytesSync();
      final iconLoader = FontLoader('MaterialIcons')
        ..addFont(Future.value(icons.buffer.asByteData(icons.offsetInBytes, icons.lengthInBytes)));
      await iconLoader.load();
    }
  });
  final history = _day(now);

  testWidgets('capture mira screens', (tester) async {
    await _shot(
      tester,
      'screen-a-start',
      HomeDashboard(
        now: now,
        spots: [
          _spot(appLocations[WindLocation.kochelsee]!, now, wind: 14, gust: 19, history: history),
          _spot(appLocations[WindLocation.gardasee]!, now, wind: 18, gust: 24, history: history, armed: true),
        ],
      ),
    );

    await _shot(
      tester,
      'screen-a-fallback',
      HomeDashboard(
        now: now,
        spots: [
          _spot(
            appLocations[WindLocation.kochelsee]!,
            now,
            wind: 9,
            gust: 12,
            history: history,
            updated: now.subtract(const Duration(hours: 10, minutes: 36)),
          ),
          _spot(appLocations[WindLocation.gardasee]!, now, wind: 18, gust: 24, history: history),
        ],
      ),
    );

    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _shot(
      tester,
      'screen-b-detail',
      SpotDetailView(
        location: appLocations[WindLocation.kochelsee]!,
        monitoringArmed: true,
        fetchSettled: true,
        measurement: _measurement(now.subtract(const Duration(minutes: 3))),
        windKnots: 14,
        gustKnots: 19,
        history: history,
        forecast: _forecast(),
        snoozeIfCalm: true,
        onSnooze: (_) {},
        onBack: () {},
        now: now,
        scrollController: controller,
      ),
      padTop: false,
      index: 1,
    );

    final max = controller.position.maxScrollExtent;
    controller.jumpTo(560.clamp(0, max).toDouble());
    await tester.pump();
    await _capture(tester, 'screen-c-prognose');

    await _shot(
      tester,
      'screen-d1-empty',
      ActivityDashboard(
        loading: false,
        alarms: const [],
        monitoredCaption: monitoredCaption(),
        onSendTest: () {},
      ),
      index: 2,
    );
    await _shot(
      tester,
      'screen-d2-loading',
      const ActivityDashboard(
        loading: true,
        alarms: [],
        monitoredCaption: '',
        onSendTest: _noop,
      ),
      index: 2,
    );
    await _shot(
      tester,
      'screen-d3-list',
      ActivityDashboard(
        loading: false,
        alarms: [
          AlarmEntry(
            locationId: 'gardasee',
            locationName: 'Gardasee',
            direction: 'N',
            at: DateTime(2026, 10, 31, 6, 41),
            knots: 22,
            gust: 26,
          ),
          AlarmEntry(
            locationId: 'kochelsee',
            locationName: 'Kochelsee',
            direction: 'SW',
            at: DateTime(2026, 10, 29, 5, 12),
            knots: 15,
            gust: 19,
          ),
          AlarmEntry(
            locationId: 'gardasee',
            locationName: 'Gardasee',
            direction: 'N',
            at: DateTime(2026, 10, 26, 5, 48),
            knots: 27,
            gust: 31,
          ),
        ],
        monitoredCaption: monitoredCaption(),
        onSendTest: () {},
      ),
      index: 2,
    );
    await _shot(
      tester,
      'screen-e-setup',
      SetupDashboard(
        status: const AlarmChannelStatus(
          criticalTitle: 'Kritische Alarme erlaubt',
          criticalSubtitle: 'Klingeln auch bei „Nicht stören“',
          showCriticalCheck: true,
          toneSubtitle: 'Alarmton der App',
          silentSubtitle: 'Klingelt auch bei stummem Gerät',
          silentValue: 'Aktiv',
        ),
        now: now,
        lastTestAt: DateTime(2026, 10, 31, 9, 14),
        onTestKochelsee: () {},
        onTestGardasee: () {},
      ),
      index: 3,
    );
  });
}

void _noop() {}

Future<void> _shot(
  WidgetTester tester,
  String name,
  Widget body, {
  int index = 0,
  bool padTop = true,
}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: RepaintBoundary(
        key: const ValueKey('mira-shot'),
        child: MiraScaffold(index: index, onChanged: (_) {}, padTop: padTop, body: body),
      ),
    ),
  );
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump();
  await _capture(tester, name);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('mira-shot')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final preferred = Directory('/opt/cursor/artifacts/mira-v1');
    Directory dir;
    try {
      await preferred.create(recursive: true);
      dir = preferred;
    } catch (_) {
      dir = await Directory.systemTemp.createTemp('mira-v1');
    }
    final file = File('${dir.path}/$name.png');
    await file.writeAsBytes(data!.buffer.asUint8List());
  });
}

HomeSpotData _spot(
  LocationData location,
  DateTime now, {
  required double wind,
  required double gust,
  required List<WindHistoryItem> history,
  DateTime? updated,
  bool armed = true,
}) {
  return HomeSpotData(
    location: location,
    measurement: _measurement(updated ?? now.subtract(const Duration(minutes: 3)), wind: wind, gust: gust),
    settled: true,
    armed: armed,
    reloading: false,
    forecast: _forecast(location.id == 'gardasee'),
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

List<WindHistoryItem> _day(DateTime now) {
  final start = DateTime(now.year, now.month, now.day, 6);
  const values = [4.0, 6, 7, 9, 10, 11, 13, 15, 16, 14, 12, 9, 8, 6, 5];
  return [
    for (var index = 0; index < values.length; index++)
      WindHistoryItem(
        observedAt: start.add(Duration(hours: index)),
        baseWind: values[index].toDouble(),
        gust: values[index].toDouble() + 5,
      ),
  ];
}

WindForecast _forecast([bool garda = false]) {
  if (garda) {
    return WindForecast(
      summary: 'Starker Pelér am Vormittag.',
      windProbabilityPercent: 85,
      confidence: 'high',
      expectedWindMin: 14,
      expectedWindMax: 22,
      expectedDirection: 'N',
      bestTimeWindow: '07:00 - 11:00',
      modelConsensus: 'Hohe Übereinstimmung der Modelle.',
      sourcesAnalyzed: const [],
      updatedAt: '2026-10-31T12:00:00Z',
    );
  }
  return WindForecast(
    summary: 'Mäßiger Föhnwind am Nachmittag wahrscheinlich, da der Patscherkofel anzieht.',
    windProbabilityPercent: 65,
    confidence: 'medium',
    expectedWindMin: 10,
    expectedWindMax: 18,
    expectedDirection: 'S',
    bestTimeWindow: '14:00 - 18:00',
    modelConsensus: '3 von 4 Modellen erwarten Südwind',
    sourcesAnalyzed: [ForecastSource(name: 'Windfinder', summary: 'Südwind.')],
    updatedAt: '2026-10-31T12:00:00Z',
  );
}
