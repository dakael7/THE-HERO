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
async function sendNotificationToUsers(userIds, notification, data = {}) {
  try {
    const ids = Array.isArray(userIds) ? userIds : [userIds];
    const userTokensMap = new Map(); // Map userId -> tokens[]

    // Get FCM tokens for all users
    for (const userId of ids) {
      const userDoc = await admin
        .firestore()
        .collection("users")
        .doc(userId)
        .get();
      if (userDoc.exists) {
        const userData = userDoc.data();
        const tokens = [];

        if (userData.fcmTokens && Array.isArray(userData.fcmTokens)) {
          tokens.push(...userData.fcmTokens);
        }

        if (userData.fcmToken && typeof userData.fcmToken === "string") {
          const t = userData.fcmToken.trim();
          if (t) tokens.push(t);
        }

        const uniqueTokens = [...new Set(tokens.filter(Boolean))];
        if (uniqueTokens.length > 0) {
          userTokensMap.set(userId, uniqueTokens);
        }
      }
    }

    if (userTokensMap.size === 0) {
      console.log("No FCM tokens found for users:", ids);
      return;
    }

    // Collect all tokens
    const allTokens = [];
    userTokensMap.forEach((tokens) => {
      allTokens.push(...tokens);
    });

    if (allTokens.length === 0) {
      console.log("No FCM tokens to send to");
      return;
    }

    // Build FCM message
    const message = {
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: {
        ...data,
        // Ensure all data values are strings
        ...Object.fromEntries(
          Object.entries(data).map(([k, v]) => [k, String(v)]),
        ),
      },
    };

    if (notification.imageUrl) {
      message.notification.imageUrl = notification.imageUrl;
    }

    // Send to all tokens
    const results = await admin.messaging().sendEachForMulticast({
      tokens: allTokens,
      ...message,
      android: {
        priority: data.priority === "high" ? "high" : "normal",
      },
      apns: {
        payload: {
          aps: {
            contentAvailable: true,
          },
        },
      },
    });

    console.log(
      `Sent ${results.successCount} notifications, ${results.failureCount} failed`,
    );

    // Clean up invalid tokens
    if (results.failureCount > 0) {
      const invalidTokens = [];
      results.responses.forEach((response, idx) => {
        if (!response.success) {
          const errorCode = response.error?.code;
          // Remove tokens that are invalid, not registered, or unregistered
          if (
            errorCode === "messaging/invalid-registration-token" ||
            errorCode === "messaging/registration-token-not-registered"
          ) {
            invalidTokens.push(allTokens[idx]);
          }
        }
      });

      // Remove invalid tokens from user documents
      if (invalidTokens.length > 0) {
        console.log(`Cleaning up ${invalidTokens.length} invalid tokens`);

        for (const [userId, userTokens] of userTokensMap.entries()) {
          const tokensToRemove = userTokens.filter((token) =>
            invalidTokens.includes(token),
          );

          if (tokensToRemove.length > 0) {
            await admin
              .firestore()
              .collection("users")
              .doc(userId)
              .update({
                fcmTokens: admin.firestore.FieldValue.arrayRemove(
                  ...tokensToRemove,
                ),
              });
            console.log(
              `Removed ${tokensToRemove.length} invalid tokens from user ${userId}`,
            );
          }
        }
      }
    }

    // Save notification to Firestore for each user
    const batch = admin.firestore().batch();
    for (const userId of ids) {
      const notificationRef = admin
        .firestore()
        .collection("notifications")
        .doc();
      batch.set(notificationRef, {
        userId,
        type: data.type || "system",
        title: notification.title,
        body: notification.body,
        data,
        action: data.action,
        imageUrl: notification.imageUrl || null,
        priority: data.priority || "normal",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        read: false,
      });
    }
    await batch.commit();
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
        status: newStatus,
        priority: "high",
      });
    }
  },
);

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
 * Callable: Send notification from system operator
 * Allows authorized users to send notifications to specific users or broadcast
 *
 * @param {Object} data - { targetUserIds?: string[], title: string, body: string, type?: string, imageUrl?: string, useTopic?: boolean }
 */
exports.sendOperatorNotification = onCall(async (request) => {
  // Verify user is authorized (support/admin)
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Usuario no autenticado");
  }

  if (!isSupportUser(request.auth)) {
    throw new HttpsError("permission-denied", "No autorizado");
  }

  const { targetUserIds, title, body, type, imageUrl, targetScreen, useTopic } =
    request.data;

  if (!title || !body) {
    throw new HttpsError("invalid-argument", "title y body son requeridos");
  }

  let recipients = targetUserIds;

  if (!recipients || recipients.length === 0) {
    if (useTopic) {
      const message = {
        notification: {
          title,
          body,
        },
        data: {
          type: type || "system",
          action: targetScreen ? "open_screen" : "open_notifications",
          targetScreen: targetScreen || "",
        },
        topic: "all_users",
      };

      if (imageUrl) {
        message.notification.imageUrl = imageUrl;
      }

      await admin.messaging().send(message);

      return {
        success: true,
        method: "topic",
        message: "Notificación enviada a todos los usuarios vía topic",
      };
    } else {
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
  }

  // Send to specific users
  await sendNotificationToUsers(
    recipients,
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
    recipientCount: recipients.length,
    message: `Notificación enviada a ${recipients.length} usuario(s)`,
  };
});

/**
 * Callable: Send broadcast notification using FCM topics
 * More efficient for mass notifications
 *
 * @param {Object} data - { title: string, body: string, topic?: string, imageUrl?: string }
 */
exports.sendBroadcastNotification = onCall(async (request) => {
  // Verify user is authorized (support/admin)
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Usuario no autenticado");
  }

  if (!isSupportUser(request.auth)) {
    throw new HttpsError("permission-denied", "No autorizado");
  }

  const { title, body, topic, imageUrl, type, targetScreen } = request.data;

  if (!title || !body) {
    throw new HttpsError("invalid-argument", "title y body son requeridos");
  }

  const targetTopic = topic || "all_users";

  const message = {
    notification: {
      title,
      body,
    },
    data: {
      type: type || "system",
      action: targetScreen ? "open_screen" : "open_notifications",
      targetScreen: targetScreen || "",
    },
    topic: targetTopic,
    android: {
      priority: "normal",
    },
    apns: {
      payload: {
        aps: {
          contentAvailable: true,
        },
      },
    },
  };

  if (imageUrl) {
    message.notification.imageUrl = imageUrl;
  }

  await admin.messaging().send(message);

  return {
    success: true,
    topic: targetTopic,
    message: `Notificación broadcast enviada al topic '${targetTopic}'`,
  };
});

