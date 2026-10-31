import 'package:flutter/material.dart';

import 'app_theme.dart';

enum WindBand { tooLittle, light, rideable, good, strong, veryStrong }

/// Wind scale from the mira-v1 styleguide.
///
/// Below 8 kt the number uses text-secondary; the bar color stays #52525B.
class WindScale {
  static WindBand band(double knots) {
    if (knots < 8) return WindBand.tooLittle;
    if (knots < 12) return WindBand.light;
    if (knots < 18) return WindBand.rideable;
    if (knots < 25) return WindBand.good;
    if (knots <= 30) return WindBand.strong;
    return WindBand.veryStrong;
  }

  static Color barColor(double knots) {
    switch (band(knots)) {
      case WindBand.tooLittle:
        return MiraColors.windTooLittle;
      case WindBand.light:
        return MiraColors.windLight;
      case WindBand.rideable:
        return MiraColors.windRideable;
      case WindBand.good:
        return MiraColors.windGood;
      case WindBand.strong:
        return MiraColors.windStrong;
      case WindBand.veryStrong:
        return MiraColors.windVeryStrong;
    }
  }

  static Color numberColor(double knots) {
    if (band(knots) == WindBand.tooLittle) return MiraColors.textSecondary;
    return barColor(knots);
  }

  static String verdict(double knots) {
    switch (band(knots)) {
      case WindBand.tooLittle:
        return 'zu wenig';
      case WindBand.light:
        return 'leicht';
      case WindBand.rideable:
        return 'fahrbar';
      case WindBand.good:
        return 'gut';
      case WindBand.strong:
        return 'stark';
      case WindBand.veryStrong:
        return 'sehr stark';
    }
  }

  static String todayVerdict(double knots) => 'Heute ${verdict(knots)}';

  static String capitalizedVerdict(double knots) {
    final label = verdict(knots);
    if (label.isEmpty) return label;
    return label[0].toUpperCase() + label.substring(1);
  }

  static bool isRideable(double knots) => band(knots).index >= WindBand.rideable.index;
}
