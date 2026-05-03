import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/location.dart';
import '../theme/app_theme.dart';

class LocationOverviewCard extends StatelessWidget {
  final LocationData location;
  final double currentWind;
  final String status;
  final bool isArmed;
  final Function(bool) onArmedChanged;
  final VoidCallback onTap;

  const LocationOverviewCard({
    super.key,
    required this.location,
    required this.currentWind,
    required this.status,
    required this.isArmed,
    required this.onArmedChanged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.backgroundCard,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: AppColors.subtleBorder, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      location.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isArmed ? "ÜBERWACHUNG AKTIV" : "STANDBY",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isArmed ? AppColors.accentCyan : AppColors.textMuted,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: isArmed,
                  onChanged: onArmedChanged,
                  activeColor: AppColors.accentCyan,
                  activeTrackColor: AppColors.accentCyan.withOpacity(0.2),
                  inactiveThumbColor: AppColors.textMuted,
                  inactiveTrackColor: AppColors.subtleBorder,
                ),
              ],
            ),
            const SizedBox(height: 32),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    currentWind.toInt().toString(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 72,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -2,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "kts",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "${location.defaultDirection} • $status",
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user, color: AppColors.accentCyan, size: 16),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Agent hat Quellen geprüft. Wind ist stabil.",
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.accentCyan.withOpacity(0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
