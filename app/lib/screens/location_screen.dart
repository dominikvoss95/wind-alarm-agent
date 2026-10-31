import 'dart:async';

import 'package:flutter/material.dart';

import '../models/location.dart';
import '../services/wind_api_service.dart';
import '../widgets/mira_scaffold.dart';
import '../widgets/spot_detail_view.dart';

class LocationScreen extends StatefulWidget {
  final WindLocation location;
  final bool monitoringArmed;

  const LocationScreen({super.key, required this.location, this.monitoringArmed = true});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  final Map<String, double> _windValues = {};
  final Map<String, double> _gustValues = {};
  bool _snoozeIfCalm = true;
  Timer? _pollingTimer;
  WindForecast? _forecast;
  WindMeasurement? _measurement;
  List<WindHistoryItem> _history = [];
  bool _fetchSettled = false;

  @override
  void initState() {
    super.initState();
    _fetchForecast();
    _startPolling();
  }

  Future<void> _fetchForecast() async {
    final apiLocId = widget.location.name.toLowerCase();
    final forecastData = await WindApiService.getForecast(apiLocId);
    if (!mounted) return;
    setState(() {
      _forecast = forecastData;
    });
  }

  void _startPolling() {
    _fetchMeasurement();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchMeasurement();
    });
  }

  Future<void> _fetchMeasurement() async {
    final apiLocId = widget.location.name.toLowerCase();
    final measurement = await WindApiService.getMeasurement(apiLocId);
    final historyData = await WindApiService.getHistory(apiLocId);
    if (!mounted) return;
    setState(() {
      _history = historyData;
      _measurement = measurement;
      _fetchSettled = true;
      if (measurement != null) {
        if (measurement.webcams != null) {
          measurement.webcams!.forEach((camId, data) {
            if (data is! Map) {
              return;
            }
            final wind = data['base_wind'] ?? data['base_wind_knots'] ?? 0;
            final gust = data['gust'] ?? data['gust_knots'] ?? 0;
            _windValues[camId] = wind is num ? wind.toDouble() : 0.0;
            _gustValues[camId] = gust is num ? gust.toDouble() : 0.0;
          });
        } else {
          final locData = appLocations[widget.location]!;
          final firstCamId = locData.webcams.first.url
              .replaceAll(RegExp(r'/+$'), '')
              .split('/')
              .last
              .toLowerCase();
          _windValues[firstCamId] = measurement.baseWind;
          _gustValues[firstCamId] = measurement.gust;
        }
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locData = appLocations[widget.location]!;
    final camId = locData.webcams.first.url.replaceAll(RegExp(r'/+$'), '').split('/').last.toLowerCase();
    final now = DateTime.now();
    final wind = _windValues.containsKey(camId)
        ? _windValues[camId]
        : _measurement?.baseWind;
    final gust = _gustValues.containsKey(camId) ? _gustValues[camId] : _measurement?.gust;
    return MiraScaffold(
      padTop: false,
      index: 1,
      onChanged: (index) => Navigator.pop(context, index),
      body: SpotDetailView(
        location: locData,
        monitoringArmed: widget.monitoringArmed,
        fetchSettled: _fetchSettled,
        measurement: _measurement,
        windKnots: _measurement == null ? null : wind,
        gustKnots: _measurement == null ? null : gust,
        history: _history,
        forecast: _forecast,
        snoozeIfCalm: _snoozeIfCalm,
        onSnooze: (value) => setState(() => _snoozeIfCalm = value),
        onBack: () => Navigator.pop(context),
        now: now,
      ),
    );
  }
}
