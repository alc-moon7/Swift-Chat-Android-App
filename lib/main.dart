import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';
import 'package:swift_chat/screens/home_screen.dart';
import 'package:swift_chat/screens/splace_screen.dart';

// Background message handler (must be top-level)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print(
      '🔔 [Background] Message: ${message.notification?.title} - ${message.notification?.body}');
}

// Local Notification Plugin
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Status/navigation bars
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Firebase Init
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);

    // FCM background
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // FCM foreground notification setup
    await _setupLocalNotifications();

    // 🔑 Get FCM token
    String? token = await FirebaseMessaging.instance.getToken();
    print("📱 FCM Token: $token");

    runApp(const MyApp());
  } catch (e) {
    runApp(const ErrorApp());
  }
}

// 🛠️ Configure local notifications
Future<void> _setupLocalNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'swift_chat_channel', // Channel ID
            'Swift Chat Notifications', // Channel Name
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    }
  });
}

// 🟢 Main App
class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isDarkMode = false;

  void toggleTheme(bool value) {
    setState(() {
      isDarkMode = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      isDarkMode
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark
              .copyWith(statusBarColor: Colors.transparent),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Swift Chat',
      theme: isDarkMode ? _darkTheme() : _lightTheme(),
      home: AuthWrapper(
        isDarkMode: isDarkMode,
        onThemeChanged: toggleTheme,
      ),
    );
  }

  ThemeData _lightTheme() {
    return ThemeData(
      primarySwatch: Colors.blue,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 1,
        iconTheme: IconThemeData(color: Colors.black),
        backgroundColor: Color.fromARGB(255, 97, 170, 248),
      ),
      scaffoldBackgroundColor: const Color(0xFFF0F0F0),
    );
  }

  ThemeData _darkTheme() {
    return ThemeData.dark().copyWith(
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 1,
        backgroundColor: Colors.black87,
      ),
      scaffoldBackgroundColor: Colors.grey[900],
    );
  }
}

// 👤 Auth Wrapper
class AuthWrapper extends StatelessWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;

  const AuthWrapper({
    Key? key,
    required this.isDarkMode,
    required this.onThemeChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return HomeScreen(
            isDarkMode: isDarkMode,
            onThemeChanged: onThemeChanged,
          );
        }

        return SplashScreen(
          isDarkMode: isDarkMode,
          onThemeChanged: onThemeChanged,
        );
      },
    );
  }
}

// ❌ Error App
class ErrorApp extends StatelessWidget {
  const ErrorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Initialization failed. Please restart the app.',
            style: TextStyle(
              color: Colors.red[700],
              fontSize: 18,
            ),
          ),
        ),
      ),
    );
  }
}
