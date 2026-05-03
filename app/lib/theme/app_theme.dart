import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Ultra-deep charcoal/black
  static const Color backgroundDark = Color(0xFF0A0A0B); 
  static const Color backgroundCard = Color(0xFF1C1C1E);
  static const Color glassCard = Color(0xFF242426);
  
  // Vibrant Teal/Cyan accents
  static const Color accentTeal = Color(0xFF00E5FF);
  static const Color accentCyan = Color(0xFF22D3EE);
  static const Color accentMint = Color(0xFF34D399);

  // Status Colors
  static const Color statusGreen = Color(0xFF4ADE80);
  static const Color statusGrey = Color(0xFF3F3F46);

  // Soft text and borders
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textMuted = Color(0xFF71717A);
  static const Color subtleBorder = Color(0xFF27272A);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme).copyWith(
        titleLarge: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        bodyLarge: GoogleFonts.plusJakartaSans(color: AppColors.textPrimary),
        bodyMedium: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary),
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accentMint,
        brightness: Brightness.dark,
        primary: AppColors.accentMint,
        secondary: AppColors.accentTeal,
        surface: AppColors.backgroundCard,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.accentMint,
        inactiveTrackColor: AppColors.accentMint.withOpacity(0.2),
        thumbColor: AppColors.accentMint,
        overlayColor: AppColors.accentMint.withOpacity(0.1),
        trackHeight: 4,
      ),
    );
  }
}
