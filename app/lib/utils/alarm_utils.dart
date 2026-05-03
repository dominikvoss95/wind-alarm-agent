import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_intent_plus/android_intent.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

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
    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentSound: true,
        presentAlert: true,
        interruptionLevel: InterruptionLevel.critical,
        sound: 'default',
      ),
    );
    await flutterLocalNotificationsPlugin.show(
      id: 88,
      title: '🌬️ $locationName WIND!',
      body: 'Get up! Wind detected for $hour:${minute.toString().padLeft(2, '0')}',
      notificationDetails: details,
    );
  }
}
