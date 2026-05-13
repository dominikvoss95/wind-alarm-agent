import 'dart:ui';
import 'package:flutter/material.dart';

class Responsive extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;

  const Responsive({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  static bool get isMobile => MediaQueryData.fromWindow(window).size.width < 600;
  static bool get isTablet => MediaQueryData.fromWindow(window).size.width >= 600 && MediaQueryData.fromWindow(window).size.width < 1200;
  static bool get isDesktop => MediaQueryData.fromWindow(window).size.width >= 1200;

  static double get screenWidth => MediaQueryData.fromWindow(window).size.width;
  static double get screenHeight => MediaQueryData.fromWindow(window).size.height;

  static double wp(double percent) => screenWidth * percent;
  static double hp(double percent) => screenHeight * percent;

  static double sp(double baseSize) {
    final width = screenWidth;
    final height = screenHeight;
    final diagonal = (width * width + height * height);
    final referenceDiagonal = 1080 * 1080 + 1920 * 1920;
    final scale = (diagonal / referenceDiagonal).clamp(0.5, 2.0);
    return baseSize * scale;
  }

  static double fontSize(double baseSize) {
    final width = screenWidth;
    final height = screenHeight;
    final refWidth = 390.0;
    final refHeight = 844.0;
    final widthScale = width / refWidth;
    final heightScale = height / refHeight;
    final scale = (widthScale + heightScale) / 2;
    return (baseSize * scale).clamp(baseSize * 0.8, baseSize * 1.5);
  }

  static double horizPadding() {
    if (screenWidth < 400) return 16;
    if (screenWidth < 600) return 20;
    if (screenWidth < 900) return 32;
    return 48;
  }

  static double cardPadding() {
    if (screenWidth < 400) return 16;
    if (screenWidth < 600) return 20;
    return 24;
  }

  static double heroHeight() {
    if (screenWidth < 400) return 320;
    if (screenWidth < 600) return 400;
    if (screenWidth < 900) return 480;
    return 560;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1200 && desktop != null) return desktop!;
    if (width >= 600 && tablet != null) return tablet!;
    return mobile;
  }
}