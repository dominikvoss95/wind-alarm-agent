import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'alarm_utils.dart';

class AlarmChannelStatus {
  final String criticalTitle;
  final String criticalSubtitle;
  final bool showCriticalCheck;
  final String toneSubtitle;
  final String silentSubtitle;
  final String silentValue;

  const AlarmChannelStatus({
    required this.criticalTitle,
    required this.criticalSubtitle,
    required this.showCriticalCheck,
    required this.toneSubtitle,
    required this.silentSubtitle,
    required this.silentValue,
  });

  static const unsupported = AlarmChannelStatus(
    criticalTitle: 'Kritische Alarme',
    criticalSubtitle: 'Auf diesem System nicht verfügbar',
    showCriticalCheck: false,
    toneSubtitle: 'Kein eigener Ton hinterlegt',
    silentSubtitle: 'Nur mit Wecker oder kritischem Alarm',
    silentValue: 'Nicht verfügbar',
  );

  static const checking = AlarmChannelStatus(
    criticalTitle: 'Kritische Alarme',
    criticalSubtitle: 'Status wird geprüft',
    showCriticalCheck: false,
    toneSubtitle: 'Status wird geprüft',
    silentSubtitle: 'Status wird geprüft',
    silentValue: '…',
  );

  /// Reads what this install can actually do. Does not change alarm behavior.
  static Future<AlarmChannelStatus> resolve() async {
    try {
      if (kIsWeb) return unsupported;
      if (Platform.isIOS) {
        final ios = flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        final permissions = await ios?.checkPermissions();
        if (permissions == null) return unsupported;
        if (permissions.isCriticalEnabled) {
          return const AlarmChannelStatus(
            criticalTitle: 'Kritische Alarme erlaubt',
            criticalSubtitle: 'Klingeln auch bei „Nicht stören“',
            showCriticalCheck: true,
            toneSubtitle: 'Alarmton der App',
            silentSubtitle: 'Klingelt auch bei stummem Gerät',
            silentValue: 'Aktiv',
          );
        }
        return AlarmChannelStatus(
          criticalTitle: 'Kritische Alarme nicht erlaubt',
          criticalSubtitle: permissions.isEnabled
              ? 'Hinweise sind an, kritische Alarme nicht'
              : 'Mitteilungen sind aus',
          showCriticalCheck: false,
          toneSubtitle: 'Alarmton der App',
          silentSubtitle: 'Braucht kritische Alarme',
          silentValue: 'Nicht aktiv',
        );
      }
      if (Platform.isAndroid) {
        return const AlarmChannelStatus(
          criticalTitle: 'Kritische Alarme',
          criticalSubtitle: 'Über den Systemwecker, auch im Stummmodus',
          showCriticalCheck: true,
          toneSubtitle: 'Systemwecker',
          silentSubtitle: 'Klingelt auch bei stummem Gerät',
          silentValue: 'Aktiv',
        );
      }
    } catch (error, stack) {
      debugPrint('Alarm status unavailable: $error\n$stack');
    }
    return unsupported;
  }
}
