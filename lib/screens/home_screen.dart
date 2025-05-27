// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:intl/intl.dart';
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
  final String? photoUrl;

  ChatUser({
    required this.id,
    required this.name,
    required this.email,
    this.photoUrl,
  });

  factory ChatUser.fromMap(Map<String, dynamic> data) {
    return ChatUser(
      id: data['uid'] ?? data['id'] ?? '',
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      photoUrl: data['photoUrl'] ?? data['photo'] ?? '',
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
      if (mounted) {
        _showInAppNotification(message);
      }
    });
  }

  void _showInAppNotification(RemoteMessage message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(message.notification?.title ?? 'New Message'),
        content: Text(message.notification?.body ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (message.data['chatId'] != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToChat(message.data['chatId']);
              },
              child: const Text('View'),
            ),
        ],
      ),
    );
  }

  void _navigateToChat(String? chatId) {
    if (chatId == null || !mounted) return;
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

  String _getChatId(String uid1, String uid2) {
    return uid1.compareTo(uid2) < 0 ? '$uid1-$uid2' : '$uid2-$uid1';
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Center(child: Text('User not logged in'));
    }

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
        child: const Icon(Icons.person_add),
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A237E), Color(0xFF0D47A1)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildUserHeader(),
                  const SizedBox(height: 16),
                  Expanded(child: _buildUserList()),
                ],
              ),
            ),
          ),
          if (_isMenuOpen)
            GestureDetector(
              onTap: () => setState(() => _isMenuOpen = false),
              child: Container(color: Colors.black.withOpacity(0.3)),
            ),
          _buildSideMenu(),
        ],
      ),
    );
  }

  Widget _buildUserHeader() {
    return SizedBox(
      height: 100,
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundImage: _user!.photoURL != null
                ? NetworkImage(_user!.photoURL!)
                : const AssetImage('assets/images/default_avatar.png')
                    as ImageProvider,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _user!.displayName ?? 'User',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _user!.email ?? 'No email',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserList() {
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
            return _buildUserListItem(users[index]);
          },
        );
      },
    );
  }

  Widget _buildUserListItem(ChatUser user) {
    final chatId = _getChatId(_user!.uid, user.id);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('messages')
          .where('chatId', isEqualTo: chatId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        String lastMessage = 'No messages yet';
        String timeString = '';
        bool isMe = false;

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final message = snapshot.data!.docs.first;
          lastMessage = message['content'] ?? '';
          final timestamp = message['timestamp'] as Timestamp?;
          isMe = message['senderId'] == _user!.uid;

          if (timestamp != null) {
            timeString = DateFormat('h:mm a')
                .format(timestamp.toDate())
                .replaceAll(':', '.')
                .toLowerCase();
          }
        }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: user.photoUrl != null
                  ? NetworkImage(user.photoUrl!)
                  : const AssetImage('assets/images/default_avatar.png')
                      as ImageProvider,
            ),
            title: Text(
              user.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Row(
              children: [
                Expanded(
                  child: Text(
                    isMe ? 'You: $lastMessage' : lastMessage,
                    style: const TextStyle(color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  timeString,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    peerId: user.id,
                    peerName: user.name,
                    peerPhoto: user.photoUrl,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSideMenu() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      left: _isMenuOpen ? 0 : -MediaQuery.of(context).size.width * 0.7,
      top: 0,
      bottom: 0,
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 40),
            ListTile(
              leading: CircleAvatar(
                radius: 25,
                backgroundImage: _user!.photoURL != null
                    ? NetworkImage(_user!.photoURL!)
                    : const AssetImage('assets/images/default_avatar.png')
                        as ImageProvider,
              ),
              title: Text(
                _user!.displayName ?? 'User',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              subtitle: Text(
                _user!.email ?? 'No email',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
              trailing: IconButton(
                icon: Icon(
                  widget.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  color: Colors.white70,
                ),
                onPressed: () => widget.onThemeChanged(!widget.isDarkMode),
              ),
            ),
            const Divider(color: Colors.tealAccent),
            ..._menuItems.map((item) => ListTile(
                  leading: Icon(
                    item['icon'],
                    color: const Color(0xFF00BCD4),
                  ),
                  title: Text(
                    item['title'],
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () => setState(() => _isMenuOpen = false),
                )),
          ],
        ),
      ),
    );
  }

  void _showAddUserDialog() {
    if (_isDialogOpen || !mounted) return;
    _isDialogOpen = true;

    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add User by Email'),
          content: TextField(
            controller: emailController,
            decoration: const InputDecoration(hintText: 'Enter user email'),
            keyboardType: TextInputType.emailAddress,
          ),
          actions: [
            TextButton(
              onPressed: () {
                _isDialogOpen = false;
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final email = emailController.text.trim();
                if (!mounted) return;
                Navigator.pop(context);
                _isDialogOpen = false;

                if (email.isEmpty) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter email')),
                    );
                  }
                  return;
                }

                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      const Center(child: CircularProgressIndicator()),
                );

                try {
                  final query = await FirebaseFirestore.instance
                      .collection('users')
                      .where('email', isEqualTo: email)
                      .limit(1)
                      .get();

                  if (!mounted) return;
                  Navigator.pop(context); // Close loading

                  if (query.docs.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('User not found')),
                    );
                    return;
                  }

                  final peerUser = ChatUser.fromMap(query.docs.first.data());

                  // Add to contacts
                  await FirebaseFirestore.instance
                      .collection('chat_users')
                      .doc(_user!.uid)
                      .collection('contacts')
                      .doc(peerUser.id)
                      .set({
                    'uid': peerUser.id,
                    'name': peerUser.name,
                    'email': peerUser.email,
                    'photoUrl': peerUser.photoUrl,
                    'lastMessageTime': FieldValue.serverTimestamp(),
                  });

                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          peerId: peerUser.id,
                          peerName: peerUser.name,
                          peerPhoto: peerUser.photoUrl,
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${e.toString()}')),
                    );
                  }
                }
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
  }
}
