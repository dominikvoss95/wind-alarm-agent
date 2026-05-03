import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/location.dart';
import '../theme/app_theme.dart';
import '../widgets/location_card.dart';
import 'location_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<bool> _isMonitoringArmed = [true, false]; // Kochelsee, Gardasee
  final Map<String, double> _liveWindSummary = {};
  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    print("DEBUG: MainScreen initState");
    _initFirestoreListeners();
  }

  void _initFirestoreListeners() {
    for (var loc in WindLocation.values) {
      final sub = FirebaseFirestore.instance
          .collection('latest_measurements')
          .where('location_id', isEqualTo: loc.name.toLowerCase())
          .snapshots()
          .listen((snapshot) {
        if (!mounted || snapshot.docs.isEmpty) return;
        setState(() {
          // Simplification: use first cam found for home screen summary
          final data = snapshot.docs.first.data();
          _liveWindSummary[loc.name] = (data['base_wind'] ?? 0.0).toDouble();
        });
      });
      _subscriptions.add(sub);
    }
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    print("DEBUG: MainScreen build index: $_currentIndex");
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
            final wind = _liveWindSummary[loc.name] ?? (index == 0 ? 18.0 : 4.0);
            
            return LocationOverviewCard(
              location: data,
              currentWind: wind,
              status: index == 0 ? "Steigt stetig" : "Nächster Check • ${data.nextCheck}",
              isArmed: _isMonitoringArmed[index],
              onArmedChanged: (val) => setState(() => _isMonitoringArmed[index] = val),
              onTap: () => Navigator.push(
                context, 
                MaterialPageRoute(builder: (_) => LocationScreen(location: loc))
              ),
            );
          }).toList(),
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
                        color: data.accentColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(data.icon, color: data.accentColor, size: 20),
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
          Icon(Icons.history_rounded, size: 64, color: AppColors.textMuted.withOpacity(0.5)),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.settings_outlined, size: 64, color: AppColors.textMuted.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            "Einstellungen",
            style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16, top: 8),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark.withOpacity(0.9),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          backgroundColor: AppColors.glassCard.withOpacity(0.8),
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
