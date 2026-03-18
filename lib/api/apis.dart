import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:swift_chat/services/notification_service.dart';
import 'package:swift_chat/services/presence_service.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _googleServerClientId =
      '205981391089-1v9tq6c2rn8t3te7ndacuhb9or3eh5di.apps.googleusercontent.com';
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: _googleServerClientId,
  );

  static Future<bool> checkInternetConnection() async {
    try {
      await InternetAddress.lookup('google.com');
      return true;
    } on SocketException {
      return false;
    }
  }

  static Future<UserCredential> signInWithGoogle() async {
    try {
      if (!await checkInternetConnection()) {
        throw NoInternetException();
      }

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw SignInCanceledException();

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      if (googleAuth.idToken == null || googleAuth.idToken!.isEmpty) {
        throw AuthException(
          'Google sign-in could not get a valid ID token. Please try again.',
        );
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } on PlatformException catch (e) {
      throw AuthException(_mapGoogleSignInError(e));
    } on FirebaseAuthException catch (e) {
      throw AuthException('Authentication failed: ${e.message}');
    }
  }

  static String _mapGoogleSignInError(PlatformException error) {
    final details = [
      error.code,
      if ((error.message ?? '').isNotEmpty) error.message!,
    ].join(' ').toLowerCase();

    if (details.contains('network')) {
      return 'Network problem detected. Please check your internet and try again.';
    }

    if (details.contains('canceled') || details.contains('cancelled')) {
      return 'Sign-in process canceled.';
    }

    if (details.contains('developer_error') || details.contains('status code: 10')) {
      return 'Google sign-in configuration was refreshed. Please reinstall the app and try again.';
    }

    return error.message ??
        'Google sign-in failed unexpectedly. Please try again.';
  }

  static Future<void> signOut() async {
    final currentUser = _auth.currentUser;

    if (currentUser != null) {
      await Future.wait([
        PresenceService.instance
            .stop(user: currentUser, markOffline: true)
            .timeout(const Duration(seconds: 3), onTimeout: () {}),
        NotificationService.clearTokenForUser(currentUser)
            .timeout(const Duration(seconds: 3), onTimeout: () {}),
      ]).catchError((error) {
        return <Future<void>>[];
      });
    }

    await _auth.signOut();

    unawaited(
      _googleSignIn.signOut().catchError((_) => null),
    );
  }
}

// Custom Exceptions
class NoInternetException implements Exception {
  @override
  String toString() => 'No internet connection. Please try again.';
}

class SignInCanceledException implements Exception {
  @override
  String toString() => 'Sign-in process canceled.';
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}
