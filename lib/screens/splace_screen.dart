import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:swift_chat/helper/dialogs.dart';
import 'package:swift_chat/screens/auth/login_screen.dart';
import 'package:swift_chat/screens/home_screen.dart';
import 'package:swift_chat/services/app_update_service.dart';
import 'package:swift_chat/services/notification_service.dart';

class SplashScreen extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;

  const SplashScreen({
    Key? key,
    required this.isDarkMode,
    required this.onThemeChanged,
  }) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _logoSlide;
  late Animation<double> _logoFade;
  late Animation<double> _textFade;
  Timer? _navigationTimer;
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  bool _isUpdateDialogVisible = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setupNavigation();
  }

  void _initializeAnimations() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _logoSlide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    ));

    _logoFade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
    ));

    _textFade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 0.7, curve: Curves.easeIn),
    ));

    _controller.forward();
  }

  Future<void> _handleNotifications() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPermissionDialog();
      });
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final existingData =
          (await userRef.get()).data() ?? const <String, dynamic>{};

      await userRef.set({
        'name': existingData['name'] ?? user.displayName ?? 'User',
        'email': user.email ?? existingData['email'] ?? '',
        'photoUrl': existingData['photoUrl'] ?? user.photoURL ?? '',
        'photoBase64': existingData['photoBase64'] ?? '',
        'phone': existingData['phone'] ?? '',
        'bio': existingData['bio'] ?? '',
        'username': existingData['username'] ?? '',
        'birthday': existingData['birthday'],
        'uid': user.uid,
      }, SetOptions(merge: true));
      await NotificationService.syncTokenForUser(user);
    }
  }

  void _setupNavigation() {
    _navigationTimer = Timer(const Duration(seconds: 2), () async {
      if (!mounted) return;

      await _handleNotifications();
      final shouldContinue = await _handleLaunchUpdateCheck();
      if (!mounted || !shouldContinue) {
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _navigateToLogin();
      } else {
        _navigateToHome();
      }
    });
  }

  Future<bool> _handleLaunchUpdateCheck() async {
    final updateInfo = await AppUpdateService.checkForUpdate();
    if (!mounted) {
      return false;
    }

    if (updateInfo.status != AppUpdateCheckStatus.updateAvailable ||
        (updateInfo.downloadUrl ?? '').isEmpty ||
        _isUpdateDialogVisible) {
      return true;
    }

    _isUpdateDialogVisible = true;
    final releaseUrl = updateInfo.downloadUrl ?? updateInfo.releaseUrl ?? '';
    final didTapDownload = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Update available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current: ${updateInfo.installedAppInfo?.displayVersion ?? 'Unknown'}',
              ),
              const SizedBox(height: 6),
              Text('Latest: v${updateInfo.latestVersion ?? 'Unknown'}'),
              const SizedBox(height: 12),
              Text(
                AppUpdateService.normalizeReleaseNotes(updateInfo.releaseNotes),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Download'),
            ),
          ],
        );
      },
    );

    _isUpdateDialogVisible = false;

    if (!mounted) {
      return false;
    }

    if (didTapDownload == true && releaseUrl.isNotEmpty) {
      await _downloadUpdateInApp(updateInfo);
    }

    return true;
  }

  Future<void> _downloadUpdateInApp(AppUpdateInfo updateInfo) async {
    final downloadUrl = updateInfo.downloadUrl ?? '';
    if (downloadUrl.isEmpty || !mounted) {
      return;
    }

    Dialogs.showLoading(
      context,
      message: 'Downloading update inside Swift Chat...',
    );

    try {
      final result = await AppUpdateService.downloadAndInstallUpdate(
        url: downloadUrl,
        fileName: updateInfo.downloadFileName,
      );

      if (!mounted) {
        return;
      }

      Dialogs.hideLoading(context);

      if (result.status != AppUpdateInstallStatus.installerOpened) {
        Dialogs.showSnackbar(context, result.message);
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      Dialogs.hideLoading(context);
      Dialogs.showSnackbar(context, 'Could not download the update right now.');
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Notifications Required'),
        content: const Text(
          'Swift Chat needs notification permissions to alert you '
          'about new messages. Please enable notifications in settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              AppSettings.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _navigateToLogin() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => LoginScreen(
          isDarkMode: widget.isDarkMode,
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    );
  }

  void _navigateToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => HomeScreen(
          isDarkMode: widget.isDarkMode,
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _navigationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.fromARGB(255, 23, 39, 55),
              Color.fromARGB(255, 3, 67, 82),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SlideTransition(
                position: _logoSlide,
                child: FadeTransition(
                  opacity: _logoFade,
                  child: Image.asset(
                    'assets/images/icon.png',
                    width: 100,
                    height: 100,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FadeTransition(
                opacity: _textFade,
                child: const Text(
                  'Swift Chat',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              const CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
