const {initializeApp} = require("firebase-admin/app");
const {FieldValue, getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {logger} = require("firebase-functions");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");

initializeApp();

const db = getFirestore();

exports.sendChatMessageNotification = onDocumentCreated(
  {
    document: "chats/{chatId}/messages/{messageId}",
    region: "us-central1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      logger.warn("Missing message snapshot", {eventId: event.id});
      return;
    }

    const messageData = snapshot.data() || {};
    const chatId = event.params.chatId;
    const messageId = event.params.messageId;
    const senderId = normalizeString(messageData.senderId);
    const receiverId = normalizeString(messageData.receiverId);
    const rawText = normalizeString(messageData.text);

    if (!senderId || !receiverId) {
      logger.warn("Message is missing sender or receiver", {
        chatId,
        messageId,
      });
      return;
    }

    const [senderDoc, receiverDoc] = await Promise.all([
      db.collection("users").doc(senderId).get(),
      db.collection("users").doc(receiverId).get(),
    ]);

    if (!receiverDoc.exists) {
      logger.warn("Receiver document not found", {receiverId, chatId});
      return;
    }

    const receiverData = receiverDoc.data() || {};
    const receiverToken = normalizeString(receiverData.fcmToken);

    if (!receiverToken) {
      logger.info("Receiver has no active FCM token", {receiverId, chatId});
      return;
    }

    const senderData = senderDoc.data() || {};
    const senderName =
      normalizeString(senderData.name) ||
      normalizeString(senderData.email) ||
      "Swift Chat";
    const body = buildMessagePreview(rawText);

    const notificationMessage = {
      token: receiverToken,
      notification: {
        title: senderName,
        body,
      },
      data: {
        type: "chat_message",
        chatId,
        peerId: senderId,
        senderId,
        senderName,
        body,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "swift_chat_channel",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
          priority: "max",
          defaultSound: true,
          visibility: "public",
          tag: chatId,
        },
      },
      apns: {
        headers: {
          "apns-priority": "10",
        },
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    try {
      const response = await getMessaging().send(notificationMessage);
      logger.info("Chat notification sent", {
        chatId,
        messageId,
        receiverId,
        response,
      });
    } catch (error) {
      logger.error("Failed to send chat notification", {
        chatId,
        messageId,
        receiverId,
        error,
      });

      const errorCode = error && typeof error === "object" ? error.code : "";
      if (
        errorCode === "messaging/registration-token-not-registered" ||
        errorCode === "messaging/invalid-registration-token"
      ) {
        await db.collection("users").doc(receiverId).set(
          {
            fcmToken: FieldValue.delete(),
            lastTokenUpdatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );
      }
    }
  },
);

function normalizeString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function buildMessagePreview(text) {
  if (!text) {
    return "Sent you a message";
  }

  if (text.length <= 120) {
    return text;
  }

  return `${text.slice(0, 117)}...`;
}
