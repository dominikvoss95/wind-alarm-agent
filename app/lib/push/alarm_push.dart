import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../utils/alarm_utils.dart';

/// Topics the app should subscribe to for the current armed flags.
List<String> topicsForArmed(List<bool> armed, List<String> topicsInOrder) {
  final selected = <String>[];
  for (var index = 0; index < topicsInOrder.length; index++) {
    if (index < armed.length && armed[index]) {
      selected.add(topicsInOrder[index]);
    }
  }
  return selected;
}

bool isScheduleAlarm(Map<String, dynamic> data) {
  return data['action'] == 'schedule_alarm';
}

/// Foreground messages are not shown by iOS. Background messages that already
/// carry a notification payload are shown by the system, so a second local
/// alert would ring twice.
bool shouldPresentLocalAlarm({
  required Map<String, dynamic> data,
  required bool systemWillPresent,
}) {
  return isScheduleAlarm(data) && !systemWillPresent;
}

String alarmLocationName(Map<String, dynamic> data) {
  final raw = data['location']?.toString().trim() ?? '';
  if (raw.isEmpty) return 'KOCHELSEE';
  return raw.toUpperCase();
}

Future<void> subscribeToAlarmTopics(List<String> topics) async {
  if (topics.isEmpty) return;
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    criticalAlert: false,
    provisional: false,
  );
  if (!kIsWeb && Platform.isIOS) {
    String? token;
    for (var attempt = 0; attempt < 20; attempt++) {
      token = await messaging.getAPNSToken();
      if (token != null && token.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (token == null || token.isEmpty) {
      debugPrint('APNs token not ready; skipped subscribe for $topics');
      return;
    }
  }
  for (final topic in topics) {
    await messaging.subscribeToTopic(topic);
    debugPrint('Subscribed to topic: $topic');
  }
  if (!kIsWeb && Platform.isIOS) {
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );
  }
}

Future<void> presentScheduleAlarm(Map<String, dynamic> data) async {
  final now = DateTime.now();
  await triggerAlarmLogic(
    locationName: alarmLocationName(data),
    hour: now.hour,
    minute: now.minute,
  );
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await initLocalNotifications();
  if (shouldPresentLocalAlarm(
    data: message.data,
    systemWillPresent: message.notification != null,
  )) {
    await presentScheduleAlarm(message.data);
  }
}

Future<void> handleForegroundAlarm(RemoteMessage message) async {
  if (shouldPresentLocalAlarm(data: message.data, systemWillPresent: false)) {
    await presentScheduleAlarm(message.data);
  }
}
