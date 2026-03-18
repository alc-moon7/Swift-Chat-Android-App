import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:swift_chat/api/apis.dart';
import 'package:swift_chat/helper/avatar_provider.dart';
import 'package:swift_chat/helper/dialogs.dart';
import 'package:swift_chat/screens/chatscreen.dart';
import 'package:swift_chat/services/notification_service.dart';
import 'package:swift_chat/services/presence_service.dart';
import 'package:image_picker/image_picker.dart';

class ChatUser {
  final String id;
  final String name;
  final String email;
  final String? photoUrl;
  final String? photoBase64;
  final bool isOnline;
  final Timestamp? lastSeen;
  final Timestamp? lastActiveAt;
  final String phone;
  final String bio;
  final String username;
  final Timestamp? birthday;

  ChatUser({
    required this.id,
    required this.name,
    required this.email,
    this.photoUrl,
    this.photoBase64,
    this.isOnline = false,
    this.lastSeen,
    this.lastActiveAt,
    this.phone = '',
    this.bio = '',
    this.username = '',
    this.birthday,
  });

  factory ChatUser.fromMap(Map<String, dynamic> data) {
    return ChatUser(
      id: data['uid'] ?? data['id'] ?? '',
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      photoUrl: data['photoUrl'] ?? data['photo'] ?? '',
      photoBase64: data['photoBase64'] ?? data['avatarBase64'] ?? '',
      isOnline: data['isOnline'] == true,
      lastSeen: data['lastSeen'] as Timestamp?,
      lastActiveAt: data['lastActiveAt'] as Timestamp?,
      phone: data['phone'] ?? '',
      bio: data['bio'] ?? '',
      username: data['username'] ?? '',
      birthday: data['birthday'] as Timestamp?,
    );
  }
}

class _MessagePreviewData {
  final String subtitle;
  final String timeString;
  final bool isMe;
  final bool isDeleted;

  const _MessagePreviewData({
    required this.subtitle,
    required this.timeString,
    required this.isMe,
    this.isDeleted = false,
  });
}

enum _HomeTab {
  chats,
  contacts,
  settings,
  profile,
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final User? _user = FirebaseAuth.instance.currentUser;
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  final ImagePicker _imagePicker = ImagePicker();

  bool _isDialogOpen = false;
  bool _isSearchOpen = false;
  bool _isSigningOut = false;
  String _searchQuery = '';
  _HomeTab _selectedTab = _HomeTab.chats;

  bool get _isDark => widget.isDarkMode;
  User get _currentUser => _user!;
  Color get _pageColor =>
      _isDark ? const Color(0xFF17212B) : const Color(0xFFF3F7FB);
  Color get _pageAccentColor =>
      _isDark ? const Color(0xFF16232E) : const Color(0xFFEAF2FB);
  Color get _surfaceColor =>
      _isDark ? const Color(0xFF1E2C38) : Colors.white;
  Color get _surfaceSoftColor =>
      _isDark ? const Color(0xFF223445) : const Color(0xFFE8F1FA);
  Color get _accentColor =>
      _isDark ? const Color(0xFF2EA6FF) : const Color(0xFF1485EA);
  Color get _mutedTextColor =>
      _isDark ? const Color(0xFF8D9AA6) : const Color(0xFF708190);
  Color get _primaryTextColor =>
      _isDark ? Colors.white : const Color(0xFF17212B);
  Color get _secondaryTextColor =>
      _isDark ? Colors.white70 : const Color(0xFF51606D);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupNotifications();
    _startPresenceSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PresenceService.instance.stop();
    _notificationSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_user == null) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        PresenceService.instance.start(_currentUser);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        PresenceService.instance.pause(_currentUser);
        break;
    }
  }

  void _startPresenceSync() {
    if (_user != null) {
      PresenceService.instance.start(_currentUser);
    }
  }

  DocumentReference<Map<String, dynamic>> get _currentUserDocRef =>
      FirebaseFirestore.instance.collection('users').doc(_currentUser.uid);

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _currentUserDocStream =>
      _currentUserDocRef.snapshots();

  ChatUser _currentProfileFromData(Map<String, dynamic>? data) {
    final fallbackData = <String, dynamic>{
      'uid': _currentUser.uid,
      'name': _currentUser.displayName ?? 'User',
      'email': _currentUser.email ?? '',
      'photoUrl': _currentUser.photoURL ?? '',
    };

    return ChatUser.fromMap({
      ...fallbackData,
      ...?data,
    });
  }

  Future<void> _saveProfileData(Map<String, dynamic> values) async {
    await _currentUserDocRef.set(values, SetOptions(merge: true));
  }

  Future<void> _pickAndSaveProfilePhoto(ImageSource source) async {
    try {
      final selectedImage = await _imagePicker.pickImage(
        source: source,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 72,
      );

      if (selectedImage == null) {
        return;
      }

      final bytes = await selectedImage.readAsBytes();
      await _saveProfileData({
        'photoBase64': bytes.isNotEmpty ? base64Encode(bytes) : '',
        'photoUrl': '',
        'photoUpdatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }

      Dialogs.showSnackbar(context, 'Profile photo updated');
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }

      final message = error.code == 'channel-error'
          ? 'Photo picker did not start. Please reopen the app once and try again.'
          : 'Could not update profile photo right now.';
      Dialogs.showSnackbar(context, message);
      debugPrint('Profile photo picker error: $error');
    } catch (error) {
      if (!mounted) {
        return;
      }

      Dialogs.showSnackbar(context, 'Could not update profile photo right now.');
      debugPrint('Unexpected profile photo error: $error');
    }
  }

  Future<void> _showSetPhotoOptions() async {
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set Profile Photo',
                  style: TextStyle(
                    color: _primaryTextColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _buildProfileActionRowTile(
                  icon: Icons.photo_library_rounded,
                  title: 'Choose from gallery',
                  subtitle: 'Pick a new profile photo from your phone',
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickAndSaveProfilePhoto(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 10),
                _buildProfileActionRowTile(
                  icon: Icons.photo_camera_rounded,
                  title: 'Take a photo',
                  subtitle: 'Use your camera to capture a new profile photo',
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickAndSaveProfilePhoto(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditProfileSheet(ChatUser profile) async {
    final parentContext = context;
    final nameController = TextEditingController(text: profile.name);
    final phoneController = TextEditingController(text: profile.phone);
    final bioController = TextEditingController(text: profile.bio);
    final usernameController = TextEditingController(
      text: profile.username,
    );
    DateTime? selectedBirthday = profile.birthday?.toDate();
    bool isSaving = false;

    Future<void> pickBirthday(StateSetter setSheetState) async {
      final pickedDate = await showDatePicker(
        context: parentContext,
        initialDate: selectedBirthday ?? DateTime(2000, 1, 1),
        firstDate: DateTime(1950),
        lastDate: DateTime.now(),
      );

      if (pickedDate != null) {
        setSheetState(() {
          selectedBirthday = pickedDate;
        });
      }
    }

    await showModalBottomSheet<void>(
      context: parentContext,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: _surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 5,
                          decoration: BoxDecoration(
                            color: _mutedTextColor.withOpacity(0.28),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Edit Profile',
                        style: TextStyle(
                          color: _primaryTextColor,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildProfileInputField(
                        controller: nameController,
                        label: 'Name',
                        hintText: 'Your display name',
                      ),
                      const SizedBox(height: 12),
                      _buildProfileInputField(
                        controller: phoneController,
                        label: 'Mobile',
                        hintText: '+8801XXXXXXXXX',
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      _buildProfileInputField(
                        controller: bioController,
                        label: 'Bio',
                        hintText: 'Say something about yourself',
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      _buildProfileInputField(
                        controller: usernameController,
                        label: 'Username',
                        hintText: '@swiftchat',
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: isSaving
                            ? null
                            : () => pickBirthday(setSheetState),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: _surfaceSoftColor,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Birthday',
                                style: TextStyle(
                                  color: _mutedTextColor,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                selectedBirthday != null
                                    ? DateFormat('dd MMM yyyy')
                                        .format(selectedBirthday!)
                                    : 'Select your birthday',
                                style: TextStyle(
                                  color: _primaryTextColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  FocusScope.of(sheetContext).unfocus();
                                  setSheetState(() {
                                    isSaving = true;
                                  });

                                  final normalizedName =
                                      nameController.text.trim();
                                  final normalizedPhone =
                                      phoneController.text.trim();
                                  final normalizedBio =
                                      bioController.text.trim();
                                  final normalizedUsername =
                                      usernameController.text.trim();

                                  try {
                                    await _saveProfileData({
                                      'name': normalizedName.isNotEmpty
                                          ? normalizedName
                                          : profile.name,
                                      'phone': normalizedPhone,
                                      'bio': normalizedBio,
                                      'username': _normalizeUsername(
                                        normalizedUsername,
                                      ),
                                      'birthday': selectedBirthday != null
                                          ? Timestamp.fromDate(
                                              selectedBirthday!,
                                            )
                                          : null,
                                      'profileUpdatedAt':
                                          FieldValue.serverTimestamp(),
                                    });

                                    if (!mounted) {
                                      return;
                                    }

                                    if (Navigator.of(sheetContext).canPop()) {
                                      Navigator.of(sheetContext).pop();
                                    }

                                    Dialogs.showSnackbar(
                                      parentContext,
                                      'Profile updated successfully',
                                    );
                                  } catch (error) {
                                    if (!mounted) {
                                      return;
                                    }

                                    setSheetState(() {
                                      isSaving = false;
                                    });
                                    Dialogs.showSnackbar(
                                      parentContext,
                                      'Could not update profile right now.',
                                    );
                                    debugPrint(
                                      'Profile update failed: $error',
                                    );
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text('Save Changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
    bioController.dispose();
    usernameController.dispose();
  }

  String _normalizeUsername(String username) {
    final normalized = username.trim().replaceAll(' ', '');
    if (normalized.isEmpty) {
      return '';
    }

    return normalized.startsWith('@') ? normalized : '@$normalized';
  }

  void _setupNotifications() {
    _notificationSubscription =
        NotificationService.notificationTapStream.listen((payload) {
      _openChatFromNotificationPayload(payload);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingPayload =
          NotificationService.consumeInitialNotificationData();
      if (pendingPayload != null) {
        _openChatFromNotificationPayload(pendingPayload);
      }
    });
  }

  Future<void> _openChatFromNotificationPayload(
    Map<String, dynamic> payload,
  ) async {
    final peerId = (payload['peerId'] ?? payload['senderId'] ?? '').toString();
    if (peerId.isEmpty || !mounted) {
      return;
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(peerId)
        .get();

    if (!mounted) {
      return;
    }

    final peerData = userDoc.data();
    final peerUser = peerData != null
        ? ChatUser.fromMap(peerData)
        : ChatUser(
            id: peerId,
            name: (payload['senderName'] ?? 'Chat User').toString(),
            email: '',
            photoUrl: null,
          );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          peerId: peerUser.id,
          peerName: peerUser.name,
          peerPhoto: peerUser.photoUrl,
          peerPhotoBase64: peerUser.photoBase64,
        ),
      ),
    );
  }

  String _chatIdForPeer(String peerId) {
    final ids = [_currentUser.uid, peerId]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  String _deletedPreviewText() => 'This message was deleted';

  bool _isDeletedPreviewText(String text) =>
      text.trim().toLowerCase() == _deletedPreviewText().toLowerCase();

  Future<_MessagePreviewData?> _loadLegacyPreview(String peerId) async {
    final chatId = _chatIdForPeer(peerId);
    final latestMessageQuery = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(25)
        .get();

    if (latestMessageQuery.docs.isEmpty) {
      return null;
    }

    for (final doc in latestMessageQuery.docs) {
      final latestMessage = doc.data();
      final deletedFor =
          List<String>.from(latestMessage['deletedFor'] ?? const []);
      if (deletedFor.contains(_currentUser.uid)) {
        continue;
      }

      final isDeleted = latestMessage['deletedForEveryone'] == true;
      final text = isDeleted
          ? _deletedPreviewText()
          : (latestMessage['text'] as String? ?? '').trim();
      final timestamp = latestMessage['timestamp'] as Timestamp?;
      final senderId = (latestMessage['senderId'] as String? ?? '').trim();

      return _MessagePreviewData(
        subtitle: text.isNotEmpty ? text : 'No messages yet',
        timeString: _formatMessageTime(timestamp),
        isMe: senderId == _currentUser.uid,
        isDeleted: isDeleted,
      );
    }

    return null;
  }

  bool _isPeerTyping(Map<String, dynamic>? chatData, String peerId) {
    final typingData = Map<String, dynamic>.from(chatData?['typing'] ?? const {});
    return typingData[peerId] == true;
  }

  bool _isUserActiveNow(ChatUser user) {
    if (user.isOnline) {
      return true;
    }

    final lastActive = user.lastActiveAt?.toDate();
    if (lastActive == null) {
      return false;
    }

    return DateTime.now().difference(lastActive).inSeconds <= 90;
  }

  List<ChatUser> _sortUsersByRecentChats(
    List<ChatUser> users,
    List<QueryDocumentSnapshot> chatDocs,
  ) {
    final lastMessageTimes = <String, Timestamp>{};

    for (final doc in chatDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final members = List<String>.from(data['members'] ?? const []);
      final otherUserId = members.firstWhere(
        (memberId) => memberId != _currentUser.uid,
        orElse: () => '',
      );

      if (otherUserId.isEmpty) continue;

      final timestamp = data['lastMessageTime'];
      if (timestamp is Timestamp) {
        lastMessageTimes[otherUserId] = timestamp;
      }
    }

    final sortedUsers = [...users];
    sortedUsers.sort((a, b) {
      final aTime = lastMessageTimes[a.id];
      final bTime = lastMessageTimes[b.id];

      if (aTime != null && bTime != null) {
        return bTime.compareTo(aTime);
      }
      if (aTime != null) return -1;
      if (bTime != null) return 1;

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return sortedUsers;
  }

  void _selectTab(_HomeTab tab) {
    setState(() {
      _selectedTab = tab;
      if (tab != _HomeTab.chats && tab != _HomeTab.contacts) {
        _closeSearch();
      }
    });
  }

  void _openSearch() {
    setState(() {
      _isSearchOpen = true;
    });
  }

  void _closeSearch() {
    setState(() {
      _isSearchOpen = false;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  void _updateTheme(bool value) {
    if (widget.isDarkMode == value) {
      return;
    }

    widget.onThemeChanged(value);
  }

  Future<void> _signOut() async {
    if (_isSigningOut) {
      return;
    }

    setState(() {
      _isSigningOut = true;
    });

    try {
      await AuthService.signOut();
    } catch (error) {
      debugPrint('Sign out failed: $error');
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isSigningOut = false;
    });

    if (FirebaseAuth.instance.currentUser != null) {
      Dialogs.showSnackbar(context, 'Could not sign out right now.');
      return;
    }

    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _handleMenuAction(String value) async {
    switch (value) {
      case 'add_user':
        _showAddUserDialog();
        break;
      case 'theme':
        _updateTheme(!widget.isDarkMode);
        break;
      case 'logout':
        await _signOut();
        break;
      default:
        break;
    }
  }

  String _titleForTab() {
    switch (_selectedTab) {
      case _HomeTab.chats:
        return 'Swift Chat';
      case _HomeTab.contacts:
        return 'Contacts';
      case _HomeTab.settings:
        return 'Settings';
      case _HomeTab.profile:
        return 'Profile';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Scaffold(
        body: Center(child: Text('User not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        backgroundColor: _pageColor,
        elevation: 0,
        titleSpacing: 16,
        title: _isSearchOpen ? _buildSearchField() : _buildTitle(),
        actions: [
          IconButton(
            onPressed: _isSearchOpen ? _closeSearch : _openSearch,
            icon: Icon(
              _isSearchOpen ? Icons.close_rounded : Icons.search_rounded,
              color: _primaryTextColor,
            ),
          ),
          PopupMenuButton<String>(
            color: _surfaceColor,
            icon: Icon(Icons.more_vert_rounded, color: _primaryTextColor),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'add_user',
                child: Text(
                  'Add user',
                  style: TextStyle(color: _primaryTextColor),
                ),
              ),
              PopupMenuItem<String>(
                value: 'theme',
                child: Text(
                  'Toggle theme',
                  style: TextStyle(color: _primaryTextColor),
                ),
              ),
              PopupMenuItem<String>(
                value: 'logout',
                child: Text(
                  'Logout',
                  style: TextStyle(color: _primaryTextColor),
                ),
              ),
            ],
          ),
        ],
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_pageColor, _pageAccentColor],
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _buildCurrentTab(),
        ),
      ),
      floatingActionButton:
          _selectedTab == _HomeTab.chats ? _buildFloatingActions() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildTitle() {
    return Text(
      _titleForTab(),
      style: TextStyle(
        color: _primaryTextColor,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      style: TextStyle(color: _primaryTextColor),
      cursorColor: _accentColor,
      decoration: InputDecoration(
        hintText: 'Search chats',
        hintStyle: TextStyle(color: _mutedTextColor),
        border: InputBorder.none,
      ),
      onChanged: (value) {
        setState(() {
          _searchQuery = value.trim().toLowerCase();
        });
      },
    );
  }

  Widget _buildCurrentTab() {
    switch (_selectedTab) {
      case _HomeTab.chats:
        return _buildUsersTab(showArchivedTile: true);
      case _HomeTab.contacts:
        return _buildUsersTab(showArchivedTile: false);
      case _HomeTab.settings:
        return _buildSettingsTab();
      case _HomeTab.profile:
        return _buildProfileTab();
    }
  }

  Widget _buildUsersTab({required bool showArchivedTile}) {
    return SafeArea(
      key: ValueKey<String>('users-${showArchivedTile.toString()}'),
      top: false,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: TextStyle(color: _secondaryTextColor),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data!.docs
              .map((doc) => ChatUser.fromMap(doc.data() as Map<String, dynamic>))
              .where((user) =>
                  user.id.isNotEmpty && user.id != _currentUser.uid)
              .where((user) {
                if (_searchQuery.isEmpty) return true;
                final haystack =
                    '${user.name} ${user.email}'.toLowerCase().trim();
                return haystack.contains(_searchQuery);
              })
              .toList();

          if (users.isEmpty) {
            return _buildEmptyState(
              title: showArchivedTile ? 'No chats yet' : 'No contacts found',
              subtitle: showArchivedTile
                  ? 'Use the add button to start a conversation.'
                  : 'Try another name or email.',
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('chats')
                .where('members', arrayContains: _currentUser.uid)
                .snapshots(),
            builder: (context, chatSnapshot) {
              final chatDocs = chatSnapshot.data?.docs ?? const [];
              final chatDataByUserId = <String, Map<String, dynamic>>{};

              for (final doc in chatDocs) {
                final data = doc.data() as Map<String, dynamic>;
                final members = List<String>.from(data['members'] ?? const []);
                final otherUserId = members.firstWhere(
                  (memberId) => memberId != _currentUser.uid,
                  orElse: () => '',
                );

                if (otherUserId.isNotEmpty) {
                  chatDataByUserId[otherUserId] = data;
                }
              }

              final sortedUsers = showArchivedTile
                  ? _sortUsersByRecentChats(
                      users,
                      chatDocs,
                    )
                  : (users..sort(
                      (a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    ));

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 120),
                itemCount: sortedUsers.length + (showArchivedTile ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (context, index) {
                  if (showArchivedTile && index == 0) {
                    return _buildArchivedTile(sortedUsers.length);
                  }

                  final user =
                      sortedUsers[showArchivedTile ? index - 1 : index];
                  return _buildUserListItem(
                    user,
                    chatDataByUserId[user.id],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildArchivedTile(int count) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(22),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _surfaceSoftColor,
          ),
          child: Icon(
            Icons.archive_outlined,
            color: _primaryTextColor,
            size: 28,
          ),
        ),
        title: Text(
          'Archived Chats',
          style: TextStyle(
            color: _primaryTextColor,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        subtitle: Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text(
            'Keep quiet conversations out of the main list',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _mutedTextColor,
              fontSize: 14,
            ),
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _surfaceSoftColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: _primaryTextColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserListItem(ChatUser user, Map<String, dynamic>? chatData) {
    String subtitle = 'No messages yet';
    String timeString = '';
    bool isMe = false;
    bool isLastMessageRead = false;
    bool isDeletedPreview = false;
    int unreadCount = 0;
    final isOnline = _isUserActiveNow(user);
    final isPeerTyping = _isPeerTyping(chatData, user.id);

    if (chatData != null) {
      final previewOverrides =
          Map<String, dynamic>.from(chatData['previewOverrides'] ?? const {});
      final overrideData = previewOverrides[_currentUser.uid];
      final previewSource = overrideData is Map<String, dynamic>
          ? overrideData
          : overrideData is Map
              ? Map<String, dynamic>.from(overrideData)
              : chatData;

      subtitle = (previewSource['lastMessage'] as String?)?.trim().isNotEmpty ==
              true
          ? previewSource['lastMessage'] as String
          : subtitle;
      isMe = previewSource['lastMessageSenderId'] == _currentUser.uid;
      timeString =
          _formatMessageTime(previewSource['lastMessageTime'] as Timestamp?);
      isDeletedPreview = previewSource['lastMessageDeletedForEveryone'] == true ||
          _isDeletedPreviewText(subtitle);

      final unreadCounts =
          Map<String, dynamic>.from(chatData['unreadCounts'] ?? const {});
      final unreadValue = unreadCounts[_currentUser.uid];
      if (unreadValue is int) {
        unreadCount = unreadValue;
      } else if (unreadValue is num) {
        unreadCount = unreadValue.toInt();
      }

      final peerUnreadValue = unreadCounts[user.id];
      final peerUnreadCount = peerUnreadValue is int
          ? peerUnreadValue
          : peerUnreadValue is num
              ? peerUnreadValue.toInt()
              : 0;
      isLastMessageRead = isMe && peerUnreadCount == 0;
    }

    if (isPeerTyping) {
      subtitle = 'typing...';
      isMe = false;
      isDeletedPreview = false;
    }

    final needsLegacyPreview = subtitle == 'No messages yet';

    if (needsLegacyPreview) {
      return FutureBuilder<_MessagePreviewData?>(
        future: _loadLegacyPreview(user.id),
        builder: (context, snapshot) {
          final resolvedPreview = snapshot.data;
          return _buildUserTile(
            user,
            subtitle: resolvedPreview?.subtitle ?? subtitle,
            timeString: resolvedPreview?.timeString ?? timeString,
            isMe: resolvedPreview?.isMe ?? isMe,
            isDeletedPreview: resolvedPreview?.isDeleted ?? isDeletedPreview,
            isLastMessageRead: isLastMessageRead,
            unreadCount: unreadCount,
            isOnline: isOnline,
            isPeerTyping: isPeerTyping,
          );
        },
      );
    }

    return _buildUserTile(
      user,
      subtitle: subtitle,
      timeString: timeString,
      isMe: isMe,
      isDeletedPreview: isDeletedPreview,
      isLastMessageRead: isLastMessageRead,
      unreadCount: unreadCount,
      isOnline: isOnline,
      isPeerTyping: isPeerTyping,
    );
  }

  Widget _buildUserTile(
    ChatUser user, {
    required String subtitle,
    required String timeString,
    required bool isMe,
    required bool isDeletedPreview,
    required bool isLastMessageRead,
    required int unreadCount,
    required bool isOnline,
    required bool isPeerTyping,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                peerId: user.id,
                peerName: user.name,
                peerPhoto: user.photoUrl,
                peerPhotoBase64: user.photoBase64,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatar(
                photoUrl: user.photoUrl,
                photoBase64: user.photoBase64,
                name: user.name,
                showOnlineBadge: true,
                isOnline: isOnline,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              user.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _primaryTextColor,
                                fontWeight: unreadCount > 0
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 17,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            timeString,
                            style: TextStyle(
                              color: unreadCount > 0
                                  ? _accentColor
                                  : _mutedTextColor,
                              fontWeight: unreadCount > 0
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                if (isMe &&
                                    subtitle != 'No messages yet' &&
                                    !isDeletedPreview)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(
                                      isLastMessageRead
                                          ? Icons.done_all_rounded
                                          : Icons.done_rounded,
                                      size: 18,
                                      color: isLastMessageRead
                                          ? _accentColor
                                          : _mutedTextColor,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isPeerTyping
                                          ? _accentColor
                                          : isDeletedPreview
                                              ? _mutedTextColor
                                          : unreadCount > 0
                                              ? _primaryTextColor
                                              : _mutedTextColor,
                                      fontSize: 15,
                                      fontWeight: isPeerTyping
                                          ? FontWeight.w600
                                          : isDeletedPreview
                                              ? FontWeight.w400
                                          : unreadCount > 0
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                      fontStyle: isPeerTyping
                                          ? FontStyle.italic
                                          : isDeletedPreview
                                              ? FontStyle.italic
                                          : FontStyle.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (unreadCount > 0) ...[
                            const SizedBox(width: 12),
                            Container(
                              constraints: const BoxConstraints(minWidth: 26),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _accentColor,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Text(
                                unreadCount.toString(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SafeArea(
      key: const ValueKey<String>('settings'),
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          _buildSettingsHeader(),
          const SizedBox(height: 16),
          _buildSettingsTile(
            icon: widget.isDarkMode
                ? Icons.dark_mode_rounded
                : Icons.light_mode_rounded,
            title: 'Dark Theme',
            subtitle: 'Smoothly switch between dark and light mode',
            onTap: null,
            trailing: Switch.adaptive(
              value: widget.isDarkMode,
              onChanged: _updateTheme,
            ),
          ),
          _buildSettingsTile(
            icon: Icons.person_add_alt_1_rounded,
            title: 'Add New Contact',
            subtitle: 'Start a new chat by email',
            onTap: _showAddUserDialog,
          ),
          _buildSettingsTile(
            icon: Icons.notifications_none_rounded,
            title: 'Notifications',
            subtitle: 'Configured through Firebase Messaging',
            onTap: () => Dialogs.showSnackbar(
              context,
              'Notifications are already connected to Firebase.',
            ),
          ),
          _buildSettingsTile(
            icon: Icons.share_outlined,
            title: 'Invite Friends',
            subtitle: 'Share Swift Chat with your contacts',
            onTap: () => Dialogs.showSnackbar(
              context,
              'Invite sharing can be connected next.',
            ),
          ),
          _buildSettingsTile(
            icon: Icons.logout_rounded,
            title: 'Logout',
            subtitle: 'Sign out from your account',
            iconColor: const Color(0xFFFF6B6B),
            onTap: () async {
              await _signOut();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsHeader() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _currentUserDocStream,
      builder: (context, snapshot) {
        final profile = _currentProfileFromData(snapshot.data?.data());

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              _buildAvatar(
                photoUrl: profile.photoUrl,
                photoBase64: profile.photoBase64,
                name: profile.name,
                radius: 28,
                showOnlineBadge: true,
                isOnline: _isUserActiveNow(profile),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: TextStyle(
                        color: _primaryTextColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.email.isNotEmpty ? profile.email : 'No email',
                      style: TextStyle(
                        color: _mutedTextColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Color? iconColor,
    Widget? trailing,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _surfaceSoftColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor ?? _primaryTextColor),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: _primaryTextColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: _mutedTextColor),
        ),
        trailing: trailing ??
            Icon(
              Icons.chevron_right_rounded,
              color: _mutedTextColor,
            ),
      ),
    );
  }

  Widget _buildProfileTab() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _currentUserDocStream,
      builder: (context, snapshot) {
        final profile = _currentProfileFromData(snapshot.data?.data());
        final isOnline = _isUserActiveNow(profile);
        final mediaQuery = MediaQuery.of(context);
        final isCompactLayout = mediaQuery.size.height <= 820;
        final avatarRadius = isCompactLayout ? 48.0 : 60.0;
        final sectionGap = isCompactLayout ? 14.0 : 18.0;
        final itemGap = isCompactLayout ? 14.0 : 22.0;

        return SafeArea(
          key: const ValueKey<String>('profile'),
          top: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              14,
              isCompactLayout ? 6 : 12,
              14,
              mediaQuery.padding.bottom + 96,
            ),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => _selectTab(_HomeTab.chats),
                    icon: Icon(
                      Icons.dashboard_customize_outlined,
                      color: _primaryTextColor,
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    color: _surfaceColor,
                    icon: Icon(Icons.more_vert_rounded, color: _primaryTextColor),
                    onSelected: (value) async {
                      switch (value) {
                        case 'edit':
                          await _showEditProfileSheet(profile);
                          break;
                        case 'settings':
                          _selectTab(_HomeTab.settings);
                          break;
                        case 'logout':
                          await _signOut();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: Text(
                          'Edit info',
                          style: TextStyle(color: _primaryTextColor),
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'settings',
                        child: Text(
                          'Settings',
                          style: TextStyle(color: _primaryTextColor),
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'logout',
                        child: Text(
                          'Logout',
                          style: TextStyle(color: _primaryTextColor),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: isCompactLayout ? 2 : 8),
              Center(
                child: Column(
                  children: [
                    _buildAvatar(
                      photoUrl: profile.photoUrl,
                      photoBase64: profile.photoBase64,
                      name: profile.name,
                      radius: avatarRadius,
                      showOnlineBadge: true,
                      isOnline: isOnline,
                    ),
                    SizedBox(height: isCompactLayout ? 12 : 18),
                    Text(
                      profile.name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _primaryTextColor,
                        fontSize: isCompactLayout ? 21 : 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatProfilePresence(profile),
                      style: TextStyle(
                        color: isOnline ? _accentColor : _mutedTextColor,
                        fontSize: isCompactLayout ? 14 : 16,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isCompactLayout ? 18 : 26),
              Row(
                children: [
                  Expanded(
                    child: _buildProfileActionCard(
                      icon: Icons.add_a_photo_rounded,
                      title: 'Set Photo',
                      compact: isCompactLayout,
                      onTap: _showSetPhotoOptions,
                    ),
                  ),
                  SizedBox(width: isCompactLayout ? 10 : 12),
                  Expanded(
                    child: _buildProfileActionCard(
                      icon: Icons.edit_rounded,
                      title: 'Edit Info',
                      compact: isCompactLayout,
                      onTap: () => _showEditProfileSheet(profile),
                    ),
                  ),
                  SizedBox(width: isCompactLayout ? 10 : 12),
                  Expanded(
                    child: _buildProfileActionCard(
                      icon: Icons.settings_rounded,
                      title: 'Settings',
                      compact: isCompactLayout,
                      onTap: () async => _selectTab(_HomeTab.settings),
                    ),
                  ),
                ],
              ),
              SizedBox(height: sectionGap),
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                padding: EdgeInsets.all(isCompactLayout ? 18 : 24),
                decoration: BoxDecoration(
                  color: _surfaceColor,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileInfoItem(
                      label: 'Mobile',
                      value: profile.phone.isNotEmpty
                          ? profile.phone
                          : 'Not added yet',
                      compact: isCompactLayout,
                    ),
                    SizedBox(height: itemGap),
                    _buildProfileInfoItem(
                      label: 'Bio',
                      value: profile.bio.isNotEmpty
                          ? profile.bio
                          : 'Write a short bio about yourself',
                      compact: isCompactLayout,
                      maxLines: 2,
                    ),
                    SizedBox(height: itemGap),
                    _buildProfileInfoItem(
                      label: 'Username',
                      value: profile.username.isNotEmpty
                          ? profile.username
                          : '@${profile.id.substring(0, 6)}',
                      compact: isCompactLayout,
                    ),
                    SizedBox(height: itemGap),
                    _buildProfileInfoItem(
                      label: 'Birthday',
                      value: _formatBirthdayWithAge(profile.birthday),
                      compact: isCompactLayout,
                      maxLines: 2,
                    ),
                    SizedBox(height: itemGap),
                    _buildProfileInfoItem(
                      label: 'Email',
                      value: profile.email.isNotEmpty
                          ? profile.email
                          : 'No email available',
                      compact: isCompactLayout,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileActionCard({
    required IconData icon,
    required String title,
    required Future<void> Function() onTap,
    bool compact = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () async => onTap(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          padding: EdgeInsets.symmetric(
            vertical: compact ? 13 : 18,
            horizontal: compact ? 6 : 10,
          ),
          decoration: BoxDecoration(
            color: _surfaceColor.withOpacity(_isDark ? 0.98 : 1),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              Icon(icon, color: _primaryTextColor, size: compact ? 24 : 28),
              SizedBox(height: compact ? 7 : 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _primaryTextColor,
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 12.3 : 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileInfoItem({
    required String label,
    required String value,
    bool compact = false,
    int maxLines = 3,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _primaryTextColor,
            fontSize: compact ? 15.2 : 17,
            fontWeight: FontWeight.w500,
            height: compact ? 1.15 : 1.25,
          ),
        ),
        SizedBox(height: compact ? 4 : 6),
        Text(
          label,
          style: TextStyle(
            color: _mutedTextColor,
            fontSize: compact ? 12.3 : 14,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileInputField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _mutedTextColor,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: TextStyle(color: _primaryTextColor),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: _mutedTextColor),
            filled: true,
            fillColor: _surfaceSoftColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileActionRowTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Future<void> Function() onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async => onTap(),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _surfaceSoftColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _surfaceColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _primaryTextColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: _primaryTextColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: _mutedTextColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatProfilePresence(ChatUser profile) {
    if (_isUserActiveNow(profile)) {
      return 'online';
    }

    final lastSeen = (profile.lastSeen ?? profile.lastActiveAt)?.toDate();
    if (lastSeen == null) {
      return 'offline';
    }

    final now = DateTime.now();
    if (DateUtils.isSameDay(lastSeen, now)) {
      return 'last seen ${DateFormat('h:mm a').format(lastSeen)}';
    }

    return 'last seen ${DateFormat('dd MMM, h:mm a').format(lastSeen)}';
  }

  String _formatBirthdayWithAge(Timestamp? birthday) {
    if (birthday == null) {
      return 'Not set yet';
    }

    final birthDate = birthday.toDate();
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    final hasHadBirthdayThisYear = now.month > birthDate.month ||
        (now.month == birthDate.month && now.day >= birthDate.day);

    if (!hasHadBirthdayThisYear) {
      age -= 1;
    }

    return '${DateFormat('MMM d, yyyy').format(birthDate)} ($age years old)';
  }

  Widget _buildEmptyState({
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: _surfaceColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                color: _primaryTextColor,
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(
                color: _primaryTextColor,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _mutedTextColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar({
    required String? photoUrl,
    String? photoBase64,
    required String name,
    double radius = 30,
    bool showOnlineBadge = false,
    bool isOnline = false,
  }) {
    final hasCustomPhoto =
        photoUrl?.isNotEmpty == true || photoBase64?.isNotEmpty == true;
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: _avatarColor(name),
      foregroundImage: hasCustomPhoto
          ? buildAvatarImageProvider(
              photoUrl: photoUrl,
              photoBase64: photoBase64,
            )
          : null,
      child: hasCustomPhoto
          ? null
          : Text(
              _initialsFromName(name),
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.7,
                fontWeight: FontWeight.w700,
              ),
            ),
    );

    if (!showOnlineBadge) {
      return avatar;
    }

    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: avatar),
          if (isOnline)
            Positioned(
              right: 1,
              bottom: 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: radius * 0.55,
                height: radius * 0.55,
                decoration: BoxDecoration(
                  color: const Color(0xFF44D16B),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _surfaceColor,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: radius * 0.34,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _avatarColor(String seed) {
    const palette = [
      Color(0xFF5C6BC0),
      Color(0xFF42A5F5),
      Color(0xFF26A69A),
      Color(0xFFAB47BC),
      Color(0xFFFF7043),
      Color(0xFF7E57C2),
    ];

    final index = seed.runes.fold<int>(0, (value, rune) => value + rune) %
        palette.length;
    return palette[index];
  }

  String _initialsFromName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'U';
    if (parts.length == 1) return parts.first[0].toUpperCase();

    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final second = parts[1].isNotEmpty ? parts[1][0] : '';
    return '$first$second'.toUpperCase();
  }

  String _formatMessageTime(Timestamp? timestamp) {
    if (timestamp == null) return '';

    final date = timestamp.toDate();
    final now = DateTime.now();

    if (DateUtils.isSameDay(date, now)) {
      return DateFormat('h:mm a').format(date);
    }

    if (DateUtils.isSameDay(
      date,
      now.subtract(const Duration(days: 1)),
    )) {
      return 'Yesterday';
    }

    if (now.difference(date).inDays < 7) {
      return DateFormat('EEE').format(date);
    }

    return DateFormat('dd MMM').format(date);
  }

  Widget _buildFloatingActions() {
    return FloatingActionButton(
      onPressed: _showAddUserDialog,
      backgroundColor: _accentColor,
      elevation: 4,
      child: const Icon(
        Icons.person_add_alt_1_rounded,
        color: Colors.white,
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: _surfaceColor.withOpacity(_isDark ? 0.96 : 0.98),
            borderRadius: BorderRadius.circular(34),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildBottomItem(
                  tab: _HomeTab.chats,
                  icon: Icons.chat_bubble_rounded,
                  label: 'Chats',
                ),
              ),
              Expanded(
                child: _buildBottomItem(
                  tab: _HomeTab.contacts,
                  icon: Icons.contacts_rounded,
                  label: 'Contacts',
                ),
              ),
              Expanded(
                child: _buildBottomItem(
                  tab: _HomeTab.settings,
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                ),
              ),
              Expanded(
                child: _buildBottomItem(
                  tab: _HomeTab.profile,
                  icon: Icons.person_rounded,
                  label: 'Profile',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomItem({
    required _HomeTab tab,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _selectedTab == tab;

    return GestureDetector(
      onTap: () => _selectTab(tab),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color:
              isSelected ? _accentColor.withOpacity(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? _accentColor : _secondaryTextColor,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? _accentColor : _secondaryTextColor,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
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
          backgroundColor: _surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            'Add User by Email',
            style: TextStyle(color: _primaryTextColor),
          ),
          content: TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: _primaryTextColor),
            decoration: InputDecoration(
              hintText: 'Enter user email',
              hintStyle: TextStyle(color: _mutedTextColor),
              filled: true,
              fillColor: _surfaceSoftColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
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
                  Dialogs.showSnackbar(context, 'Please enter email');
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
                  Navigator.pop(context);

                  if (query.docs.isEmpty) {
                    Dialogs.showSnackbar(context, 'User not found');
                    return;
                  }

                  final peerUser = ChatUser.fromMap(query.docs.first.data());

                  await FirebaseFirestore.instance
                      .collection('chat_users')
                      .doc(_currentUser.uid)
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
                          peerPhotoBase64: peerUser.photoBase64,
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(context);
                    Dialogs.showSnackbar(
                      context,
                      'Error: ${e.toString()}',
                    );
                  }
                }
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    ).then((_) {
      _isDialogOpen = false;
      emailController.dispose();
    });
  }
}
