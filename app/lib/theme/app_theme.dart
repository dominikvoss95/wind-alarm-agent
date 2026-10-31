import 'package:flutter/material.dart';

/// mira-v1 color tokens. Hex values live only here.
class MiraColors {
  static const Color bg = Color(0xFF0A0A0B);
  static const Color surface = Color(0xFF18181B);
  static const Color surface2 = Color(0xFF232327);
  static const Color outline = Color(0xFF2E2E33);
  static const Color textPrimary = Color(0xFFFAFAFA);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textTertiary = Color(0xFF71717A);
  static const Color accent = Color(0xFF22D3EE);
  static const Color onAccent = Color(0xFF04242B);

  static const Color windTooLittle = Color(0xFF52525B);
  static const Color windLight = Color(0xFF38BDF8);
  static const Color windRideable = Color(0xFF22D3EE);
  static const Color windGood = Color(0xFF34D399);
  static const Color windStrong = Color(0xFFFBBF24);
  static const Color windVeryStrong = Color(0xFFF87171);

  static const Color heroTop = Color(0xFF0B2545);
  static const Color heroMid = Color(0xFF0A1A2E);
  static const Color tick = Color(0xFF3F3F46);

  static const double pillTint = 0.14;
  static const double navIconTint = 0.16;
  static const double navFill = 0.96;
}

class MiraSpace {
  static const double screen = 20;
  static const double card = 20;
  static const double gap = 12;
  static const double section = 32;
  static const double radius = 24;
  static const double touch = 48;
  static const double navHeight = 72;
  static const double radiusIcon = 10;
  static const double radiusInset = 14;
  static const double radiusPill = 14;
  static const double radiusNav = 36;
  static const double buttonHeight = 52;
}

class MiraType {
  static const String family = 'Plus Jakarta Sans';

  static const TextStyle display = TextStyle(
    fontFamily: family,
    fontSize: 56,
    height: 60 / 56,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.12,
    color: MiraColors.textPrimary,
  );

  static const TextStyle h1 = TextStyle(
    fontFamily: family,
    fontSize: 32,
    height: 38 / 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.32,
    color: MiraColors.textPrimary,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: family,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
    color: MiraColors.textPrimary,
  );

  static const TextStyle title = TextStyle(
    fontFamily: family,
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    color: MiraColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: family,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
    color: MiraColors.textPrimary,
  );

  static const TextStyle label = TextStyle(
    fontFamily: family,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.96,
    color: MiraColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: family,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
    color: MiraColors.textSecondary,
  );
}

@immutable
class MiraTheme extends ThemeExtension<MiraTheme> {
  const MiraTheme();

  Color get bg => MiraColors.bg;
  Color get surface => MiraColors.surface;
  Color get surface2 => MiraColors.surface2;
  Color get outline => MiraColors.outline;
  Color get textPrimary => MiraColors.textPrimary;
  Color get textSecondary => MiraColors.textSecondary;
  Color get textTertiary => MiraColors.textTertiary;
  Color get accent => MiraColors.accent;
  Color get onAccent => MiraColors.onAccent;

  TextStyle get display => MiraType.display;
  TextStyle get h1 => MiraType.h1;
  TextStyle get h2 => MiraType.h2;
  TextStyle get title => MiraType.title;
  TextStyle get body => MiraType.body;
  TextStyle get label => MiraType.label;
  TextStyle get caption => MiraType.caption;

  @override
  MiraTheme copyWith() => const MiraTheme();

  @override
  MiraTheme lerp(ThemeExtension<MiraTheme>? other, double t) => this;
}

extension MiraBuildContext on BuildContext {
  MiraTheme get mira => Theme.of(this).extension<MiraTheme>() ?? const MiraTheme();
}

/// Backwards-compatible aliases so model data keeps compiling.
class AppColors {
  static const Color backgroundDark = MiraColors.bg;
  static const Color backgroundCard = MiraColors.surface;
  static const Color glassCard = MiraColors.surface2;
  static const Color accentTeal = MiraColors.accent;
  static const Color accentCyan = MiraColors.accent;
  static const Color accentMint = MiraColors.windGood;
  static const Color statusGreen = MiraColors.windGood;
  static const Color statusGrey = MiraColors.windTooLittle;
  static const Color textPrimary = MiraColors.textPrimary;
  static const Color textSecondary = MiraColors.textSecondary;
  static const Color textMuted = MiraColors.textTertiary;
  static const Color subtleBorder = MiraColors.outline;
}

class AppTheme {
  static ThemeData get darkTheme {
    const scheme = ColorScheme.dark(
      surface: MiraColors.bg,
      primary: MiraColors.accent,
      onPrimary: MiraColors.onAccent,
      secondary: MiraColors.accent,
      onSecondary: MiraColors.onAccent,
      onSurface: MiraColors.textPrimary,
      outline: MiraColors.outline,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: MiraColors.bg,
      fontFamily: MiraType.family,
      colorScheme: scheme,
      splashColor: MiraColors.accent.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,
    );

    return base.copyWith(
      textTheme: TextTheme(
        displayLarge: MiraType.display,
        headlineLarge: MiraType.h1,
        headlineMedium: MiraType.h2,
        titleMedium: MiraType.title,
        bodyMedium: MiraType.body,
        bodySmall: MiraType.caption,
        labelSmall: MiraType.label,
      ).apply(
        fontFamily: MiraType.family,
        bodyColor: MiraColors.textPrimary,
        displayColor: MiraColors.textPrimary,
      ),
      extensions: const [MiraTheme()],
      sliderTheme: SliderThemeData(
        activeTrackColor: MiraColors.accent,
        inactiveTrackColor: MiraColors.accent.withValues(alpha: 0.2),
        thumbColor: MiraColors.accent,
        overlayColor: MiraColors.accent.withValues(alpha: 0.1),
        trackHeight: 4,
      ),
    );
  }
}
