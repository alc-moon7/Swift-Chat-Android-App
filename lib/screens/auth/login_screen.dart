import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:swift_chat/api/apis.dart';
import 'package:swift_chat/helper/dialogs.dart';
import 'package:swift_chat/screens/home_screen.dart';
import 'package:swift_chat/services/notification_service.dart';

class LoginScreen extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;

  const LoginScreen({
    Key? key,
    required this.isDarkMode,
    required this.onThemeChanged,
  }) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _controller;
  late Animation<Offset> _logoSlide;
  late Animation<double> _logoFade;
  late Animation<double> _textFade;
  late Animation<double> _buttonFade;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _controller.forward();
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

    _buttonFade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.7, 1.0, curve: Curves.easeIn),
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    Dialogs.showLoading(context);

    try {
      final userCredential = await AuthService.signInWithGoogle();
      final user = userCredential.user;

      if (user != null && mounted) {
        await _saveUserToFirestoreIfNotExists(user);
        await NotificationService.syncTokenForUser(user);
        _navigateToHome();
      }
    } on NoInternetException catch (e) {
      _handleError(e.toString());
    } on SignInCanceledException catch (e) {
      _handleError(e.toString());
    } on AuthException catch (e) {
      _handleError(e.toString());
    } on FirebaseAuthException catch (e) {
      _handleError('Authentication error: ${e.message}');
    } catch (e) {
      _handleError('An unexpected error occurred');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveUserToFirestoreIfNotExists(User user) async {
    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final userDoc = await userRef.get();
    final existingData = userDoc.data() ?? const <String, dynamic>{};

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
      'isOnline': true,
      'lastActiveAt': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
      if (!userDoc.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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

  void _handleError(String message) {
    if (mounted) {
      Dialogs.hideLoading(context);
      Dialogs.showSnackbar(context, message);
    }
  }

  void _showComingSoonMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coming soon!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.fromARGB(255, 64, 131, 198),
              Color.fromARGB(255, 6, 133, 161),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLogoAnimation(),
                const SizedBox(height: 40),
                _buildSignInButton(mq),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoAnimation() {
    return SlideTransition(
      position: _logoSlide,
      child: FadeTransition(
        opacity: _logoFade,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Image.asset(
                'assets/images/icon.png',
                width: 100,
                height: 100,
              ),
            ),
            FadeTransition(
              opacity: _textFade,
              child: const Text(
                'Swift Chat',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignInButton(Size mq) {
    return FadeTransition(
      opacity: _buttonFade,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          children: [
            SizedBox(
              width: mq.width,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF757575),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFFEEEEEE)),
                  ),
                ),
                onPressed: _handleGoogleSignIn,
                icon: Image.asset(
                  'assets/images/google.png',
                  height: 20,
                  width: 20,
                ),
                label: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Continue with Google',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: _showComingSoonMessage,
              icon: const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Color.fromARGB(255, 120, 200, 172),
              ),
              label: const Text(
                'Need more sign-in options?\nComing soon...😉',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
