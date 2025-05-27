import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Adds the selected user to the current user's contacts
/// and vice versa, if not already present.
Future<void> addToChatUsers({
  required String peerUserId,
  required String peerName,
  required String peerEmail,
  required String peerPhotoUrl,
}) async {
  try {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final currentUserId = currentUser.uid;
    final currentUserName = currentUser.displayName ?? '';
    final currentUserEmail = currentUser.email ?? '';
    final currentUserPhotoUrl = currentUser.photoURL ?? '';

    final userRef = FirebaseFirestore.instance;

    // Add peer to current user's contacts
    await userRef
        .collection('users')
        .doc(currentUserId)
        .collection('contacts')
        .doc(peerUserId)
        .set({
      'uid': peerUserId,
      'name': peerName,
      'email': peerEmail,
      'photoUrl': peerPhotoUrl,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCount': 0,
    });

    // Add current user to peer's contacts
    await userRef
        .collection('users')
        .doc(peerUserId)
        .collection('contacts')
        .doc(currentUserId)
        .set({
      'uid': currentUserId,
      'name': currentUserName,
      'email': currentUserEmail,
      'photoUrl': currentUserPhotoUrl,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'unreadCount': 0,
    });
  } catch (e) {
    print('Error adding to chat users: $e');
    rethrow;
  }
}

/// Updates the unread message count and timestamp for a user
Future<void> updateUnreadCount(
    String contactUserId, String currentUserId) async {
  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('contacts')
        .doc(contactUserId)
        .update({
      'unreadCount': FieldValue.increment(1),
      'lastMessageTime': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    print('Error updating unread count: $e');
    rethrow;
  }
}
