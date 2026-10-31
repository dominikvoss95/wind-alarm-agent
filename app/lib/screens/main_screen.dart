import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/location.dart';
import '../services/wind_api_service.dart';
import '../utils/alarm_history.dart';
import '../utils/alarm_status.dart';
import '../utils/alarm_utils.dart';
import '../widgets/activity_dashboard.dart';
import '../widgets/home_dashboard.dart';
import '../widgets/mira_scaffold.dart';
import '../widgets/places_dashboard.dart';
import '../widgets/setup_dashboard.dart';
import 'location_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<bool> _isMonitoringArmed = [true, false];
  final Map<String, WindMeasurement> _liveWindSummary = {};
  final Map<String, WindForecast> _forecastSummary = {};
  final Map<String, List<WindHistoryItem>> _history = {};
  final Set<String> _reloading = {};
  Timer? _pollingTimer;
  bool _measurementsSettled = false;
  bool _activityLoading = true;
  AlarmChannelStatus _alarmStatus = AlarmChannelStatus.checking;
  DateTime? _lastTestAt;

  @override
  void initState() {
    super.initState();
    _fetchForecasts();
    _loadHistory();
    _loadAlarmStatus();
    _startPolling();
  }

  Future<void> _toggleMonitoring(int index, bool isArmed, LocationData data) async {
    setState(() {
      _isMonitoringArmed[index] = isArmed;
    });

    try {
      if (isArmed) {
        await FirebaseMessaging.instance.subscribeToTopic(data.fcmTopic);
        debugPrint('Subscribed to topic: ${data.fcmTopic}');
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(data.fcmTopic);
        debugPrint('Unsubscribed from topic: ${data.fcmTopic}');
      }
    } catch (error) {
      debugPrint('Error updating topic subscription: $error');
    }
  }

  Future<void> _fetchForecasts() async {
    for (final location in WindLocation.values) {
      final forecast = await WindApiService.getForecast(location.name.toLowerCase());
      if (forecast != null && mounted) {
        setState(() {
          _forecastSummary[location.name] = forecast;
        });
      }
    }
  }

  Future<void> _loadHistory() async {
    final next = <String, List<WindHistoryItem>>{};
    for (final location in WindLocation.values) {
      next[location.name] = await WindApiService.getHistory(location.name.toLowerCase());
      if (!mounted) return;
    }
    setState(() {
      _history
        ..clear()
        ..addAll(next);
      _activityLoading = false;
    });
  }

  Future<void> _loadAlarmStatus() async {
    final status = await AlarmChannelStatus.resolve();
    if (mounted) setState(() => _alarmStatus = status);
  }

  void _startPolling() {
    _fetchMeasurements();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchMeasurements();
    });
  }

  Future<void> _fetchMeasurements() async {
    final measurements = await WindApiService.getAllMeasurements();
    if (!mounted) return;
    setState(() {
      _measurementsSettled = true;
      measurements.forEach((key, measurement) {
        if (measurement != null) {
          try {
            final location = WindLocation.values.firstWhere(
              (item) => item.name.toLowerCase() == key.toLowerCase(),
            );
            _liveWindSummary[location.name] = measurement;
          } catch (_) {}
        }
      });
    });
  }

  Future<void> _reloadLocation(WindLocation location) async {
    setState(() => _reloading.add(location.name));
    final measurement = await WindApiService.getMeasurement(location.name.toLowerCase());
    final history = await WindApiService.getHistory(location.name.toLowerCase());
    if (!mounted) return;
    setState(() {
      _reloading.remove(location.name);
      _measurementsSettled = true;
      if (measurement != null) _liveWindSummary[location.name] = measurement;
      _history[location.name] = history;
    });
  }

  Future<void> _openLocation(WindLocation location) async {
    final index = WindLocation.values.indexOf(location);
    final next = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationScreen(
          location: location,
          monitoringArmed: index >= 0 && index < _isMonitoringArmed.length && _isMonitoringArmed[index],
        ),
      ),
    );
    if (next != null && mounted) {
      setState(() => _currentIndex = next);
    }
  }

  Future<void> _sendTest(String locationName, int hour, int minute) async {
    await triggerAlarmLogic(hour: hour, minute: minute, locationName: locationName);
    if (mounted) setState(() => _lastTestAt = DateTime.now());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  List<HomeSpotData> _spots(DateTime now) {
    return WindLocation.values.asMap().entries.map((entry) {
      final index = entry.key;
      final location = entry.value;
      final data = appLocations[location]!;
      return HomeSpotData(
        location: data,
        measurement: _liveWindSummary[location.name],
        settled: _measurementsSettled,
        armed: _isMonitoringArmed[index],
        reloading: _reloading.contains(location.name),
        forecast: _forecastSummary[location.name],
        history: _history[location.name] ?? const [],
        onArmed: (value) => _toggleMonitoring(index, value, data),
        onOpen: () => _openLocation(location),
        onReload: () => _reloadLocation(location),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return MiraScaffold(
      index: _currentIndex,
      onChanged: (index) => setState(() => _currentIndex = index),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeDashboard(now: now, spots: _spots(now)),
          PlacesDashboard(armed: _isMonitoringArmed, onOpen: _openLocation),
          ActivityDashboard(
            loading: _activityLoading,
            alarms: alarmsFromHistory(historyByLocation: _history, now: now),
            monitoredCaption: monitoredCaption(),
            onSendTest: () => _sendTest('KOCHELSEE', 6, 15),
          ),
          SetupDashboard(
            status: _alarmStatus,
            now: now,
            lastTestAt: _lastTestAt,
            onTestKochelsee: () => _sendTest('KOCHELSEE', 6, 15),
            onTestGardasee: () => _sendTest('GARDASEE', 8, 45),
          ),
        ],
      ),
    );
  }
}
