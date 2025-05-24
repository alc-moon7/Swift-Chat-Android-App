import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'chat_user_card.dart';

class ChatUserCardFirestore extends StatelessWidget {
  final String peerId;
  final String peerName;
  final String peerAvatar;
  final bool isOnline;
  final VoidCallback onTap;

  ChatUserCardFirestore({
    Key? key,
    required this.peerId,
    required this.peerName,
    required this.peerAvatar,
    required this.isOnline,
    required this.onTap,
  }) : super(key: key);

  final currentUser = FirebaseAuth.instance.currentUser!;

  String get chatId {
    return currentUser.uid.hashCode <= peerId.hashCode
        ? '${currentUser.uid}_$peerId'
        : '${peerId}_${currentUser.uid}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        String lastMessage = '';
        String time = '';
        int unreadCount = 0;

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final messages = snapshot.data!.docs;

          final latest = messages.first;
          lastMessage = latest['text'];
          final timestamp = latest['timestamp'] as Timestamp?;
          time = timestamp != null ? _formatTime(timestamp.toDate()) : '';

          unreadCount = messages
              .where((msg) =>
                  msg['receiverId'] == currentUser.uid &&
                  (msg['read'] == null || msg['read'] == false))
              .length;
        }

        return ChatUserCard(
          name: peerName,
          message: lastMessage,
          time: time,
          avatarUrl: peerAvatar,
          isOnline: isOnline,
          hasUnreadMessages: unreadCount > 0,
          unreadCount: unreadCount,
          onTap: onTap,
        );
      },
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    if (now.difference(dateTime).inDays == 0) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.month}/${dateTime.day}';
    }
  }
}
