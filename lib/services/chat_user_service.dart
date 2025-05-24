import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

    // Add peer to current user's chat_users collection
    await userRef
        .collection('users')
        .doc(currentUserId)
        .collection('chat_users')
        .doc(peerUserId)
        .set({
      'uid': peerUserId,
      'name': peerName,
      'email': peerEmail,
      'photoUrl': peerPhotoUrl,
      'addedAt': FieldValue.serverTimestamp(),
    });

    // Add current user to peer's chat_users collection
    await userRef
        .collection('users')
        .doc(peerUserId)
        .collection('chat_users')
        .doc(currentUserId)
        .set({
      'uid': currentUserId,
      'name': currentUserName,
      'email': currentUserEmail,
      'photoUrl': currentUserPhotoUrl,
      'addedAt': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    print('Error adding to chat users: $e');
  }
}
