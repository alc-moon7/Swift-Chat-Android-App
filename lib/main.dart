import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swift_chat/firebase_options.dart';
import 'package:swift_chat/screens/auth/login_screen.dart';
import 'package:swift_chat/screens/home_screen.dart';
import 'package:swift_chat/screens/splace_screen.dart';
import 'package:swift_chat/services/notification_service.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint(
    '[Background] Message: ${message.notification?.title} - ${message.notification?.body}',
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await NotificationService.initialize();

    final token = await FirebaseMessaging.instance.getToken();
    debugPrint('FCM token: $token');

    runApp(const MyApp());
  } catch (error) {
    debugPrint('Initialization failed: $error');
    runApp(const ErrorApp());
  }
}

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
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: isDarkMode ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness:
          isDarkMode ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDarkMode ? Brightness.dark : Brightness.light,
    );

    SystemChrome.setSystemUIOverlayStyle(overlayStyle);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Swift Chat',
      theme: _lightTheme(),
      darkTheme: _darkTheme(),
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: const Duration(milliseconds: 320),
      themeAnimationCurve: Curves.easeInOutCubic,
      routes: {
        '/login': (_) => LoginScreen(
              isDarkMode: isDarkMode,
              onThemeChanged: toggleTheme,
            ),
        '/home': (_) => HomeScreen(
              isDarkMode: isDarkMode,
              onThemeChanged: toggleTheme,
            ),
        '/splash': (_) => SplashScreen(
              isDarkMode: isDarkMode,
              onThemeChanged: toggleTheme,
            ),
      },
      home: AuthWrapper(
        isDarkMode: isDarkMode,
        onThemeChanged: toggleTheme,
      ),
    );
  }

  ThemeData _lightTheme() {
    const colorScheme = ColorScheme.light(
      primary: Color(0xFF1485EA),
      secondary: Color(0xFF2EA6FF),
      surface: Colors.white,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Color(0xFF17212B),
    );

    return ThemeData.from(
      colorScheme: colorScheme,
      useMaterial3: true,
    ).copyWith(
      scaffoldBackgroundColor: const Color(0xFFF3F7FB),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Color(0xFFF3F7FB),
        foregroundColor: Color(0xFF17212B),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary.withOpacity(0.45);
          }
          return const Color(0xFFD5DFEA);
        }),
      ),
    );
  }

  ThemeData _darkTheme() {
    const colorScheme = ColorScheme.dark(
      primary: Color(0xFF2EA6FF),
      secondary: Color(0xFF67C1FF),
      surface: Color(0xFF1E2C38),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.white,
    );

    return ThemeData.from(
      colorScheme: colorScheme,
      useMaterial3: true,
    ).copyWith(
      scaffoldBackgroundColor: const Color(0xFF17212B),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Color(0xFF17212B),
        foregroundColor: Colors.white,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return const Color(0xFFCCD6E0);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary.withOpacity(0.45);
          }
          return const Color(0xFF324454);
        }),
      ),
    );
  }
}

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
