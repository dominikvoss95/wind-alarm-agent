import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/location.dart';
import '../theme/app_theme.dart';
import '../widgets/wind_trend_chart.dart';
import '../widgets/criteria_item.dart';

class LocationScreen extends StatefulWidget {
  final WindLocation location;

  const LocationScreen({super.key, required this.location});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  Map<String, double> _windValues = {};
  Map<String, double> _gustValues = {};
  bool _snoozeIfCalm = true;
  StreamSubscription<QuerySnapshot>? _measurementSubscription;

  @override
  void initState() {
    super.initState();
    _listenToFirestore();
  }

  void _listenToFirestore() {
    final apiLocId = widget.location.name.toLowerCase();
    _measurementSubscription = FirebaseFirestore.instance
        .collection('latest_measurements')
        .where('location_id', isEqualTo: apiLocId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final camId = data['cam_id'] as String;
          _windValues[camId] = (data['base_wind'] ?? 0.0).toDouble();
          _gustValues[camId] = (data['gust'] ?? 0.0).toDouble();
        }
      });
    });
  }

  @override
  void dispose() {
    _measurementSubscription?.cancel();
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
                  Colors.black.withOpacity(0.3),
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
            color: Colors.black.withOpacity(0.4),
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
            Row(
              children: [
                Text(
                  "ÜBERWACHUNG AKTIV",
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentTeal,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  " • ${loc.activeWindow}",
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentTeal.withOpacity(0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildCurrentWindCard(loc, wind),
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
              value: "12 kts",
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
                value: "14 kts",
              ),
              CriteriaItem(
                label: "Schlummern wenn ruhig",
                subLabel: "Weiter schlafen wenn kein Wind",
                value: "AN",
                trailing: Switch(
                  value: _snoozeIfCalm,
                  onChanged: (v) => setState(() => _snoozeIfCalm = v),
                  activeColor: AppColors.accentCyan,
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
              Column(
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
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(color: AppColors.statusGreen, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "LIVE-DATEN",
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.statusGreen,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          WindTrendChart(
            data: _generateTrendData(wind),
            height: 80,
            barColor: loc.accentColor,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Vorgestern", style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              Text("Gestern", style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              Text("Heute", style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
              Text("Vorhersage", style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}
