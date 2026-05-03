import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/app_theme.dart';

enum WindLocation { kochelsee, gardasee }

class LocationData {
  final String id;
  final String name;
  final String fcmTopic;
  final IconData icon;
  final List<WebcamData> webcams;
  final Color accentColor;
  final String activeWindow;
  final String nextCheck;
  final String defaultDirection;
  final String heroImageUrl;

  LocationData({
    required this.id,
    required this.name,
    required this.fcmTopic,
    required this.icon,
    required this.webcams,
    required this.accentColor,
    required this.activeWindow,
    required this.nextCheck,
    required this.defaultDirection,
    required this.heroImageUrl,
  });
}

class WebcamData {
  final String name;
  final String url;
  final String sourceDomain;

  WebcamData({
    required this.name,
    required this.url,
    required this.sourceDomain,
  });
}

final Map<WindLocation, LocationData> appLocations = {
  WindLocation.kochelsee: LocationData(
    id: 'kochelsee',
    name: 'Kochelsee',
    fcmTopic: 'wind_alarms_kochelsee',
    icon: FontAwesomeIcons.mountainCity,
    accentColor: AppColors.accentTeal,
    activeWindow: '04:00 - 07:00',
    nextCheck: '04:20',
    defaultDirection: 'SW',
    heroImageUrl: 'assets/images/kochelsee.png',
    webcams: [
      WebcamData(
        name: 'Trimini',
        url: 'https://www.addicted-sports.com/webcam/kochelsee/trimini/',
        sourceDomain: 'addictedsports.com',
      ),
    ],
  ),
  WindLocation.gardasee: LocationData(
    id: 'gardasee',
    name: 'Gardasee',
    fcmTopic: 'wind_alarms_gardasee',
    icon: FontAwesomeIcons.water,
    accentColor: AppColors.accentCyan,
    activeWindow: '05:00 - 09:00',
    nextCheck: '05:30',
    defaultDirection: 'N',
    heroImageUrl: 'assets/images/gardasee.png',
    webcams: [
      WebcamData(
        name: 'Malcesine Nord',
        url: 'https://www.addicted-sports.com/webcam/gardasee/malcesinenord/',
        sourceDomain: 'addictedsports.com',
      ),
      WebcamData(
        name: 'Malcesine',
        url: 'https://www.addicted-sports.com/webcam/gardasee/malcesine/',
        sourceDomain: 'addictedsports.com',
      ),
      WebcamData(
        name: 'Campione',
        url: 'https://www.addicted-sports.com/webcam/gardasee/campione/',
        sourceDomain: 'addictedsports.com',
      ),
    ],
  ),
};
