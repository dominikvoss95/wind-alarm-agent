import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/location.dart';
import '../theme/app_theme.dart';
import '../widgets/wind_trend_chart.dart';
import '../widgets/criteria_item.dart';
import '../services/wind_api_service.dart';
import '../widgets/forecast_card.dart';

class LocationScreen extends StatefulWidget {
  final WindLocation location;

  const LocationScreen({super.key, required this.location});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  final Map<String, double> _windValues = {};
  final Map<String, double> _gustValues = {};
  bool _snoozeIfCalm = true;
  Timer? _pollingTimer;
  WindForecast? _forecast;

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

  List<WindHistoryItem> _history = [];
  bool _readingIsFresh = false;

  Future<void> _fetchMeasurement() async {
    final apiLocId = widget.location.name.toLowerCase();
    final measurement = await WindApiService.getMeasurement(apiLocId);
    final historyData = await WindApiService.getHistory(apiLocId);
    if (!mounted) return;
    setState(() {
      _history = historyData;
      _readingIsFresh = measurement != null && measurement.isCurrentlyFresh;
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

  List<double> _generateTrendData(double current) {
    // Generate some mock history based on the current value to make it look alive
    if (current == 0) return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    return [
      current * 0.4,
      current * 0.5,
      current * 0.45,
      current * 0.6,
      current * 0.8,
      current * 0.95,
      current,
      current * 1.1,
      current * 1.05,
      current * 0.9,
      current * 0.85,
      current * 0.8,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final locData = appLocations[widget.location]!;
    // Use the first webcam as the primary source for this view
    final camId = locData.webcams.first.url.replaceAll(RegExp(r'/+$'), '').split('/').last.toLowerCase();
    final wind = _windValues[camId] ?? 0.0;
    
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          _buildHeroSection(locData),
          _buildContent(locData, wind),
          _buildBackButton(),
        ],
      ),
    );
  }

  Widget _buildHeroSection(LocationData loc) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 480,
      child: Stack(
        children: [
          Image.asset(
            loc.heroImageUrl,
            fit: BoxFit.cover,
            height: 480,
            width: double.infinity,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  AppColors.backgroundDark,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackButton() {
    return Positioned(
      top: 60,
      left: 24,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildContent(LocationData loc, double wind) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 300, bottom: 40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.name,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 40,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: "ÜBERWACHUNG AKTIV",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: loc.accentColor,
                      letterSpacing: 1.0,
                    ),
                  ),
                  TextSpan(
                    text: " • ${loc.activeWindow}",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: loc.accentColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildCurrentWindCard(loc, wind),
            if (_forecast != null) ...[
              const SizedBox(height: 32),
              ForecastCard(
                forecast: _forecast!,
                accentColor: loc.accentColor,
              ),
            ],
            const SizedBox(height: 40),
            Text(
              "Überwachung & Kriterien",
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            CriteriaItem(
              label: "Prüf-Zeitfenster",
              subLabel: "Checks starten um ${loc.nextCheck}",
              value: loc.activeWindow,
            ),
            CriteriaItem(
              label: "Min. Windstärke",
              subLabel: "Alarm auslösen ab",
              value: "${loc.alarmThresholdKnots.round()} kts",
            ),
            CriteriaItem(
              label: "Windrichtung",
              subLabel: "Nur spezifische Sektoren",
              value: "${loc.defaultDirection}, S, SE",
            ),
            if (widget.location == WindLocation.gardasee) ...[
              const SizedBox(height: 32),
              Text(
                "Morgenthermik (Pelér)",
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              CriteriaItem(
                label: "Prüfzeitraum",
                subLabel: "Morgensession",
                value: "5:00 - 9:00",
              ),
              CriteriaItem(
                label: "Wind-Schwellenwert",
                subLabel: "Minimum für Ora oder Pelér",
                value: "${loc.alarmThresholdKnots.round()} kts",
              ),
              CriteriaItem(
                label: "Schlummern wenn ruhig",
                subLabel: "Weiter schlafen wenn kein Wind",
                value: "AN",
                trailing: Switch(
                  value: _snoozeIfCalm,
                  onChanged: (v) => setState(() => _snoozeIfCalm = v),
                  activeThumbColor: AppColors.accentCyan,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentWindCard(LocationData loc, double wind) {
    final webcam = loc.webcams.first;
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.subtleBorder, width: 1),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "AKTUELLER WIND",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMuted,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          wind.toInt().toString(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 56,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -2,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "kts",
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "QUELLE",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textMuted,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      webcam.sourceDomain,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _readingIsFresh ? AppColors.statusGreen : AppColors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _readingIsFresh ? "LIVE-DATEN" : "KEINE FRISCHEN DATEN",
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _readingIsFresh ? AppColors.statusGreen : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          WindTrendChart(
            data: _history.isNotEmpty
                ? _history.take(12).toList().reversed.map((e) => e.baseWind).toList()
                : _generateTrendData(wind),
            height: 80,
            barColor: loc.accentColor,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Älter", style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              Text("Aktuell", style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}
