import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/services.dart';
import 'firebase_options.dart';

// --- Background Message Handler ---
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("Handling a background message: ${message.messageId}");

  if (message.data['action'] == 'schedule_alarm') {
    await _triggerAlarmLogic();
  }
}

// --- Local Notifications Setup ---
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _setupLocalNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  
  const DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
    requestCriticalPermission: true, // IMPORTANT for iOS
  );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
  );
}

/// Dispatches the correct alarm logic based on the platform
Future<void> _triggerAlarmLogic({int hour = 6, int minute = 0}) async {
  if (Platform.isAndroid) {
    // Android: Use the real system clock
    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: <String, dynamic>{
        'android.intent.extra.alarm.HOUR': hour,
        'android.intent.extra.alarm.MINUTES': minute,
        'android.intent.extra.alarm.MESSAGE': 'WIND ALARM!',
        'android.intent.extra.alarm.SKIP_UI': true,
      },
    );
    await intent.launch();
  } else if (Platform.isIOS) {
    // iOS: Send a loud critical alert notification
    // We can't set the system clock, so we use a high-priority local notification
    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentSound: true,
        presentAlert: true,
        interruptionLevel: InterruptionLevel.critical, // Wakes you up!
        sound: 'default', // In production, add a custom loud '.caf' sound file to your Xcode project
      ),
    );
    
    await flutterLocalNotificationsPlugin.show(
      id: 88,
      title: '🌊 WIND ALARM!!',
      body: 'Get up! Wind predicted for $hour:${minute.toString().padLeft(2, '0')}',
      notificationDetails: details,
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    print("Firebase initialization failed: $e");
  }

  await _setupLocalNotifications();
  tz.initializeTimeZones();

  SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent));

  runApp(const WindAlarmApp());
}

class WindAlarmApp extends StatelessWidget {
  const WindAlarmApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wind Alarm',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E2C),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _fcmToken = "Loading...";

  @override
  void initState() {
    super.initState();
    _getFCMToken();

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['action'] == 'schedule_alarm') {
        _triggerAlarmLogic();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Wind Alarm received!'), backgroundColor: Colors.cyan),
          );
        }
      }
    });
  }

  Future<void> _getFCMToken() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      sound: true,
      criticalAlert: true, // IMPORTANT for iOS
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      String? token = await messaging.getToken();
      await messaging.subscribeToTopic('wind_alarms');
      setState(() { _fcmToken = "Subscribed to Topic ✓"; });
      print("FCM Token: $token");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kochelsee Wind Alarm')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.surfing, size: 80, color: Colors.cyanAccent),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _triggerAlarmLogic(hour: 0, minute: 0), // Test trigger
              icon: const Icon(Icons.alarm),
              label: const Text("TEST ALARM"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            ),
            const SizedBox(height: 16),
            Text(_fcmToken, style: const TextStyle(color: Colors.greenAccent)),
          ],
        ),
      ),
    );
  }
}
