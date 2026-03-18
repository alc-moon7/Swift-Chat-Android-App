import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:swift_chat/services/notification_service.dart';
import 'package:swift_chat/services/presence_service.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn();

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

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw AuthException('Authentication failed: ${e.message}');
    }
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
