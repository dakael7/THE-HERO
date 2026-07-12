const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

const STORAGE_REGION = "southamerica-west1";

function getIsoWeekKey(date) {
  const d = new Date(
    Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()),
  );
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const weekNo = Math.ceil(((d - yearStart) / 86400000 + 1) / 7);
  const year = d.getUTCFullYear();
  const week = String(weekNo).padStart(2, "0");
  return `${year}-W${week}`;
}

exports.syncRiderStatsOnOrderWrite = onDocumentWritten(
  { document: "orders/{orderId}", region: STORAGE_REGION },
  async (event) => {
    const before =
      event.data && event.data.before.exists ? event.data.before.data() : null;
    const after =
      event.data && event.data.after.exists ? event.data.after.data() : null;

    if (!after) {
      return;
    }

    const beforeStatus =
      before && typeof before.status === "string" ? before.status : null;
    const afterStatus = typeof after.status === "string" ? after.status : null;

    if (beforeStatus === afterStatus) {
      return;
    }

    const riderId =
      (after.rider && after.rider.assignedRiderId) ||
      (before && before.rider && before.rider.assignedRiderId) ||
      null;

    if (!riderId) {
      return;
    }

    const deliveryFee =
      typeof after.deliveryFee === "number" ? after.deliveryFee : 0;
    const tipAfterRaw = typeof after.tip === "number" ? after.tip : 0;
    const tipBeforeRaw =
      before && typeof before.tip === "number" ? before.tip : 0;
    const statsRef = admin.firestore().collection("rider_stats").doc(riderId);
    const inc = admin.firestore.FieldValue.increment;

    const currentWeekKey = getIsoWeekKey(new Date());

    const toCounters = (status) => {
      switch ((status || "").toLowerCase()) {
        case "delivered":
          return { deliveredTrips: 1, canceledTrips: 0, failedTrips: 0 };
        case "canceled":
        case "cancelled":
          return { deliveredTrips: 0, canceledTrips: 1, failedTrips: 0 };
        case "failed":
          return { deliveredTrips: 0, canceledTrips: 0, failedTrips: 1 };
        default:
          return { deliveredTrips: 0, canceledTrips: 0, failedTrips: 0 };
      }
    };

    const isRiderUnassignToQueue = () => {
      const b = (beforeStatus || "").toLowerCase();
      const a = (afterStatus || "").toLowerCase();
      if (!(b === "assigned" && a === "queued")) return false;

      const beforeAssigned =
        before &&
        before.rider &&
        typeof before.rider.assignedRiderId === "string"
          ? before.rider.assignedRiderId
          : null;
      const afterAssigned =
        after && after.rider && typeof after.rider.assignedRiderId === "string"
          ? after.rider.assignedRiderId
          : null;

      const beforeHas = !!(beforeAssigned && beforeAssigned.trim().length > 0);
      const afterHas = !!(afterAssigned && afterAssigned.trim().length > 0);
      return beforeHas && !afterHas;
    };

    const tipIfDelivered = (status, tip) => {
      return (status || "").toLowerCase() === "delivered" ? tip : 0;
    };

    const beforeC = toCounters(beforeStatus);
    const afterC = toCounters(afterStatus);

    const deltaDelivered = afterC.deliveredTrips - beforeC.deliveredTrips;
    let deltaCanceled = afterC.canceledTrips - beforeC.canceledTrips;
    const deltaFailed = afterC.failedTrips - beforeC.failedTrips;

    // Rider unassign (assigned -> queued) should count as a cancellation for rider stats.
    if (isRiderUnassignToQueue()) {
      deltaCanceled += 1;
    }

    const beforeTip = tipIfDelivered(beforeStatus, tipBeforeRaw);
    const afterTip = tipIfDelivered(afterStatus, tipAfterRaw);
    const deltaTips = afterTip - beforeTip;

    const updates = {
      riderId,
      deliveredTrips: inc(deltaDelivered),
      canceledTrips: inc(deltaCanceled),
      failedTrips: inc(deltaFailed),
      tips: inc(deltaTips),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (deltaDelivered !== 0) {
      updates.totalEarnings = inc(deltaDelivered * deliveryFee);
      updates.totalTrips = inc(deltaDelivered);

      const deliveredAt =
        after.timestamps &&
        after.timestamps.deliveredAt &&
        typeof after.timestamps.deliveredAt.toDate === "function"
          ? after.timestamps.deliveredAt.toDate()
          : new Date();
      const deliveredWeekKey = getIsoWeekKey(deliveredAt);

      updates.weekKey = currentWeekKey;

      if (deliveredWeekKey === currentWeekKey) {
        updates.weeklyEarnings = inc(deltaDelivered * deliveryFee);
        updates.weeklyTrips = inc(deltaDelivered);
      }
    }

    if (deltaTips !== 0) {
      updates.totalEarnings = inc(deltaTips);

      const deliveredAtForTips =
        afterStatus && afterStatus.toLowerCase() === "delivered"
          ? after.timestamps &&
            after.timestamps.deliveredAt &&
            typeof after.timestamps.deliveredAt.toDate === "function"
            ? after.timestamps.deliveredAt.toDate()
            : new Date()
          : new Date();

      const tipsWeekKey = getIsoWeekKey(deliveredAtForTips);

      updates.weekKey = currentWeekKey;
      if (tipsWeekKey === currentWeekKey) {
        updates.weeklyEarnings = inc(deltaTips);
      }
    }

    const deltaCompleted = deltaDelivered + deltaCanceled + deltaFailed;
    if (deltaCompleted !== 0) {
      updates.completedTrips = inc(deltaCompleted);
    }

    await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(statsRef);
      const existingWeekKey =
        snap.exists && snap.data() && typeof snap.data().weekKey === "string"
          ? snap.data().weekKey
          : null;

      if (existingWeekKey !== currentWeekKey) {
        tx.set(
          statsRef,
          {
            weekKey: currentWeekKey,
            weeklyEarnings: 0,
            weeklyTrips: 0,
          },
          { merge: true },
        );
      }

      tx.set(statsRef, updates, { merge: true });
    });
  },
);


