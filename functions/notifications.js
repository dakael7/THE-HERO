const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { isSupportUser } = require("./supportAuth");

const STORAGE_REGION = "southamerica-west1";

/**
 * Trigger: Send notification when a new chat message is created.
 * Notifies all participants except the sender.
 */
exports.notifyNewChatMessage = onDocumentWritten(
  { document: "chats/{chatId}/messages/{messageId}", region: STORAGE_REGION },
  async (event) => {
    const before =
      event.data && event.data.before.exists ? event.data.before.data() : null;
    const after =
      event.data && event.data.after.exists ? event.data.after.data() : null;

    // Only on create
    if (!after || before) {
      return;
    }

    const chatId = event.params.chatId;
    const messageId = event.params.messageId;
    const senderId = after.senderId;
    const text = after.text;

    if (!chatId || !senderId) return;

    // Load chat to get participants and context
    const chatSnap = await admin
      .firestore()
      .collection("chats")
      .doc(chatId)
      .get();
    if (!chatSnap.exists) return;
    const chat = chatSnap.data() || {};

    // Sender display name
    let senderName = "Usuario";
    try {
      const senderSnap = await admin
        .firestore()
        .collection("users")
        .doc(senderId)
        .get();
      if (senderSnap.exists) {
        const senderData = senderSnap.data() || {};
        const identity = senderData.identity || {};
        const firstName =
          typeof identity.firstName === "string"
            ? identity.firstName.trim()
            : "";
        const lastName =
          typeof identity.lastName === "string" ? identity.lastName.trim() : "";
        const fullName = `${firstName} ${lastName}`.trim();
        if (fullName) {
          senderName = fullName;
        } else if (
          typeof senderData.fullName === "string" &&
          senderData.fullName.trim()
        ) {
          senderName = senderData.fullName.trim();
        } else if (
          typeof senderData.displayName === "string" &&
          senderData.displayName.trim()
        ) {
          senderName = senderData.displayName.trim();
        }
      }
    } catch (_) {
      // ignore
    }

    const typeRaw =
      typeof chat.type === "string" ? chat.type.toLowerCase() : "";
    const chatLabel = typeRaw.includes("rider") ? "Rider" : "Hero";

    const orderIdRaw =
      typeof chat.orderId === "string" ? chat.orderId.trim() : "";
    const shortOrderId = orderIdRaw
      ? orderIdRaw.length > 8
        ? orderIdRaw.substring(0, 8)
        : orderIdRaw
      : "";

    const participantIds = Array.isArray(chat.participantIds)
      ? chat.participantIds.map((x) => String(x)).filter(Boolean)
      : [];

    const recipients = participantIds.filter((id) => id && id !== senderId);
    if (recipients.length === 0) return;

    const preview = typeof text === "string" ? text.trim() : "";
    const trimmedText =
      preview.length > 140 ? `${preview.substring(0, 137)}...` : preview;
    const body = trimmedText
      ? `${senderName}: ${trimmedText}`
      : `${senderName}: Nuevo mensaje`;

    const title = shortOrderId
      ? `Nuevo mensaje (${chatLabel}) • Pedido #${shortOrderId}`
      : `Nuevo mensaje (${chatLabel})`;

    await sendNotificationToUsers(
      recipients,
      {
        title,
        body,
      },
      {
        type: "chat_message",
        action: "open_chat",
        chatId,
        orderId: chat.orderId || "",
        offerId: chat.offerId || "",
        messageId,
        priority: "high",
      },
    );
  },
);

/**
 * Trigger: Notify hero when rider completes a pickup stop
 * Uses orders/{orderId}.pickupProgress.currentStopIndex (0-based) changes.
 */
exports.notifyPickupStopProgress = onDocumentWritten(
  { document: "orders/{orderId}", region: STORAGE_REGION },
  async (event) => {
    const before =
      event.data && event.data.before.exists ? event.data.before.data() : null;
    const after =
      event.data && event.data.after.exists ? event.data.after.data() : null;

    if (!after || !before) {
      return;
    }

    const orderId = event.params.orderId;
    const heroId = after.heroId;

    const beforeIndexRaw =
      before.pickupProgress &&
      typeof before.pickupProgress.currentStopIndex !== "undefined"
        ? before.pickupProgress.currentStopIndex
        : null;
    const afterIndexRaw =
      after.pickupProgress &&
      typeof after.pickupProgress.currentStopIndex !== "undefined"
        ? after.pickupProgress.currentStopIndex
        : null;

    if (afterIndexRaw === null || typeof afterIndexRaw === "undefined") {
      return;
    }

    // Convert to number and ensure it's a progress forward.
    const beforeIndex =
      beforeIndexRaw === null || typeof beforeIndexRaw === "undefined"
        ? -1
        : Number(beforeIndexRaw);
    const afterIndex = Number(afterIndexRaw);

    if (!Number.isFinite(afterIndex)) {
      return;
    }

    // Only notify when index increases.
    if (afterIndex <= beforeIndex) {
      return;
    }

    const totalStops = Array.isArray(after.pickupStops)
      ? after.pickupStops.length
      : 0;
    if (totalStops <= 0) {
      return;
    }

    const humanIndex = Math.min(Math.max(afterIndex + 1, 1), totalStops);

    console.log(
      `Order ${orderId} pickup progress: ${beforeIndex} -> ${afterIndex} (stop ${humanIndex}/${totalStops})`,
    );

    const isLastStop = humanIndex >= totalStops;
    const ordinal =
      humanIndex === 1
        ? "primer"
        : humanIndex === 2
          ? "segundo"
          : humanIndex === 3
            ? "tercer"
            : `${humanIndex}°`;
    const body = isLastStop
      ? "El rider ya está en el último punto de recogida. Te avisaremos cuando vaya en camino a la entrega."
      : `El rider ya está en el ${ordinal} punto de recogida. Te avisaremos cuando vaya en camino.`;

    await sendNotificationToUsers(
      heroId,
      {
        title: "📦 Tu pedido avanza",
        body,
      },
      {
        type: "pickup_progress",
        action: "open_order",
        orderId,
        pickupStopIndex: String(afterIndex),
        pickupStopsCount: String(totalStops),
        priority: "high",
      },
    );
  },
);


// PUSH NOTIFICATIONS (FCM)
// ==========================================

/**
 * Helper: Send FCM notification to user(s)
 * @param {string|string[]} userIds - Single user ID or array of user IDs
 * @param {Object} notification - { title, body, imageUrl? }
 * @param {Object} data - Custom data payload
 * @returns {Promise<void>}
 */
const ANDROID_CHANNEL_BY_TYPE = {
  order_status: "order_updates",
  pickup_progress: "order_updates",
  seller_order: "order_updates",
  chat_message: "chat_messages",
  nearby_order: "nearby_orders",
};

async function sendNotificationToUsers(userIds, notification, data = {}) {
  try {
    const db = admin.firestore();
    const ids = [...new Set((Array.isArray(userIds) ? userIds : [userIds])
      .map((id) => (typeof id === "string" ? id.trim() : ""))
      .filter(Boolean))];
    if (ids.length === 0) return;

    const stringData = Object.fromEntries(
      Object.entries(data)
        .filter(([, v]) => v !== undefined && v !== null)
        .map(([k, v]) => [k, String(v)]),
    );

    const batch = db.batch();
    for (const userId of ids) {
      batch.set(db.collection("notifications").doc(), {
        userId,
        type: data.type || "system",
        title: notification.title,
        body: notification.body,
        data: stringData,
        action: data.action || null,
        imageUrl: notification.imageUrl || null,
        priority: data.priority || "normal",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        read: false,
      });
    }
    await batch.commit();

    const userDocs = await db.getAll(
      ...ids.map((id) => db.collection("users").doc(id)),
    );
    const targets = []; // { userId, token }
    for (const userDoc of userDocs) {
      if (!userDoc.exists) continue;
      const userData = userDoc.data() || {};
      const tokens = Array.isArray(userData.fcmTokens) ? [...userData.fcmTokens] : [];
      if (typeof userData.fcmToken === "string") tokens.push(userData.fcmToken.trim());
      for (const token of new Set(tokens.filter(Boolean))) {
        targets.push({ userId: userDoc.id, token });
      }
    }

    if (targets.length === 0) {
      console.log("No FCM tokens found for users:", ids);
      return;
    }

    const notificationPayload = {
      title: notification.title,
      body: notification.body,
    };
    if (notification.imageUrl) {
      notificationPayload.imageUrl = notification.imageUrl;
    }
    const isChat = data.type === "chat_message" && stringData.chatId;

    // firebase-admin 10.x has no sendEachForMulticast, and its sendMulticast
    // uses the retired batch endpoint, so send one HTTP v1 message per token.
    const results = await Promise.allSettled(
      targets.map(({ token }) =>
        admin.messaging().send({
          token,
          notification: notificationPayload,
          data: stringData,
          android: {
            priority: data.priority === "high" ? "high" : "normal",
            notification: {
              channelId: ANDROID_CHANNEL_BY_TYPE[data.type] || "system_notifications",
              ...(isChat ? { tag: `chat_${stringData.chatId}` } : {}),
            },
          },
          apns: {
            payload: {
              aps: {
                contentAvailable: true,
                ...(isChat ? { threadId: `chat_${stringData.chatId}` } : {}),
              },
            },
          },
        }),
      ),
    );

    const failedCodes = results
      .filter((r) => r.status === "rejected")
      .map((r) => r.reason?.code || r.reason?.message || "unknown");
    const failed = failedCodes.length;
    console.log(
      `Sent ${results.length - failed} notifications, ${failed} failed` +
        (failed ? ` [${[...new Set(failedCodes)].join(", ")}]` : ""),
    );

    // Clean up dead tokens from both the legacy array and the single-token field.
    const invalidByUser = new Map();
    results.forEach((r, idx) => {
      const code = r.status === "rejected" ? r.reason?.code : null;
      if (
        code === "messaging/invalid-registration-token" ||
        code === "messaging/registration-token-not-registered"
      ) {
        const { userId, token } = targets[idx];
        if (!invalidByUser.has(userId)) invalidByUser.set(userId, []);
        invalidByUser.get(userId).push(token);
      }
    });

    for (const [userId, tokens] of invalidByUser) {
      const userRef = db.collection("users").doc(userId);
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(userRef);
        const current = snap.get("fcmToken");
        tx.update(userRef, {
          fcmTokens: admin.firestore.FieldValue.arrayRemove(...tokens),
          ...(tokens.includes(current) ? { fcmToken: admin.firestore.FieldValue.delete() } : {}),
        });
      });
      console.log(`Removed ${tokens.length} invalid tokens from user ${userId}`);
    }
  } catch (error) {
    console.error("Error sending notification:", error);
    throw error;
  }
}

async function closeChatsForCanceledOrder(orderId, orderData) {
  const db = admin.firestore();
  const snapshot = await db
    .collection("chats")
    .where("orderId", "==", String(orderId))
    .get();

  if (snapshot.empty) return;

  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const cancelReason = orderData?.cancelReason || "Pedido cancelado";
  const closedBy = orderData?.canceledBy || "system:order_canceled";

  snapshot.docs.forEach((doc) => {
    batch.set(
      doc.ref,
      {
        isClosed: true,
        closedAt: now,
        closedReason: cancelReason,
        closedBy,
        updatedAt: now,
      },
      {merge: true},
    );
  });

  await batch.commit();
}

/**
 * Trigger: Send notification when order status changes
 * Notifies hero and rider about order status updates
 */
exports.notifyOrderStatusChange = onDocumentWritten(
  { document: "orders/{orderId}", region: STORAGE_REGION },
  async (event) => {
    const before =
      event.data && event.data.before.exists ? event.data.before.data() : null;
    const after =
      event.data && event.data.after.exists ? event.data.after.data() : null;

    // Only proceed if status changed
    if (!after || !before || before.status === after.status) {
      return;
    }

    const orderId = event.params.orderId;
    const heroId = after.heroId;
    const riderId = after.rider?.assignedRiderId;
    const newStatus = after.status;
    const oldStatus = before.status;

    console.log(
      `Order ${orderId} status changed: ${oldStatus} -> ${newStatus}`,
    );

    if (newStatus === "canceled") {
      await closeChatsForCanceledOrder(orderId, after);
    }

    // Define notification messages for each status
    const statusMessages = {
      // Hero notifications
      hero: {
        assigned: {
          title: "🚴 Rider Asignado",
          body: "Un rider ha sido asignado a tu pedido",
        },
        picked_up: {
          title: "📦 Pedido Recogido",
          body: "Tu pedido ha sido recogido por el rider",
        },
        in_transit: {
          title: "🚚 En Camino",
          body: "Tu pedido está en camino",
        },
        delivered: {
          title: "✅ Pedido Entregado",
          body: "Tu pedido ha sido entregado",
        },
        canceled: {
          title: "❌ Pedido Cancelado",
          body: "Tu pedido ha sido cancelado",
        },
      },
      // Rider notifications
      rider: {
        canceled: {
          title: "❌ Pedido Cancelado",
          body: "El pedido ha sido cancelado",
        },
      },
    };

    // Send notification to hero
    if (statusMessages.hero[newStatus]) {
      await sendNotificationToUsers(heroId, statusMessages.hero[newStatus], {
        type: "order_status",
        action: "open_order",
        orderId,
        status: newStatus,
        priority: "high",
      });
    }

    // Send notification to rider if assigned
    if (riderId && statusMessages.rider[newStatus]) {
      await sendNotificationToUsers(riderId, statusMessages.rider[newStatus], {
        type: "order_status",
        action: "open_order",
        orderId,
        recipientRole: "rider",
        status: newStatus,
        priority: "high",
      });
    }

    // Sellers: a new paid order, or a cancel of one they already had.
    // assigned -> queued (rider released the order) must not look like a new sale.
    const sellerMessage = sellerStatusMessage(oldStatus, newStatus);
    const sellerIds = (Array.isArray(after.sellerHeroIds) ? after.sellerHeroIds : [])
      .map((id) => String(id || "").trim())
      .filter((id) => id && id !== heroId);
    if (sellerMessage && sellerIds.length > 0) {
      await sendNotificationToUsers(sellerIds, sellerMessage, {
        type: "seller_order",
        action: "open_order",
        orderId,
        status: newStatus,
        priority: "high",
      });
    }
  },
);

const PRE_PAYMENT_STATUSES = ["created", "pending_payment", "paid"];
const ACTIVE_STATUSES = ["queued", "assigned", "picked_up", "in_transit"];

function sellerStatusMessage(oldStatus, newStatus) {
  if (newStatus === "queued" && PRE_PAYMENT_STATUSES.includes(oldStatus)) {
    return {
      title: "🛍️ Nuevo pedido recibido",
      body: "Tienes un pedido nuevo. Prepáralo para cuando llegue el rider.",
    };
  }
  if (newStatus === "canceled" && ACTIVE_STATUSES.includes(oldStatus)) {
    return {
      title: "❌ Pedido Cancelado",
      body: "Un pedido que habías recibido fue cancelado.",
    };
  }
  return null;
}

/**
 * Trigger: Notify nearby riders when order is queued
 * Sends notification to riders within a certain radius
 */
exports.notifyNearbyRiders = onDocumentWritten(
  { document: "orders/{orderId}", region: STORAGE_REGION },
  async (event) => {
    const before =
      event.data && event.data.before.exists ? event.data.before.data() : null;
    const after =
      event.data && event.data.after.exists ? event.data.after.data() : null;

    // Only proceed if order just became queued
    if (!after || after.status !== "queued" || before?.status === "queued") {
      return;
    }

    const orderId = event.params.orderId;
    const pickupLocation = after.pickup?.location;

    if (
      !pickupLocation ||
      !pickupLocation.latitude ||
      !pickupLocation.longitude
    ) {
      console.log(
        "Order has no pickup location, skipping nearby rider notification",
      );
      return;
    }

    // Get all active riders
    const ridersSnapshot = await admin
      .firestore()
      .collection("users")
      .where("roles", "array-contains", "rider")
      .where("riderProfile.isActive", "==", true)
      .where("riderProfile.isVerified", "==", true)
      .get();

    if (ridersSnapshot.empty) {
      console.log("No active riders found");
      return;
    }

    // Calculate distance and filter nearby riders (within 10km)
    const RADIUS_KM = 10;
    const nearbyRiders = [];

    for (const riderDoc of ridersSnapshot.docs) {
      const riderData = riderDoc.data();
      const riderLocation = riderData.riderProfile?.currentLocation;

      if (
        !riderLocation ||
        !riderLocation.latitude ||
        !riderLocation.longitude
      ) {
        continue;
      }

      // Simple distance calculation (Haversine formula)
      const distance = calculateDistance(
        pickupLocation.latitude,
        pickupLocation.longitude,
        riderLocation.latitude,
        riderLocation.longitude,
      );

      if (distance <= RADIUS_KM) {
        nearbyRiders.push({
          riderId: riderDoc.id,
          distance,
        });
      }
    }

    if (nearbyRiders.length === 0) {
      console.log("No nearby riders found");
      return;
    }

    console.log(
      `Found ${nearbyRiders.length} nearby riders for order ${orderId}`,
    );

    // Sort by distance
    nearbyRiders.sort((a, b) => a.distance - b.distance);

    // Send notification to nearby riders
    const riderIds = nearbyRiders.map((r) => r.riderId);
    await sendNotificationToUsers(
      riderIds,
      {
        title: "🎯 Nuevo Pedido Cercano",
        body: `Hay un pedido disponible a ${nearbyRiders[0].distance.toFixed(1)} km de ti`,
      },
      {
        type: "nearby_order",
        action: "open_order",
        orderId,
        distance: String(nearbyRiders[0].distance),
        priority: "high",
      },
    );
  },
);

/**
 * Helper: Calculate distance between two coordinates (Haversine formula)
 * @param {number} lat1 - Latitude 1
 * @param {number} lon1 - Longitude 1
 * @param {number} lat2 - Latitude 2
 * @param {number} lon2 - Longitude 2
 * @returns {number} Distance in kilometers
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth's radius in km
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRad(degrees) {
  return degrees * (Math.PI / 180);
}

/**
 * Helper: Send a notification to every user, 500 at a time.
 * The app only subscribes to per-user topics (all_users was dropped on purpose),
 * so broadcasts go through the per-user path, which also fills each inbox.
 */
async function broadcastToAllUsers({ title, body, imageUrl, type, targetScreen }) {
  const BATCH_SIZE = 500;
  let totalSent = 0;
  let lastDoc = null;

  while (true) {
    let query = admin.firestore().collection("users").limit(BATCH_SIZE);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const usersSnapshot = await query.get();
    if (usersSnapshot.empty) {
      break;
    }

    const batchUserIds = usersSnapshot.docs.map((doc) => doc.id);
    await sendNotificationToUsers(
      batchUserIds,
      { title, body, imageUrl },
      {
        type: type || "system",
        action: targetScreen ? "open_screen" : "open_notifications",
        targetScreen,
        priority: "normal",
      },
    );

    totalSent += batchUserIds.length;
    lastDoc = usersSnapshot.docs[usersSnapshot.docs.length - 1];
    if (usersSnapshot.docs.length < BATCH_SIZE) {
      break;
    }
  }

  return {
    success: true,
    method: "paginated",
    recipientCount: totalSent,
    message: `Notificación enviada a ${totalSent} usuario(s)`,
  };
}

function assertSupportRequest(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Usuario no autenticado");
  }
  if (!isSupportUser(request.auth)) {
    throw new HttpsError("permission-denied", "No autorizado");
  }
  const { title, body } = request.data || {};
  if (!title || !body) {
    throw new HttpsError("invalid-argument", "title y body son requeridos");
  }
}

/**
 * Callable: Send notification from system operator
 * Allows authorized users to send notifications to specific users or broadcast
 *
 * @param {Object} data - { targetUserIds?: string[], title: string, body: string, type?: string, imageUrl?: string, targetScreen?: string }
 * `useTopic` is still accepted but ignored: nobody is subscribed to all_users.
 */
exports.sendOperatorNotification = onCall(async (request) => {
  assertSupportRequest(request);
  const { targetUserIds, title, body, type, imageUrl, targetScreen } =
    request.data;

  if (!Array.isArray(targetUserIds) || targetUserIds.length === 0) {
    return broadcastToAllUsers({ title, body, imageUrl, type, targetScreen });
  }

  await sendNotificationToUsers(
    targetUserIds,
    { title, body, imageUrl },
    {
      type: type || "system",
      action: targetScreen ? "open_screen" : "open_notifications",
      targetScreen,
      priority: "normal",
    },
  );

  return {
    success: true,
    method: "direct",
    recipientCount: targetUserIds.length,
    message: `Notificación enviada a ${targetUserIds.length} usuario(s)`,
  };
});

/**
 * Callable: Broadcast notification to every user.
 * Kept for existing callers; `topic` is ignored (see broadcastToAllUsers).
 *
 * @param {Object} data - { title: string, body: string, imageUrl?: string, type?: string, targetScreen?: string }
 */
exports.sendBroadcastNotification = onCall(async (request) => {
  assertSupportRequest(request);
  const { title, body, imageUrl, type, targetScreen } = request.data;
  return broadcastToAllUsers({ title, body, imageUrl, type, targetScreen });
});

exports.sendNotificationToUsers = sendNotificationToUsers;
exports.sellerStatusMessage = sellerStatusMessage;
