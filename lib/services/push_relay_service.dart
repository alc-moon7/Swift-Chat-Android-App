import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PushRelayService {
  PushRelayService._();

  static const String _workerBaseUrl =
      'https://swift-chat-push.zerosmoon-ff.workers.dev';
  static final Uri _messageRelayUri =
      Uri.parse('$_workerBaseUrl/send-message-notification');

  static Future<void> sendMessageNotification({
    required String chatId,
    required String messageId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return;
    }

    try {
      final idToken = await currentUser.getIdToken();
      if ((idToken ?? '').isEmpty) {
        return;
      }

      final response = await http
          .post(
            _messageRelayUri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${idToken!}',
            },
            body: jsonEncode(<String, dynamic>{
              'chatId': chatId,
              'messageId': messageId,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Push relay rejected request: ${response.statusCode} ${response.body}',
        );
      }
    } catch (error) {
      debugPrint('Push relay failed: $error');
    }
  }
}
