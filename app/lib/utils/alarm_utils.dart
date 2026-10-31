import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_intent_plus/android_intent.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const alarmSoundFile = 'alarm_sound.mp3';

bool _notificationsReady = false;

DarwinNotificationDetails iosAlarmDetails() {
  return const DarwinNotificationDetails(
    presentSound: true,
    presentAlert: true,
    interruptionLevel: InterruptionLevel.timeSensitive,
    sound: alarmSoundFile,
  );
}

Future<void> initLocalNotifications() async {
  if (_notificationsReady) return;
  const initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      requestCriticalPermission: false,
    ),
  );
  await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);
  _notificationsReady = true;
}

Future<void> triggerAlarmLogic({int hour = 6, int minute = 0, String locationName = "KOCHELSEE"}) async {
  if (Platform.isAndroid) {
    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: <String, dynamic>{
        'android.intent.extra.alarm.HOUR': hour,
        'android.intent.extra.alarm.MINUTES': minute,
        'android.intent.extra.alarm.MESSAGE': '🌬️ $locationName WIND SURF TIME!',
        'android.intent.extra.alarm.SKIP_UI': true,
      },
    );
    await intent.launch();
  } else if (Platform.isIOS) {
    final details = NotificationDetails(iOS: iosAlarmDetails());
    await flutterLocalNotificationsPlugin.show(
      id: 88,
      title: '🌬️ $locationName WIND!',
      body: 'Get up! Wind detected for $hour:${minute.toString().padLeft(2, '0')}',
      notificationDetails: details,
    );
  }
}
