import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PresenceService {
  PresenceService._();

  static final PresenceService instance = PresenceService._();

  Timer? _heartbeatTimer;
  String? _activeUserId;

  Future<void> start(User user) async {
    _activeUserId = user.uid;
    await _setPresence(
      userId: user.uid,
      isOnline: true,
      updateLastSeen: false,
    );

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _refreshPresence(user.uid),
    );
  }

  Future<void> pause(User user) async {
    _heartbeatTimer?.cancel();
    await _setPresence(
      userId: user.uid,
      isOnline: false,
      updateLastSeen: true,
    );
  }

  Future<void> stop({
    User? user,
    bool markOffline = false,
  }) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    if (markOffline && user != null) {
      await _setPresence(
        userId: user.uid,
        isOnline: false,
        updateLastSeen: true,
      );
    }

    _activeUserId = null;
  }

  Future<void> _refreshPresence(String userId) async {
    if (_activeUserId != userId) {
      return;
    }

    await _setPresence(
      userId: userId,
      isOnline: true,
      updateLastSeen: false,
    );
  }

  Future<void> _setPresence({
    required String userId,
    required bool isOnline,
    required bool updateLastSeen,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'isOnline': isOnline,
        'lastActiveAt': FieldValue.serverTimestamp(),
        if (updateLastSeen) 'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Presence update failed: $error');
    }
  }
}
