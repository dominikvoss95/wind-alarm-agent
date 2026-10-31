import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/location.dart';
import '../theme/app_theme.dart';
import '../widgets/location_card.dart';
import 'location_screen.dart';
import '../utils/alarm_utils.dart';
import '../services/wind_api_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<bool> _isMonitoringArmed = [true, false]; // Kochelsee, Gardasee
  final Map<String, WindMeasurement> _liveWindSummary = {};
  Timer? _pollingTimer;

  Future<void> _toggleMonitoring(int index, bool isArmed, LocationData data) async {
    setState(() {
      _isMonitoringArmed[index] = isArmed;
    });

    try {
      if (isArmed) {
        await FirebaseMessaging.instance.subscribeToTopic(data.fcmTopic);
        debugPrint("Subscribed to topic: ${data.fcmTopic}");
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(data.fcmTopic);
        debugPrint("Unsubscribed from topic: ${data.fcmTopic}");
      }
    } catch (e) {
      debugPrint("Error updating topic subscription: $e");
    }
  }

  final Map<String, WindForecast> _forecastSummary = {};

  @override
  void initState() {
    super.initState();
    debugPrint("MainScreen initState");
    _fetchForecasts();
    _startPolling();
  }

  Future<void> _fetchForecasts() async {
    for (var loc in WindLocation.values) {
      final forecast = await WindApiService.getForecast(loc.name.toLowerCase());
      if (forecast != null && mounted) {
        setState(() {
          _forecastSummary[loc.name] = forecast;
        });
      }
    }
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
      measurements.forEach((key, measurement) {
        if (measurement != null) {
          try {
            final loc = WindLocation.values.firstWhere(
              (l) => l.name.toLowerCase() == key.toLowerCase()
            );
            _liveWindSummary[loc.name] = measurement;
          } catch (_) {}
        }
      });
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("MainScreen build index: $_currentIndex");
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _currentIndex,
          children: [
            _buildHomeTab(),
            _buildLocationsTab(),
            _buildActivityTab(),
            _buildSettingsTab(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHomeTab() {
    final now = DateTime.now();
    final dateStr = DateFormat('EEE, d. MMM', 'de_DE').format(now).toUpperCase();
    final timeStr = DateFormat('HH:mm').format(now);
    final greeting = now.hour < 12 ? "Guten Morgen" : (now.hour < 18 ? "Guten Tag" : "Guten Abend");

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$dateStr • $timeStr",
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "$greeting, Dominik.",
            style: GoogleFonts.plusJakartaSans(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 48),
          ...WindLocation.values.asMap().entries.map((entry) {
            final index = entry.key;
            final loc = entry.value;
            final data = appLocations[loc]!;
            final measurement = _liveWindSummary[loc.name];
            final isFresh = measurement != null && measurement.isCurrentlyFresh;
            final wind = isFresh ? measurement.baseWind : null;
            final status = isFresh ? "Frische Messung" : "Keine frische Messung";
            
            return LocationOverviewCard(
              location: data,
              currentWind: wind,
              status: status,
              isArmed: _isMonitoringArmed[index],
              onArmedChanged: (val) => _toggleMonitoring(index, val, data),
              forecast: _forecastSummary[loc.name],
              onTap: () => Navigator.push(
                context, 
                MaterialPageRoute(builder: (_) => LocationScreen(location: loc))
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLocationsTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Alle Orte",
            style: GoogleFonts.plusJakartaSans(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: WindLocation.values.length,
              itemBuilder: (context, index) {
                final loc = WindLocation.values[index];
                final data = appLocations[loc]!;
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.subtleBorder),
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: data.accentColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: FaIcon(data.icon, color: data.accentColor, size: 20),
                    ),
                    title: Text(
                      data.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      "Überwachung: ${data.activeWindow}",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => LocationScreen(location: loc)),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 64, color: AppColors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            "Verlauf wird geladen...",
            style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Setup & Test",
            style: GoogleFonts.plusJakartaSans(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.backgroundCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.subtleBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.accentTeal.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_active_rounded, color: AppColors.accentTeal, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Kritischer Alarm",
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Testet die Benachrichtigungen auf deinem iPhone, die auch im Stummmodus klingeln.",
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentTeal.withValues(alpha: 0.15),
                      foregroundColor: AppColors.accentTeal,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: AppColors.accentTeal, width: 1.5),
                      ),
                    ),
                    onPressed: () async {
                      await triggerAlarmLogic(
                        hour: 6,
                        minute: 15,
                        locationName: "KOCHELSEE",
                      );
                    },
                    child: Text(
                      "Kochelsee-Alarm auslösen",
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentMint.withValues(alpha: 0.15),
                      foregroundColor: AppColors.accentMint,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: AppColors.accentMint, width: 1.5),
                      ),
                    ),
                    onPressed: () async {
                      await triggerAlarmLogic(
                        hour: 8,
                        minute: 45,
                        locationName: "GARDASEE",
                      );
                    },
                    child: Text(
                      "Gardasee-Alarm auslösen",
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16, top: 8),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark.withValues(alpha: 0.9),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          backgroundColor: AppColors.glassCard.withValues(alpha: 0.8),
          elevation: 0,
          selectedItemColor: AppColors.accentTeal,
          unselectedItemColor: AppColors.textMuted,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 10),
          unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 10),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "START"),
            BottomNavigationBarItem(icon: Icon(Icons.location_on_rounded), label: "ORTE"),
            BottomNavigationBarItem(icon: Icon(Icons.insights_rounded), label: "VERLAUF"),
            BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: "SETUP"),
          ],
        ),
      ),
    );
  }
}
