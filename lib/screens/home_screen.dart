import 'dart:async';

import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:swift_chat/screens/chatscreen.dart';
import 'package:swift_chat/services/chat_user_service.dart';
import 'package:swift_chat/services/notification_service.dart';

class ChatUser {
  final String id;
  final String name;
  final String email;
  final String? photo;

  ChatUser({
    required this.id,
    required this.name,
    required this.email,
    this.photo,
  });

  factory ChatUser.fromMap(Map<String, dynamic> data) {
    return ChatUser(
      id: data['uid'] ?? '',
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      photo: data['photoUrl'] ?? '',
    );
  }
}

class HomeScreen extends StatefulWidget {
  final bool isDarkMode;
  final Function(bool) onThemeChanged;

  const HomeScreen({
    Key? key,
    required this.isDarkMode,
    required this.onThemeChanged,
  }) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isMenuOpen = false;
  bool _isDialogOpen = false;
  final User? _user = FirebaseAuth.instance.currentUser;
  late StreamSubscription _notificationSubscription;

  final List<Map<String, dynamic>> _menuItems = [
    {'title': 'My Profile', 'icon': Icons.person},
    {'title': 'Wallet', 'icon': Icons.wallet},
    {'title': 'New Group', 'icon': Icons.group_add},
    {'title': 'Contacts', 'icon': Icons.contacts},
    {'title': 'Calls', 'icon': Icons.call},
    {'title': 'Saved Messages', 'icon': Icons.bookmark},
    {'title': 'Settings', 'icon': Icons.settings},
    {'title': 'Invite Friends', 'icon': Icons.share},
    {'title': 'Swift Chat Features', 'icon': Icons.star},
  ];

  @override
  void initState() {
    super.initState();
    _setupNotifications();
  }

  @override
  void dispose() {
    _notificationSubscription.cancel();
    super.dispose();
  }

  void _setupNotifications() {
    _notificationSubscription =
        NotificationService.messageStream.listen((message) {
      _showInAppNotification(message);
    });
  }

  void _showInAppNotification(RemoteMessage message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(message.notification?.title ?? 'New Message'),
        content: Text(message.notification?.body ?? ''),
        actions: [
          TextButton(
            child: const Text('Close'),
            onPressed: () => Navigator.pop(context),
          ),
          if (message.data['chatId'] != null)
            TextButton(
              child: const Text('View'),
              onPressed: () {
                Navigator.pop(context);
                _navigateToChat(message.data['chatId']);
              },
            ),
        ],
      ),
    );
  }

  void _navigateToChat(String? chatId) {
    if (chatId == null) return;

    // Implement your chat navigation logic here
    // Example:
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          peerId: chatId,
          peerName: 'Chat User',
          peerPhoto: null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Center(child: Text('User not logged in'));
    }

    final name = _user!.displayName ?? 'User';
    final email = _user!.email ?? 'No email available';
    final photoUrl = _user!.photoURL;

    return Scaffold(
      appBar: AppBar(
        elevation: 4,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => setState(() => _isMenuOpen = !_isMenuOpen),
        ),
        title: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedTextKit(
            repeatForever: true,
            animatedTexts: [
              ColorizeAnimatedText(
                'Swift Chat',
                textStyle: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
                colors: [Colors.white, Colors.blueAccent, Colors.purpleAccent],
                speed: const Duration(milliseconds: 400),
              ),
              ColorizeAnimatedText(
                'সুইফ্ট চ্যাট',
                textStyle: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
                colors: [Colors.white, Colors.blueAccent, Colors.purpleAccent],
                speed: const Duration(milliseconds: 400),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddUserDialog,
        backgroundColor: const Color(0xFF00BCD4),
        foregroundColor: Colors.white,
        child: const Icon(Icons.person_add),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A237E), Color(0xFF0D47A1)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SizedBox(
                    height: 100,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundImage: photoUrl != null
                              ? NetworkImage(photoUrl)
                              : const AssetImage(
                                      'assets/images/default_avatar.png')
                                  as ImageProvider,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                              Text(email,
                                  style: const TextStyle(
                                      fontSize: 14, color: Colors.white70)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(child: _buildAllUsers()),
                ],
              ),
            ),
          ),
          if (_isMenuOpen)
            GestureDetector(
              onTap: () => setState(() => _isMenuOpen = false),
              child: Container(color: Colors.black.withOpacity(0.3)),
            ),
          _buildSideMenu(name, email, photoUrl),
        ],
      ),
    );
  }

  Widget _buildAllUsers() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final users = snapshot.data!.docs
            .map((doc) => ChatUser.fromMap(doc.data() as Map<String, dynamic>))
            .where((user) => user.id != _user!.uid)
            .toList();

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.white24,
                  backgroundImage: user.photo != null
                      ? NetworkImage(user.photo!)
                      : const AssetImage('assets/images/default_avatar.png')
                          as ImageProvider,
                ),
                title: Text(user.name,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w500)),
                subtitle: Text(user.email,
                    style: const TextStyle(color: Colors.white70)),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        peerId: user.id,
                        peerName: user.name,
                        peerPhoto: user.photo,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSideMenu(String name, String email, String? photoUrl) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      left: _isMenuOpen ? 0 : -MediaQuery.of(context).size.width * 0.7,
      top: 0,
      bottom: 0,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.7,
        padding: const EdgeInsets.only(top: 40),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D47A1), Color(0xFF1A237E)],
          ),
        ),
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                radius: 25,
                backgroundImage: photoUrl != null
                    ? NetworkImage(photoUrl)
                    : const AssetImage('assets/images/default_avatar.png')
                        as ImageProvider,
              ),
              title: Text(name,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              subtitle: Text(email,
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
              trailing: IconButton(
                icon: Icon(
                  widget.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  color: Colors.white70,
                ),
                onPressed: () {
                  widget.onThemeChanged(!widget.isDarkMode);
                },
              ),
            ),
            const Divider(color: Colors.tealAccent),
            ..._menuItems.map((item) {
              return ListTile(
                leading: Icon(item['icon'], color: const Color(0xFF00BCD4)),
                title: Text(
                  item['title'],
                  style: const TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.w500),
                ),
                onTap: () => setState(() => _isMenuOpen = false),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  void _showAddUserDialog() {
    if (_isDialogOpen) return;
    _isDialogOpen = true;

    final TextEditingController _emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add User by Email'),
        content: TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'Enter user email'),
        ),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () {
              _isDialogOpen = false;
              Navigator.pop(context);
            },
          ),
          TextButton(
            child: const Text('Connect'),
            onPressed: () async {
              final email = _emailController.text.trim();
              Navigator.pop(context);
              _isDialogOpen = false;

              if (email.isNotEmpty) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      const Center(child: CircularProgressIndicator()),
                );
                await _connectWithUserByEmail(email);
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid email.')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _connectWithUserByEmail(String email) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final querySnapshot = await firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final userData = querySnapshot.docs.first.data();
        final peerId = querySnapshot.docs.first.id;
        final peerName = userData['name'] ?? 'Unknown';
        final peerEmail = userData['email'] ?? '';
        final peerPhoto = userData['photo'] ?? '';

        await addToChatUsers(
          peerUserId: peerId,
          peerName: peerName,
          peerEmail: peerEmail,
          peerPhotoUrl: peerPhoto,
        );

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              peerId: peerId,
              peerName: peerName,
              peerPhoto: peerPhoto,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No user found with this email.')),
        );
      }
    } catch (e) {
      debugPrint('Error adding user by email: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error adding user.')),
      );
    }
  }
}
