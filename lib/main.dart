import 'package:flutter/material.dart';
import 'package:sasimo_guard/screens/public_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sasimo_guard/screens/home_screen.dart';
import 'screens/login_screen.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM BG] Notif diterima: ${message.notification?.title}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://tdjmedsweejiwibzywtv.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRkam1lZHN3ZWVqaXdpYnp5d3R2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0NzI3ODksImV4cCI6MjA5NDA0ODc4OX0.ggSVpWwbvnSYbGJR6KuY9zrHtNbpqMhx9zKBVNBFxeE',
  );

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await _initLocalNotifications();
  await _initFCM();

  runApp(const MyApp());
}

Future<void> _initLocalNotifications() async {
  const AndroidInitializationSettings androidInit =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: androidInit),
  );

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      'ews_urgent', 'Peringatan Darurat',
      description: 'Notifikasi gempa kuat dekat lokasi Anda.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ),
  );
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      'ews_info', 'Info Gempa',
      description: 'Informasi gempa umum.',
      importance: Importance.defaultImportance,
    ),
  );
}

Future<void> _initFCM() async {
  final fcm = FirebaseMessaging.instance;

  await fcm.requestPermission(alert: true, badge: true, sound: true);

  final String? token = await fcm.getToken();
  debugPrint('[FCM] Token: $token');

  if (token != null) {
    try {
      await Supabase.instance.client.from('fcm_tokens').upsert({
        'token': token,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[FCM] Gagal simpan token: $e');
    }
  }

  fcm.onTokenRefresh.listen((newToken) async {
    try {
      await Supabase.instance.client.from('fcm_tokens').upsert({
        'token': newToken,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[FCM] Gagal update token: $e');
    }
  });

  // Notif waktu app FOREGROUND — FCM tidak auto-show, harus manual
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint('[FCM FG] Notif masuk: ${message.notification?.title}');
    final notification = message.notification;
    if (notification == null) return;

    final bool isUrgent = (message.data['is_urgent'] ?? 'false') == 'true';
    flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          isUrgent ? 'ews_urgent' : 'ews_info',
          isUrgent ? 'Peringatan Darurat' : 'Info Gempa',
          importance: isUrgent ? Importance.max : Importance.defaultImportance,
          priority: isUrgent ? Priority.max : Priority.defaultPriority,
          color: isUrgent ? Colors.red : Colors.blue,
          enableVibration: isUrgent,
          playSound: isUrgent,
        ),
      ),
    );
  });

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('[FCM] Tap dari background: ${message.data}');
  });

  final RemoteMessage? initialMessage = await fcm.getInitialMessage();
  if (initialMessage != null) {
    debugPrint('[FCM] App dibuka dari terminated: ${initialMessage.data}');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SeismoGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const PublicScreen(),
    );
  }
}