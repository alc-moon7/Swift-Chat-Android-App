import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:swift_chat/helper/avatar_provider.dart';
import 'package:swift_chat/services/push_relay_service.dart';

class ChatScreen extends StatefulWidget {
  final String peerId;
  final String peerName;
  final String? peerPhoto;
  final String? peerPhotoBase64;

  const ChatScreen({
    Key? key,
    required this.peerId,
    required this.peerName,
    this.peerPhoto,
    this.peerPhotoBase64,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User _user = FirebaseAuth.instance.currentUser!;
  late final String _chatId;
  late final Future<void> _chatSetupFuture;
  StreamSubscription<QuerySnapshot>? _readSubscription;
  Timer? _typingDebounce;
  bool _isTyping = false;
  bool _hasTypedText = false;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _pageColor =>
      _isDark ? const Color(0xFF0B141A) : const Color(0xFFE3EDF5);
  Color get _pageAccentColor =>
      _isDark ? const Color(0xFF101C24) : const Color(0xFFD4E2ED);
  Color get _surfaceColor =>
      _isDark ? const Color(0xFF202C33) : Colors.white;
  Color get _surfaceSoftColor =>
      _isDark ? const Color(0xFF243844) : const Color(0xFFD5E3EE);
  Color get _primaryTextColor =>
      _isDark ? Colors.white : const Color(0xFF17212B);
  Color get _secondaryTextColor =>
      _isDark ? const Color(0xFFA6B4C2) : const Color(0xFF6B7A88);
  Color get _accentColor =>
      _isDark ? const Color(0xFF2EA6FF) : const Color(0xFF1485EA);
  Color get _headerColor =>
      _isDark ? const Color(0xFF1D2A33) : Colors.white;
  Color get _composerColor =>
      _isDark ? const Color(0xFF202C33) : Colors.white;

  @override
  void initState() {
    super.initState();
    _chatId = _generateChatId();
    _chatSetupFuture = _initializeChat();
    _listenForUnreadMessages();
    _messageController.addListener(_syncComposerState);
  }

  String _generateChatId() {
    final ids = [_user.uid, widget.peerId]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  Future<void> _initializeChat() async {
    final chatDoc = _firestore.collection('chats').doc(_chatId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(chatDoc);
      if (snapshot.exists) {
        return;
      }

      transaction.set(chatDoc, {
        'members': [_user.uid, widget.peerId],
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageSenderId': '',
        'lastMessageTime': null,
        'typing': {
          _user.uid: false,
          widget.peerId: false,
        },
        'unreadCounts': {
          _user.uid: 0,
          widget.peerId: 0,
        },
      });
    });
  }

  void _listenForUnreadMessages() {
    _readSubscription = _firestore
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .where('receiverId', isEqualTo: _user.uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen(_markIncomingMessagesAsRead);
  }

  Future<void> _markIncomingMessagesAsRead(QuerySnapshot snapshot) async {
    if (snapshot.docs.isEmpty) {
      await _firestore.collection('chats').doc(_chatId).update({
        'unreadCounts.${_user.uid}': 0,
      }).catchError((_) {});
      return;
    }

    final batch = _firestore.batch();

    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }

    batch.update(_firestore.collection('chats').doc(_chatId), {
      'unreadCounts.${_user.uid}': 0,
    });

    await batch.commit();
  }

  void _syncComposerState() {
    final hasText = _messageController.text.trim().isNotEmpty;
    if (_hasTypedText == hasText || !mounted) {
      return;
    }

    setState(() {
      _hasTypedText = hasText;
    });
  }

  void _handleTypingInput(String value) {
    final hasText = value.trim().isNotEmpty;
    _typingDebounce?.cancel();

    if (!hasText) {
      _setTyping(false);
      return;
    }

    if (!_isTyping) {
      _setTyping(true);
    }

    _typingDebounce = Timer(
      const Duration(milliseconds: 1200),
      () => _setTyping(false),
    );
  }

  Future<void> _setTyping(bool value) async {
    if (_isTyping == value) {
      return;
    }

    _isTyping = value;

    try {
      await _chatSetupFuture;
      await _firestore.collection('chats').doc(_chatId).update({
        'typing.${_user.uid}': value,
        'typingUpdatedAt.${_user.uid}': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    try {
      await _chatSetupFuture;
      final chatRef = _firestore.collection('chats').doc(_chatId);
      final messageRef = chatRef.collection('messages').doc();
      final batch = _firestore.batch();

      batch.set(messageRef, {
        'senderId': _user.uid,
        'receiverId': widget.peerId,
        'text': text,
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });

      batch.set(chatRef, {
        'members': [_user.uid, widget.peerId],
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastMessageSenderId': _user.uid,
        'lastMessageSenderName': _user.displayName ?? _user.email ?? 'You',
      }, SetOptions(merge: true));

      batch.update(chatRef, {
        'typing.${_user.uid}': false,
        'unreadCounts.${widget.peerId}': FieldValue.increment(1),
        'unreadCounts.${_user.uid}': 0,
        'lastMessageDeletedForEveryone': false,
        'previewOverrides.${_user.uid}': FieldValue.delete(),
        'previewOverrides.${widget.peerId}': FieldValue.delete(),
      });

      await batch.commit();
      _isTyping = false;
      _messageController.clear();
      _scrollToBottom();
      unawaited(
        PushRelayService.sendMessageNotification(
          chatId: _chatId,
          messageId: messageRef.id,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  bool _isMessageDeletedForEveryone(Map<String, dynamic> data) {
    return data['deletedForEveryone'] == true;
  }

  bool _isMessageHiddenForUser(
    Map<String, dynamic> data,
    String userId,
  ) {
    final deletedFor = List<String>.from(data['deletedFor'] ?? const []);
    return deletedFor.contains(userId);
  }

  String _deletedPreviewText() => 'This message was deleted';

  Future<Map<String, dynamic>> _resolveVisiblePreviewForUser(
    String userId,
  ) async {
    await _chatSetupFuture;

    final snapshot = await _firestore
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(40)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (_isMessageHiddenForUser(data, userId)) {
        continue;
      }

      final senderId = (data['senderId'] as String? ?? '').trim();
      final timestamp = data['timestamp'] as Timestamp?;
      final isDeletedForEveryone = _isMessageDeletedForEveryone(data);
      final previewText = isDeletedForEveryone
          ? _deletedPreviewText()
          : (data['text'] as String? ?? '').trim();

      return {
        'lastMessage': previewText,
        'lastMessageTime': timestamp,
        'lastMessageSenderId': senderId,
        'lastMessageDeletedForEveryone': isDeletedForEveryone,
      };
    }

    return {
      'lastMessage': '',
      'lastMessageTime': null,
      'lastMessageSenderId': '',
      'lastMessageDeletedForEveryone': false,
    };
  }

  Future<void> _refreshCurrentUserPreviewOverride() async {
    final preview = await _resolveVisiblePreviewForUser(_user.uid);
    await _firestore.collection('chats').doc(_chatId).set({
      'previewOverrides': {
        _user.uid: preview,
      },
    }, SetOptions(merge: true));
  }

  Future<bool> _isLatestMessage(String messageId) async {
    final latestSnapshot = await _firestore
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    return latestSnapshot.docs.isNotEmpty &&
        latestSnapshot.docs.first.id == messageId;
  }

  Future<void> _deleteMessageForMe(QueryDocumentSnapshot doc) async {
    await doc.reference.set({
      'deletedFor': FieldValue.arrayUnion([_user.uid]),
      'deletedForUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _refreshCurrentUserPreviewOverride();
  }

  Future<void> _deleteMessageForEveryone(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final isLatestMessage = await _isLatestMessage(doc.id);

    final batch = _firestore.batch();
    batch.set(doc.reference, {
      'text': '',
      'deletedForEveryone': true,
      'deletedForEveryoneAt': FieldValue.serverTimestamp(),
      'deletedForEveryoneBy': _user.uid,
    }, SetOptions(merge: true));

    if (isLatestMessage) {
      batch.update(_firestore.collection('chats').doc(_chatId), {
        'lastMessage': _deletedPreviewText(),
        'lastMessageSenderId': data['senderId'] ?? _user.uid,
        'lastMessageDeletedForEveryone': true,
        'previewOverrides.${_user.uid}': FieldValue.delete(),
        'previewOverrides.${widget.peerId}': FieldValue.delete(),
      });
    }

    await batch.commit();
  }

  Future<void> _showMessageActions(
    QueryDocumentSnapshot doc,
    bool isOwnMessage,
  ) async {
    final data = doc.data() as Map<String, dynamic>;
    final isAlreadyDeletedForEveryone = _isMessageDeletedForEveryone(data);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        Widget actionTile({
          required IconData icon,
          required String title,
          required Future<void> Function() onTap,
          Color? color,
        }) {
          final resolvedColor = color ?? _primaryTextColor;
          return ListTile(
            leading: Icon(icon, color: resolvedColor),
            title: Text(
              title,
              style: TextStyle(
                color: resolvedColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () async {
              Navigator.pop(sheetContext);
              await onTap();
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(title),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _secondaryTextColor.withOpacity(0.28),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                actionTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete for me',
                  onTap: () => _deleteMessageForMe(doc),
                ),
                if (isOwnMessage && !isAlreadyDeletedForEveryone)
                  actionTile(
                    icon: Icons.undo_rounded,
                    title: 'Unsend for everyone',
                    color: const Color(0xFFFF6B6B),
                    onTap: () => _deleteMessageForEveryone(doc),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isPeerOnline(Map<String, dynamic>? data) {
    if (data == null) {
      return false;
    }

    if (data['isOnline'] == true) {
      return true;
    }

    final lastActive = data['lastActiveAt'] as Timestamp?;
    if (lastActive == null) {
      return false;
    }

    return DateTime.now().difference(lastActive.toDate()).inSeconds <= 90;
  }

  String _formatPresenceLabel(bool isOnline, Timestamp? lastSeen) {
    if (isOnline) {
      return 'online';
    }

    if (lastSeen == null) {
      return 'offline';
    }

    final date = lastSeen.toDate();
    final time = DateFormat('h:mm a').format(date);
    final now = DateTime.now();

    if (DateUtils.isSameDay(date, now)) {
      return 'last seen at $time';
    }

    if (DateUtils.isSameDay(
      date,
      now.subtract(const Duration(days: 1)),
    )) {
      return 'last seen yesterday at $time';
    }

    return 'last seen ${DateFormat('dd MMM').format(date)} at $time';
  }

  String _peerNameFromData(Map<String, dynamic>? data) {
    final liveName = (data?['name'] as String?)?.trim() ?? '';
    return liveName.isNotEmpty ? liveName : widget.peerName;
  }

  String? _peerPhotoUrlFromData(Map<String, dynamic>? data) {
    final liveUrl = (data?['photoUrl'] as String?)?.trim() ?? '';
    return liveUrl.isNotEmpty ? liveUrl : widget.peerPhoto;
  }

  String? _peerPhotoBase64FromData(Map<String, dynamic>? data) {
    final liveBase64 = (data?['photoBase64'] as String?)?.trim() ?? '';
    return liveBase64.isNotEmpty ? liveBase64 : widget.peerPhotoBase64;
  }

  Widget _buildAppBarTitle({
    required Map<String, dynamic>? userData,
    required String peerName,
    required String? peerPhoto,
    required String? peerPhotoBase64,
  }) {
    final isPeerOnline = _isPeerOnline(userData);
    final lastSeen =
        (userData?['lastSeen'] ?? userData?['lastActiveAt']) as Timestamp?;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('chats').doc(_chatId).snapshots(),
      builder: (context, chatSnapshot) {
        final chatData = chatSnapshot.data?.data();
        final typingData =
            Map<String, dynamic>.from(chatData?['typing'] ?? const {});
        final isPeerTyping = typingData[widget.peerId] == true;
        final statusLabel = isPeerTyping
            ? 'typing...'
            : _formatPresenceLabel(isPeerOnline, lastSeen);

        return Row(
          children: [
            _buildPeerAvatar(
              isOnline: isPeerOnline,
              peerPhoto: peerPhoto,
              peerPhotoBase64: peerPhotoBase64,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    peerName,
                    style: TextStyle(
                      color: _primaryTextColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      color: isPeerTyping ? _accentColor : _secondaryTextColor,
                      fontSize: 12,
                      fontStyle: isPeerTyping
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('users').doc(widget.peerId).snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data();
        final peerName = _peerNameFromData(userData);
        final peerPhoto = _peerPhotoUrlFromData(userData);
        final peerPhotoBase64 = _peerPhotoBase64FromData(userData);

        return Scaffold(
          backgroundColor: _pageColor,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: _headerColor,
            foregroundColor: _primaryTextColor,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 4,
            toolbarHeight: 66,
            title: _buildAppBarTitle(
              userData: userData,
              peerName: peerName,
              peerPhoto: peerPhoto,
              peerPhotoBase64: peerPhotoBase64,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.videocam_outlined),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.call_outlined),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () {},
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
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                _pageColor,
                                _pageAccentColor,
                              ],
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Opacity(
                                  opacity: _isDark ? 0.12 : 0.075,
                                  child: Image.asset(
                                    'assets/images/chat_bf.png',
                                    fit: BoxFit.cover,
                                    color: _isDark
                                        ? const Color(0xFF8FB9D2)
                                        : const Color(0xFF6D96B2),
                                    colorBlendMode: BlendMode.srcATop,
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withOpacity(
                                          _isDark ? 0.18 : 0.03,
                                        ),
                                        Colors.transparent,
                                        Colors.black.withOpacity(
                                          _isDark ? 0.08 : 0.014,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      StreamBuilder<QuerySnapshot>(
                        stream: _firestore
                            .collection('chats')
                            .doc(_chatId)
                            .collection('messages')
                            .orderBy('timestamp', descending: true)
                            .snapshots(),
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
                          final docs = snapshot.data!.docs
                              .where((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return !_isMessageHiddenForUser(
                                  data,
                                  _user.uid,
                                );
                              })
                              .toList();

                          if (docs.isEmpty) {
                            return Center(
                              child: Text(
                                'No messages yet',
                                style: TextStyle(color: _secondaryTextColor),
                              ),
                            );
                          }

                          return ListView.separated(
                            reverse: true,
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final currentTimestamp =
                                  doc['timestamp'] as Timestamp?;
                              final olderTimestamp = index < docs.length - 1
                                  ? docs[index + 1]['timestamp'] as Timestamp?
                                  : null;

                              return Column(
                                children: [
                                  if (_shouldShowDateHeader(
                                    currentTimestamp,
                                    olderTimestamp,
                                  ))
                                    _DateHeader(
                                      label: _formatDateHeader(currentTimestamp),
                                      isDark: _isDark,
                                    ),
                                  _MessageItem(
                                    doc: doc,
                                    isMe: doc['senderId'] == _user.uid,
                                    peerPhoto: peerPhoto,
                                    peerPhotoBase64: peerPhotoBase64,
                                    onLongPress: () => _showMessageActions(
                                      doc,
                                      doc['senderId'] == _user.uid,
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
                _buildTypingBanner(peerName),
                SafeArea(child: _buildInputArea()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPeerAvatar({
    required bool isOnline,
    required String? peerPhoto,
    required String? peerPhotoBase64,
  }) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      child: SizedBox(
        width: 42,
        height: 42,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: _surfaceSoftColor,
              backgroundImage: buildAvatarImageProvider(
                photoUrl: peerPhoto,
                photoBase64: peerPhotoBase64,
              ),
            ),
            if (isOnline)
              Positioned(
                right: -1,
                bottom: -1,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF44D16B),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _headerColor,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 8,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingBanner(String peerName) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('chats').doc(_chatId).snapshots(),
      builder: (context, snapshot) {
        final chatData = snapshot.data?.data();
        final typingData =
            Map<String, dynamic>.from(chatData?['typing'] ?? const {});
        final isPeerTyping = typingData[widget.peerId] == true;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: isPeerTyping
              ? Padding(
                  key: const ValueKey<String>('typing-banner'),
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _isDark
                            ? _surfaceColor.withOpacity(0.96)
                            : Colors.white.withOpacity(0.96),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _accentColor.withOpacity(0.18),
                        ),
                      ),
                      child: Text(
                        '$peerName is typing...',
                        style: TextStyle(
                          color: _accentColor,
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox(
                  key: ValueKey<String>('typing-banner-empty'),
                ),
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              decoration: BoxDecoration(
                color: _composerColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _isDark
                      ? Colors.white.withOpacity(0.06)
                      : const Color(0xFFD9E7F2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(_isDark ? 0.18 : 0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 5,
                style: TextStyle(color: _primaryTextColor),
                cursorColor: _accentColor,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: _secondaryTextColor),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 14,
                  ),
                ),
                onChanged: _handleTypingInput,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _hasTypedText
                    ? [
                        _accentColor,
                        _isDark
                            ? const Color(0xFF67C1FF)
                            : const Color(0xFF3EA6FF),
                      ]
                    : [
                        _surfaceSoftColor.withOpacity(0.92),
                        _surfaceColor,
                      ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (_hasTypedText ? _accentColor : Colors.black)
                      .withOpacity(_isDark ? 0.26 : 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                Icons.send_rounded,
                color: _hasTypedText ? Colors.white : _primaryTextColor,
              ),
              onPressed: _hasTypedText ? _sendMessage : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _setTyping(false);
    _readSubscription?.cancel();
    _messageController.removeListener(_syncComposerState);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool _shouldShowDateHeader(Timestamp? current, Timestamp? older) {
    if (current == null) return false;
    if (older == null) return true;

    return !DateUtils.isSameDay(current.toDate(), older.toDate());
  }

  String _formatDateHeader(Timestamp? timestamp) {
    if (timestamp == null) return '';

    final date = timestamp.toDate();
    final now = DateTime.now();

    if (DateUtils.isSameDay(date, now)) {
      return 'Today';
    }

    if (DateUtils.isSameDay(
      date,
      now.subtract(const Duration(days: 1)),
    )) {
      return 'Yesterday';
    }

    return DateFormat('dd MMM yyyy').format(date);
  }
}

class _MessageItem extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final bool isMe;
  final String? peerPhoto;
  final String? peerPhotoBase64;
  final VoidCallback? onLongPress;

  const _MessageItem({
    Key? key,
    required this.doc,
    required this.isMe,
    this.peerPhoto,
    this.peerPhotoBase64,
    this.onLongPress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final isDeletedForEveryone = data['deletedForEveryone'] == true;
    return MessageBubble(
      text: isDeletedForEveryone
          ? (isMe
              ? 'You unsent this message'
              : 'This message was deleted')
          : data['text'] ?? '',
      isMe: isMe,
      isRead: data['read'] == true,
      isDeletedMessage: isDeletedForEveryone,
      timestamp: data['timestamp'] as Timestamp?,
      peerPhoto: isMe ? null : peerPhoto,
      peerPhotoBase64: isMe ? null : peerPhotoBase64,
      onLongPress: onLongPress,
    );
  }
}

class MessageBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final bool isRead;
  final bool isDeletedMessage;
  final Timestamp? timestamp;
  final String? peerPhoto;
  final String? peerPhotoBase64;
  final VoidCallback? onLongPress;

  const MessageBubble({
    Key? key,
    required this.text,
    required this.isMe,
    required this.isRead,
    this.isDeletedMessage = false,
    this.timestamp,
    this.peerPhoto,
    this.peerPhotoBase64,
    this.onLongPress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final incomingBubbleColor =
        isDeletedMessage
            ? (isDark
                ? const Color(0xFF24343E)
                : const Color(0xFFF2F5F7))
            : (isDark ? const Color(0xFF202C33) : Colors.white);
    final outgoingGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDeletedMessage
          ? (isDark
              ? const [
                  Color(0xFF475861),
                  Color(0xFF53656F),
                ]
              : const [
                  Color(0xFFE4E9ED),
                  Color(0xFFF0F4F7),
                ])
          : (isDark
              ? const [
                  Color(0xFF5060FF),
                  Color(0xFF7860FF),
                ]
              : const [
                  Color(0xFF9ED7FF),
                  Color(0xFFC5E9FF),
                ]),
    );
    final textColor = isDark ? Colors.white : const Color(0xFF17212B);
    final subTextColor =
        isDark ? const Color(0xFFA6B4C2) : const Color(0xFF6B7A88);
    final textStyle = TextStyle(
      fontSize: 16,
      color: isDeletedMessage
          ? subTextColor
          : textColor,
      height: 1.35,
      fontStyle: isDeletedMessage ? FontStyle.italic : FontStyle.normal,
    );
    final timeStyle = TextStyle(
      fontSize: 11.5,
      color: isMe ? Colors.white.withOpacity(0.84) : subTextColor,
      fontWeight: FontWeight.w500,
    );
    final timeFormat = DateFormat('h:mm a');
    final time =
        timestamp != null ? timeFormat.format(timestamp!.toDate()) : '';
    final textDirection = Directionality.of(context);
    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(22),
      topRight: const Radius.circular(22),
      bottomLeft: isMe ? const Radius.circular(22) : const Radius.circular(8),
      bottomRight: isMe ? const Radius.circular(8) : const Radius.circular(22),
    );
    final hasPeerAvatar =
        !isMe &&
        ((peerPhoto?.isNotEmpty ?? false) || (peerPhotoBase64?.isNotEmpty ?? false));

    return Padding(
      padding: EdgeInsets.only(
        top: 2,
        bottom: 2,
        left: isMe ? 48 : 0,
        right: isMe ? 0 : 48,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const horizontalPadding = 32.0;
          const minBubbleWidth = 88.0;
          const avatarFootprint = 36.0;
          final maxBubbleWidth = math.max(
            minBubbleWidth,
            math.min(
              constraints.maxWidth - (hasPeerAvatar ? avatarFootprint : 0),
              MediaQuery.of(context).size.width * 0.76,
            ),
          );

          final textPainter = TextPainter(
            text: TextSpan(text: text, style: textStyle),
            textDirection: textDirection,
            textWidthBasis: TextWidthBasis.longestLine,
            maxLines: null,
          )..layout(maxWidth: maxBubbleWidth - horizontalPadding);

          final timePainter = TextPainter(
            text: TextSpan(text: time, style: timeStyle),
            textDirection: textDirection,
            maxLines: 1,
          )..layout();

          final footerWidth = timePainter.width + (isMe ? 22 : 0);
          final contentWidth = math.max(textPainter.width, footerWidth);
          final bubbleWidth =
              (contentWidth + horizontalPadding)
                  .clamp(minBubbleWidth, maxBubbleWidth)
                  .toDouble();

          return Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (hasPeerAvatar)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: CircleAvatar(
                    radius: 14,
                    backgroundImage: buildAvatarImageProvider(
                      photoUrl: peerPhoto,
                      photoBase64: peerPhotoBase64,
                    ),
                  ),
                ),
              GestureDetector(
                onLongPress: onLongPress,
                child: SizedBox(
                  width: bubbleWidth,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    decoration: BoxDecoration(
                      color: isMe ? null : incomingBubbleColor,
                      gradient: isMe ? outgoingGradient : null,
                      borderRadius: bubbleRadius,
                      border: isMe
                          ? null
                          : Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.04)
                                  : const Color(0xFFDDE8F1),
                            ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(isDark ? 0.18 : 0.05),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            text,
                            style: textStyle,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              time,
                              style: timeStyle,
                            ),
                            if (isMe && !isDeletedMessage)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(
                                  isRead
                                      ? Icons.done_all_rounded
                                      : Icons.done_rounded,
                                  size: 16,
                                  color: isRead
                                      ? const Color(0xFFBDF3FF)
                                      : Colors.white.withOpacity(0.78),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  final String label;
  final bool isDark;

  const _DateHeader({
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF243744).withOpacity(0.92)
                : Colors.white.withOpacity(0.94),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.14 : 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF17212B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
