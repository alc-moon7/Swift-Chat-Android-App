const FIREBASE_WEB_API_KEY = "AIzaSyBlD6sRgN7ffRpPFadILsPI0RUiEn2oSFA";
const GOOGLE_OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token";

let cachedAccessToken = "";
let cachedAccessTokenExpiry = 0;

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(),
      });
    }

    const url = new URL(request.url);
    if (url.pathname !== "/send-message-notification") {
      return jsonResponse({error: "Not found"}, 404);
    }

    if (request.method !== "POST") {
      return jsonResponse({error: "Method not allowed"}, 405);
    }

    try {
      const serviceAccount = readServiceAccount(env);
      const authHeader = request.headers.get("Authorization") || "";
      const idToken = authHeader.startsWith("Bearer ") ?
        authHeader.slice(7).trim() :
        "";

      if (!idToken) {
        return jsonResponse({error: "Missing Firebase ID token"}, 401);
      }

      const body = await request.json().catch(() => ({}));
      const chatId = normalizeString(body.chatId);
      const messageId = normalizeString(body.messageId);

      if (!chatId || !messageId) {
        return jsonResponse({error: "chatId and messageId are required"}, 400);
      }

      const verifiedUser = await verifyFirebaseIdToken(idToken);
      if (!verifiedUser.uid) {
        return jsonResponse({error: "Invalid Firebase ID token"}, 401);
      }

      const accessToken = await getGoogleAccessToken(serviceAccount);
      const messageDoc = await getFirestoreDocument(
        accessToken,
        serviceAccount.project_id,
        `chats/${chatId}/messages/${messageId}`,
      );

      if (!messageDoc) {
        return jsonResponse({error: "Message not found"}, 404);
      }

      const messageData = parseFirestoreFields(messageDoc.fields || {});
      const senderId = normalizeString(messageData.senderId);
      const receiverId = normalizeString(messageData.receiverId);
      const text = normalizeString(messageData.text);

      if (!senderId || !receiverId) {
        return jsonResponse({error: "Message is missing sender or receiver"}, 400);
      }

      if (senderId !== verifiedUser.uid) {
        return jsonResponse({error: "You are not allowed to relay this message"}, 403);
      }

      const [senderDoc, receiverDoc] = await Promise.all([
        getFirestoreDocument(
          accessToken,
          serviceAccount.project_id,
          `users/${senderId}`,
        ),
        getFirestoreDocument(
          accessToken,
          serviceAccount.project_id,
          `users/${receiverId}`,
        ),
      ]);

      if (!receiverDoc) {
        return jsonResponse({error: "Receiver not found"}, 404);
      }

      const senderData = parseFirestoreFields(senderDoc?.fields || {});
      const receiverData = parseFirestoreFields(receiverDoc.fields || {});
      const receiverToken = normalizeString(receiverData.fcmToken);

      if (!receiverToken) {
        return jsonResponse({
          ok: true,
          message: "Receiver has no active FCM token",
        });
      }

      const senderName =
        normalizeString(senderData.name) ||
        normalizeString(senderData.email) ||
        "Swift Chat";

      const fcmResponse = await sendFcmMessage({
        accessToken,
        projectId: serviceAccount.project_id,
        receiverToken,
        chatId,
        senderId,
        senderName,
        body: buildMessagePreview(text),
      });

      return jsonResponse({
        ok: true,
        response: fcmResponse,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return jsonResponse({error: message}, 500);
    }
  },
};

function readServiceAccount(env) {
  const rawSecret = normalizeString(env.FIREBASE_SERVICE_ACCOUNT);
  if (!rawSecret) {
    throw new Error("Missing FIREBASE_SERVICE_ACCOUNT secret");
  }

  const parsed = JSON.parse(rawSecret);
  if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT is invalid");
  }

  return parsed;
}

async function verifyFirebaseIdToken(idToken) {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${FIREBASE_WEB_API_KEY}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({idToken}),
    },
  );

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`Firebase token verification failed: ${errorBody}`);
  }

  const data = await response.json();
  const user = Array.isArray(data.users) ? data.users[0] || {} : {};
  return {
    uid: normalizeString(user.localId),
    email: normalizeString(user.email),
  };
}

async function getGoogleAccessToken(serviceAccount) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && now < cachedAccessTokenExpiry - 60) {
    return cachedAccessToken;
  }

  const jwt = await createServiceJwt(serviceAccount, now);
  const response = await fetch(GOOGLE_OAUTH_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`Could not get Google access token: ${errorBody}`);
  }

  const data = await response.json();
  cachedAccessToken = normalizeString(data.access_token);
  cachedAccessTokenExpiry = now + Number(data.expires_in || 3600);
  return cachedAccessToken;
}

async function createServiceJwt(serviceAccount, now) {
  const header = {
    alg: "RS256",
    typ: "JWT",
  };

  const payload = {
    iss: serviceAccount.client_email,
    scope:
      "https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging",
    aud: GOOGLE_OAUTH_TOKEN_URL,
    exp: now + 3600,
    iat: now,
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const unsignedToken = `${encodedHeader}.${encodedPayload}`;

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(serviceAccount.private_key),
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(unsignedToken),
  );

  return `${unsignedToken}.${base64UrlEncode(signature)}`;
}

async function getFirestoreDocument(accessToken, projectId, documentPath) {
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${documentPath}`,
    {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    },
  );

  if (response.status === 404) {
    return null;
  }

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`Firestore request failed: ${errorBody}`);
  }

  return response.json();
}

async function sendFcmMessage({
  accessToken,
  projectId,
  receiverToken,
  chatId,
  senderId,
  senderName,
  body,
}) {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
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
            priority: "HIGH",
            notification: {
              channelId: "swift_chat_channel",
              clickAction: "FLUTTER_NOTIFICATION_CLICK",
              priority: "PRIORITY_MAX",
              defaultSound: true,
              visibility: "PUBLIC",
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
        },
      }),
    },
  );

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`FCM send failed: ${errorBody}`);
  }

  return response.json();
}

function parseFirestoreFields(fields) {
  const parsed = {};
  for (const [key, value] of Object.entries(fields)) {
    parsed[key] = parseFirestoreValue(value);
  }
  return parsed;
}

function parseFirestoreValue(value) {
  if ("stringValue" in value) {
    return value.stringValue;
  }
  if ("integerValue" in value) {
    return Number(value.integerValue);
  }
  if ("doubleValue" in value) {
    return Number(value.doubleValue);
  }
  if ("booleanValue" in value) {
    return Boolean(value.booleanValue);
  }
  if ("timestampValue" in value) {
    return value.timestampValue;
  }
  if ("nullValue" in value) {
    return null;
  }
  if ("mapValue" in value) {
    return parseFirestoreFields(value.mapValue.fields || {});
  }
  if ("arrayValue" in value) {
    return (value.arrayValue.values || []).map(parseFirestoreValue);
  }
  return null;
}

function buildMessagePreview(text) {
  const normalizedText = normalizeString(text);
  if (!normalizedText) {
    return "Sent you a message";
  }

  if (normalizedText.length <= 120) {
    return normalizedText;
  }

  return `${normalizedText.slice(0, 117)}...`;
}

function pemToArrayBuffer(pem) {
  const cleanPem = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const binary = atob(cleanPem);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes.buffer;
}

function base64UrlEncode(input) {
  const bytes = input instanceof ArrayBuffer ?
    new Uint8Array(input) :
    new TextEncoder().encode(input);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders(),
    },
  });
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

function normalizeString(value) {
  return typeof value === "string" ? value.trim() : "";
}
