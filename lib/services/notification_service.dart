import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:swift_chat/firebase_options.dart';

class NotificationService {
  NotificationService._();

  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static final StreamController<Map<String, dynamic>>
      _notificationTapController = StreamController.broadcast();

  static StreamSubscription<String>? _tokenRefreshSubscription;
  static bool _isInitialized = false;
  static Map<String, dynamic>? _initialNotificationData;

  static Stream<Map<String, dynamic>> get notificationTapStream =>
      _notificationTapController.stream;

  static Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    const androidInitializationSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInitializationSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _notificationsPlugin.initialize(
      const InitializationSettings(
        android: androidInitializationSettings,
        iOS: iosInitializationSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = _decodePayload(response.payload);
        if (payload.isNotEmpty) {
          _notificationTapController.add(payload);
        }
      },
    );

    await _requestPermissions();
    await _createNotificationChannel();

    FirebaseMessaging.onMessage.listen((message) async {
      await _showForegroundNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final payload = _normalizePayload(message.data);
      if (payload.isNotEmpty) {
        _notificationTapController.add(payload);
      }
    });

    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      _initialNotificationData = _normalizePayload(initialMessage.data);
    }

    _isInitialized = true;
  }

  static Future<void> syncTokenForUser(User user) async {
    final token = await _firebaseMessaging.getToken();
    if (token != null && token.isNotEmpty) {
      await _storeToken(user.uid, token);
    }

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _firebaseMessaging.onTokenRefresh.listen(
      (newToken) async {
        if (newToken.isNotEmpty) {
          await _storeToken(user.uid, newToken);
        }
      },
    );
  }

  static Future<void> clearTokenForUser(User? user) async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;

    if (user == null) {
      return;
    }

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'fcmToken': FieldValue.delete(),
      'lastTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Map<String, dynamic>? consumeInitialNotificationData() {
    final pendingPayload = _initialNotificationData;
    _initialNotificationData = null;
    return pendingPayload;
  }

  static Future<void> _requestPermissions() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint(
      'Notification permission: ${settings.authorizationStatus.name}',
    );
  }

  static Future<void> _createNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      'swift_chat_channel',
      'Swift Chat Notifications',
      description: 'Realtime message notifications',
      importance: Importance.max,
      playSound: true,
      showBadge: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  @pragma('vm:entry-point')
  static Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    debugPrint(
      '[Background notification] ${message.notification?.title} - ${message.notification?.body}',
    );
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title =
        (notification?.title ?? message.data['senderName'] ?? 'Swift Chat')
            .toString();
    final body =
        (notification?.body ?? message.data['body'] ?? 'New message')
            .toString();

    await _notificationsPlugin.show(
      message.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'swift_chat_channel',
          'Swift Chat Notifications',
          channelDescription: 'Realtime message notifications',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(_normalizePayload(message.data)),
    );
  }

  static Future<void> _storeToken(String userId, String token) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'fcmToken': token,
      'lastTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Map<String, dynamic> _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      debugPrint('Failed to decode notification payload.');
    }

    return <String, dynamic>{};
  }

  static Map<String, dynamic> _normalizePayload(
    Map<String, dynamic> payload,
  ) {
    return payload.map(
      (key, value) => MapEntry(key, value?.toString() ?? ''),
    );
  }
}
