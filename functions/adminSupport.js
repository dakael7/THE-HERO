const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {
  DEFAULT_RIDER_SERVICE_FEE_CLP,
  DEFAULT_RIDER_TAX_PERCENTAGE,
  normalizeNonNegativeNumber: _normalizeNonNegativeNumber,
  round2: _round2,
  toCents: _toCents,
} = require("./money");

function _getBearerToken(req) {
  const authHeader = req.get("authorization") || req.get("Authorization") || "";
  const prefix = "bearer ";
  const raw = String(authHeader || "");
  if (!raw.toLowerCase().startsWith(prefix)) return null;
  const token = raw.slice(prefix.length).trim();
  return token || null;
}

async function _requireWebAdmin(req) {
  const idToken = _getBearerToken(req);
  if (!idToken) {
    return {
      ok: false,
      status: 401,
      message: "Missing Authorization Bearer token",
    };
  }

  let decoded;
  try {
    decoded = await admin.auth().verifyIdToken(idToken);
  } catch (e) {
    logger.warn("[auth] invalid token", e);
    return { ok: false, status: 401, message: "Invalid token" };
  }

  const uid = decoded?.uid ? String(decoded.uid) : null;
  if (!uid) {
    return { ok: false, status: 401, message: "Invalid token" };
  }

  const firestore = admin.firestore();
  const adminSnap = await firestore.collection("web_admins").doc(uid).get();
  if (!adminSnap.exists) {
    return { ok: false, status: 403, message: "Forbidden" };
  }

  const adminData = adminSnap.data() || {};
  if (adminData.enabled === false) {
    return { ok: false, status: 403, message: "Forbidden" };
  }

  return { ok: true, uid, email: decoded.email || null };
}

async function _logModerationEvent({
  actorUid,
  actorEmail,
  targetType,
  targetId,
  action,
  payload,
}) {
  const firestore = admin.firestore();
  const event = {
    actorUid: actorUid || null,
    actorEmail: actorEmail || null,
    targetType: String(targetType || '').trim(),
    targetId: String(targetId || '').trim(),
    action: String(action || '').trim(),
    payload: payload != null && typeof payload === 'object' ? payload : null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  // Best-effort: do not throw if logging fails.
  try {
    await firestore.collection('moderation_events').add(event);
  } catch (e) {
    logger.warn('[moderation_events] failed to log event', e);
  }
}


function _pickVehicleMap(input) {
  if (input == null) return null;
  if (typeof input !== "object") return null;

  const allowed = new Set(["bicycle", "motorcycle", "car", "truck"]);
  const out = {};
  for (const [k, v] of Object.entries(input)) {
    const key = String(k || "").trim();
    if (!allowed.has(key)) continue;
    const num = _normalizeNonNegativeNumber(v);
    if (num == null) continue;
    out[key] = num;
  }
  return Object.keys(out).length ? out : null;
}

function _normalizePositiveInt(value, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n) || Number.isNaN(n) || n <= 0) return fallback;
  return Math.floor(n);
}

function _parseMillisToTimestamp(value) {
  if (value == null) return null;
  const n = Number(value);
  if (!Number.isFinite(n) || Number.isNaN(n)) return null;
  return admin.firestore.Timestamp.fromMillis(n);
}

function _docIdOrderBy(query, direction) {
  return query.orderBy(admin.firestore.FieldPath.documentId(), direction);
}

async function _getInboxPage(collectionName, req, filter) {
  const firestore = admin.firestore();

  const limit = _normalizePositiveInt(req.query?.limit, 25);
  const startAfterLastReportedAtMs = req.query?.startAfterLastReportedAtMs;
  const startAfterId = req.query?.startAfterId;

  let q = firestore
    .collection(collectionName)
    .where(filter.field, "==", filter.value)
    .orderBy(filter.orderByField, "desc");

  q = _docIdOrderBy(q, "desc");

  if (startAfterLastReportedAtMs != null && startAfterId != null) {
    const ts = _parseMillisToTimestamp(startAfterLastReportedAtMs);
    if (ts) {
      q = q.startAfter(ts, String(startAfterId));
    }
  }

  q = q.limit(limit);
  const snap = await q.get();

  const items = snap.docs.map((d) => ({ id: d.id, data: d.data() || {} }));
  const last = snap.docs.length ? snap.docs[snap.docs.length - 1] : null;
  const lastData = last ? last.data() || {} : null;

  return {
    items,
    nextPage: last
      ? {
          startAfterLastReportedAtMs: lastData?.[filter.orderByField]?.toMillis
            ? lastData[filter.orderByField].toMillis()
            : null,
          startAfterId: last.id,
        }
      : null,
  };
}

exports.adminUpdatePricing = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const pricePerKm = _pickVehicleMap(req.body?.pricePerKm);
      const minimumCharge = _pickVehicleMap(req.body?.minimumCharge);

      const taxBasisPoints = req.body?.taxBasisPoints;
      const taxPercent = req.body?.taxPercent;
      const taxPercentage = req.body?.taxPercentage;

      // maxDistanceKm: vehicle → km (null allowed = uncapped)
      const maxDistanceKmRaw = req.body?.maxDistanceKm;
      let maxDistanceKmUpdate = null;
      if (maxDistanceKmRaw != null && typeof maxDistanceKmRaw === "object") {
        const allowed = new Set(["bicycle", "motorcycle", "car", "truck"]);
        const out = {};
        for (const [k, v] of Object.entries(maxDistanceKmRaw)) {
          const key = String(k || "").trim();
          if (!allowed.has(key)) continue;
          if (v === null) {
            out[key] = null; // null = infinity in Flutter
            continue;
          }
          const num = _normalizeNonNegativeNumber(v);
          if (num == null) continue;
          out[key] = num;
        }
        if (Object.keys(out).length) maxDistanceKmUpdate = out;
      }

      // riderCommission: { serviceFeeCLP, taxPercent }
      const riderCommissionRaw = req.body?.riderCommission;
      let riderCommissionUpdate = null;
      if (
        riderCommissionRaw != null &&
        typeof riderCommissionRaw === "object"
      ) {
        riderCommissionUpdate = {};
        const feeCLP = _normalizeNonNegativeNumber(
          riderCommissionRaw.serviceFeeCLP,
        );
        const riderTaxPercent = _normalizeNonNegativeNumber(
          riderCommissionRaw.taxPercent ?? riderCommissionRaw.taxPercentage,
        );
        if (feeCLP != null) riderCommissionUpdate.serviceFeeCLP = feeCLP;
        if (riderTaxPercent != null)
          riderCommissionUpdate.taxPercent = riderTaxPercent;
        if (!Object.keys(riderCommissionUpdate).length)
          riderCommissionUpdate = null;
      }

      const update = {};
      if (pricePerKm != null) update.pricePerKm = pricePerKm;
      if (minimumCharge != null) update.minimumCharge = minimumCharge;
      if (maxDistanceKmUpdate != null)
        update.maxDistanceKm = maxDistanceKmUpdate;
      if (riderCommissionUpdate != null)
        update.riderCommission = riderCommissionUpdate;

      // distanceDiscount: per-vehicle { thresholdKm, reducedPricePerKm }
      // null for a vehicle key = disable discount for that vehicle.
      const distanceDiscountRaw = req.body?.distanceDiscount;
      let distanceDiscountUpdate = null;
      if (distanceDiscountRaw != null && typeof distanceDiscountRaw === 'object') {
        const allowed = new Set(['bicycle', 'motorcycle', 'car', 'truck']);
        const out = {};
        for (const [k, v] of Object.entries(distanceDiscountRaw)) {
          const key = String(k || '').trim();
          if (!allowed.has(key)) continue;
          if (v === null) {
            out[key] = null; // null = no discount for this vehicle
            continue;
          }
          if (typeof v !== 'object') continue;
          const threshold = _normalizeNonNegativeNumber(v.thresholdKm);
          const reduced = _normalizeNonNegativeNumber(v.reducedPricePerKm);
          if (threshold == null && reduced == null) continue;
          out[key] = {};
          if (threshold != null) out[key].thresholdKm = threshold;
          if (reduced != null) out[key].reducedPricePerKm = reduced;
        }
        if (Object.keys(out).length) distanceDiscountUpdate = out;
      }
      if (distanceDiscountUpdate != null) update.distanceDiscount = distanceDiscountUpdate;


      const taxBpsNum = _normalizeNonNegativeNumber(taxBasisPoints);
      const taxPercentNum = _normalizeNonNegativeNumber(taxPercent);
      const taxPercentageNum = _normalizeNonNegativeNumber(taxPercentage);

      if (taxBpsNum != null) update.taxBasisPoints = taxBpsNum;
      if (taxPercentNum != null) update.taxPercent = taxPercentNum;
      if (taxPercentageNum != null) update.taxPercentage = taxPercentageNum;

      if (!Object.keys(update).length) {
        return res.status(400).json({ error: "No valid fields to update" });
      }

      update.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      update.updatedByUid = authCheck.uid;
      if (authCheck.email) update.updatedByEmail = authCheck.email;

      const firestore = admin.firestore();
      await firestore
        .collection("settings")
        .doc("pricing")
        .set(update, { merge: true });

      return res.status(200).json({ ok: true });
    } catch (e) {
      logger.error("[adminUpdatePricing] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminGetPricing = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "GET") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const firestore = admin.firestore();
      const snap = await firestore.collection("settings").doc("pricing").get();
      const data = snap.exists ? snap.data() : null;

      return res.status(200).json({
        ok: true,
        exists: snap.exists,
        pricing: data || {},
      });
    } catch (e) {
      logger.error("[adminGetPricing] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportInboxOffers = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "GET") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const page = await _getInboxPage("offers", req, {
        field: "supportReviewStatus",
        value: "pending",
        orderByField: "lastReportedAt",
      });

      return res.status(200).json({ ok: true, ...page });
    } catch (e) {
      logger.error("[adminSupportInboxOffers] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportInboxUsers = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "GET") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const page = await _getInboxPage("users", req, {
        field: "supportReviewStatus",
        value: "pending",
        orderByField: "lastReportedAt",
      });

      return res.status(200).json({ ok: true, ...page });
    } catch (e) {
      logger.error("[adminSupportInboxUsers] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportGetOffer = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "GET") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const offerId = String(req.query?.offerId || "").trim();
      if (!offerId) {
        return res.status(400).json({ error: "Missing offerId" });
      }

      const firestore = admin.firestore();
      const snap = await firestore.collection("offers").doc(offerId).get();
      if (!snap.exists) {
        return res.status(404).json({ error: "Not found" });
      }

      return res
        .status(200)
        .json({ ok: true, offer: { id: snap.id, data: snap.data() || {} } });
    } catch (e) {
      logger.error("[adminSupportGetOffer] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportGetUser = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "GET") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const userId = String(req.query?.userId || "").trim();
      if (!userId) {
        return res.status(400).json({ error: "Missing userId" });
      }

      const firestore = admin.firestore();
      const snap = await firestore.collection("users").doc(userId).get();
      if (!snap.exists) {
        return res.status(404).json({ error: "Not found" });
      }

      return res
        .status(200)
        .json({ ok: true, user: { id: snap.id, data: snap.data() || {} } });
    } catch (e) {
      logger.error("[adminSupportGetUser] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportListOfferReports = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "GET") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const offerId = String(req.query?.offerId || "").trim();
      if (!offerId) {
        return res.status(400).json({ error: "Missing offerId" });
      }

      const limit = _normalizePositiveInt(req.query?.limit, 200);
      const firestore = admin.firestore();
      const snap = await firestore
        .collection("offers")
        .doc(offerId)
        .collection("reports")
        .orderBy("createdAt", "desc")
        .limit(limit)
        .get();

      const reports = snap.docs.map((d) => ({ id: d.id, data: d.data() || {} }));
      return res.status(200).json({ ok: true, reports });
    } catch (e) {
      logger.error("[adminSupportListOfferReports] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportListUserReports = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "GET") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const userId = String(req.query?.userId || "").trim();
      if (!userId) {
        return res.status(400).json({ error: "Missing userId" });
      }

      const limit = _normalizePositiveInt(req.query?.limit, 200);
      const firestore = admin.firestore();
      const snap = await firestore
        .collection("users")
        .doc(userId)
        .collection("reports")
        .orderBy("createdAt", "desc")
        .limit(limit)
        .get();

      const reports = snap.docs.map((d) => ({ id: d.id, data: d.data() || {} }));
      return res.status(200).json({ ok: true, reports });
    } catch (e) {
      logger.error("[adminSupportListUserReports] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportSetOfferReviewStatus = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const offerId = String(req.body?.offerId || "").trim();
      const status = String(req.body?.status || "").trim();
      const notes = req.body?.notes != null ? String(req.body.notes) : null;

      if (!offerId) return res.status(400).json({ error: "Missing offerId" });
      if (!new Set(["reviewed", "dismissed"]).has(status)) {
        return res.status(400).json({ error: "Invalid status" });
      }

      const firestore = admin.firestore();
      await firestore.collection("offers").doc(offerId).set(
        {
          supportReviewStatus: status,
          lastModeratedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(notes != null ? { moderationNotes: notes } : {}),
          moderatedByUid: authCheck.uid,
          ...(authCheck.email ? { moderatedByEmail: authCheck.email } : {}),
        },
        { merge: true },
      );

      await _logModerationEvent({
        actorUid: authCheck.uid,
        actorEmail: authCheck.email,
        targetType: 'offer',
        targetId: offerId,
        action: 'set_review_status',
        payload: { status, notes },
      });

      return res.status(200).json({ ok: true });
    } catch (e) {
      logger.error("[adminSupportSetOfferReviewStatus] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportSetUserReviewStatus = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const userId = String(req.body?.userId || "").trim();
      const status = String(req.body?.status || "").trim();
      const notes = req.body?.notes != null ? String(req.body.notes) : null;

      if (!userId) return res.status(400).json({ error: "Missing userId" });
      if (!new Set(["reviewed", "dismissed"]).has(status)) {
        return res.status(400).json({ error: "Invalid status" });
      }

      const firestore = admin.firestore();
      await firestore.collection("users").doc(userId).set(
        {
          supportReviewStatus: status,
          lastModeratedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(notes != null ? { moderationNotes: notes } : {}),
          moderatedByUid: authCheck.uid,
          ...(authCheck.email ? { moderatedByEmail: authCheck.email } : {}),
        },
        { merge: true },
      );

      await _logModerationEvent({
        actorUid: authCheck.uid,
        actorEmail: authCheck.email,
        targetType: 'user',
        targetId: userId,
        action: 'set_review_status',
        payload: { status, notes },
      });

      return res.status(200).json({ ok: true });
    } catch (e) {
      logger.error("[adminSupportSetUserReviewStatus] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportModerateOffer = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const offerId = String(req.body?.offerId || "").trim();
      const moderationStatus = String(req.body?.moderationStatus || "").trim();
      const notes = req.body?.notes != null ? String(req.body.notes) : null;

      if (!offerId) return res.status(400).json({ error: "Missing offerId" });
      if (!new Set(["visible", "hidden", "blocked"]).has(moderationStatus)) {
        return res.status(400).json({ error: "Invalid moderationStatus" });
      }

      const firestore = admin.firestore();
      await firestore.collection("offers").doc(offerId).set(
        {
          moderationStatus,
          supportReviewStatus: "reviewed",
          lastModeratedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(notes != null ? { moderationNotes: notes } : {}),
          moderatedByUid: authCheck.uid,
          ...(authCheck.email ? { moderatedByEmail: authCheck.email } : {}),
        },
        { merge: true },
      );

      await _logModerationEvent({
        actorUid: authCheck.uid,
        actorEmail: authCheck.email,
        targetType: 'offer',
        targetId: offerId,
        action: 'set_moderation_status',
        payload: { moderationStatus, notes },
      });

      return res.status(200).json({ ok: true });
    } catch (e) {
      logger.error("[adminSupportModerateOffer] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportModerateUser = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const userId = String(req.body?.userId || "").trim();
      const accountStatus = String(req.body?.accountStatus || "").trim();
      const suspendedUntilMs = req.body?.suspendedUntilMs;
      const notes = req.body?.notes != null ? String(req.body.notes) : null;

      if (!userId) return res.status(400).json({ error: "Missing userId" });
      if (!new Set(["active", "suspended", "banned"]).has(accountStatus)) {
        return res.status(400).json({ error: "Invalid accountStatus" });
      }

      let suspendedUntil = null;
      if (accountStatus === "suspended") {
        suspendedUntil = _parseMillisToTimestamp(suspendedUntilMs);
        if (!suspendedUntil) {
          return res.status(400).json({ error: "Missing/invalid suspendedUntilMs" });
        }
      }

      const firestore = admin.firestore();
      await firestore.collection("users").doc(userId).set(
        {
          accountStatus,
          suspendedUntil: accountStatus === "suspended" ? suspendedUntil : null,
          supportReviewStatus: "reviewed",
          lastModeratedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(notes != null ? { moderationNotes: notes } : {}),
          moderatedByUid: authCheck.uid,
          ...(authCheck.email ? { moderatedByEmail: authCheck.email } : {}),
        },
        { merge: true },
      );

      await _logModerationEvent({
        actorUid: authCheck.uid,
        actorEmail: authCheck.email,
        targetType: 'user',
        targetId: userId,
        action: 'set_account_status',
        payload: {
          accountStatus,
          suspendedUntilMs: suspendedUntil ? suspendedUntil.toMillis() : null,
          notes,
        },
      });

      return res.status(200).json({ ok: true });
    } catch (e) {
      logger.error("[adminSupportModerateUser] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportDeleteOffer = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const offerId = String(req.body?.offerId || "").trim();
      if (!offerId) return res.status(400).json({ error: "Missing offerId" });

      const firestore = admin.firestore();
      const offerRef = firestore.collection("offers").doc(offerId);
      await firestore.recursiveDelete(offerRef);

      await _logModerationEvent({
        actorUid: authCheck.uid,
        actorEmail: authCheck.email,
        targetType: 'offer',
        targetId: offerId,
        action: 'delete_offer',
        payload: null,
      });

      return res.status(200).json({ ok: true });
    } catch (e) {
      logger.error("[adminSupportDeleteOffer] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminPayoutRider = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const riderId = String(req.body?.riderId || "").trim();
      const idempotencyKey = String(req.body?.idempotencyKey || "").trim();
      const reference =
        req.body?.reference != null ? String(req.body.reference) : null;
      const note = req.body?.note != null ? String(req.body.note) : null;

      if (!riderId) {
        return res.status(400).json({ error: "riderId is required" });
      }
      if (!idempotencyKey) {
        return res.status(400).json({ error: "idempotencyKey is required" });
      }

      const requestedCents =
        req.body?.amount == null ? null : _toCents(req.body.amount);
      if (
        req.body?.amount != null &&
        (requestedCents == null || requestedCents <= 0)
      ) {
        return res.status(400).json({ error: "amount must be > 0" });
      }

      const firestore = admin.firestore();
      const userRef = firestore.collection("users").doc(riderId);
      const idemRef = firestore
        .collection("admin_payout_requests")
        .doc(idempotencyKey);
      const payoutTxRef = userRef.collection("riderWalletTransactions").doc();

      const result = await firestore.runTransaction(async (tx) => {
        const idemSnap = await tx.get(idemRef);
        if (idemSnap.exists) {
          const idem = idemSnap.data() || {};
          if (idem.status === "completed") {
            return {
              replay: true,
              riderId,
              payoutTxId: idem.payoutTxId || null,
              paidAmount: idem.paidAmount || 0,
              paidAmountCents: idem.paidAmountCents || 0,
              currency: idem.currency || "CLP",
              walletBefore: idem.walletBefore || null,
              walletAfter: idem.walletAfter || null,
            };
          }
          throw new Error("Idempotency key is already in use");
        }

        const userSnap = await tx.get(userRef);
        if (!userSnap.exists) {
          throw new Error("Rider not found");
        }
        const user = userSnap.data() || {};
        const wallet =
          user.riderWallet && typeof user.riderWallet === "object"
            ? user.riderWallet
            : {};

        let earningsBalanceCents =
          wallet.earningsBalanceCents != null
            ? Number(wallet.earningsBalanceCents)
            : null;

        const legacyEarnings =
          wallet.earningsBalance != null ? Number(wallet.earningsBalance) : 0;

        if (
          earningsBalanceCents == null ||
          !Number.isFinite(earningsBalanceCents)
        ) {
          earningsBalanceCents = _toCents(legacyEarnings) || 0;
          tx.update(userRef, {
            "riderWallet.earningsBalanceCents": earningsBalanceCents,
          });
        }

        earningsBalanceCents = Math.max(0, Math.trunc(earningsBalanceCents));
        const maxPayableCents = earningsBalanceCents;
        const payoutCents = Math.min(
          requestedCents == null ? maxPayableCents : requestedCents,
          maxPayableCents,
        );

        const isPartial = payoutCents < maxPayableCents;

        if (payoutCents <= 0) {
          const payload = {
            status: "completed",
            riderId,
            payoutTxId: null,
            paidAmountCents: 0,
            paidAmount: 0,
            currency: wallet.currency || "CLP",
            walletBefore: {
              earningsBalanceCents: earningsBalanceCents,
              earningsBalance: legacyEarnings,
            },
            walletAfter: {
              earningsBalanceCents: earningsBalanceCents,
              earningsBalance: legacyEarnings,
            },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          };
          tx.set(idemRef, payload);
          return {
            replay: false,
            riderId,
            payoutTxId: null,
            paidAmountCents: 0,
            paidAmount: 0,
            currency: payload.currency,
            walletBefore: payload.walletBefore,
            walletAfter: payload.walletAfter,
          };
        }

        const paidAmount = payoutCents / 100;
        const walletBefore = {
          earningsBalanceCents: earningsBalanceCents,
          earningsBalance: legacyEarnings,
        };
        const walletAfter = {
          earningsBalanceCents: earningsBalanceCents - payoutCents,
          earningsBalance:
            _round2(legacyEarnings - paidAmount) ?? legacyEarnings - paidAmount,
        };

        tx.set(payoutTxRef, {
          type: "payout",
          riderId,
          amountCents: -payoutCents,
          amount: -paidAmount,
          currency: wallet.currency || "CLP",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          meta: {
            method: "bank_transfer",
            reference,
            note,
            isPartial,
            requestedAmountCents: requestedCents,
          },
        });

        const walletUpdate = {
          "riderWallet.earningsBalanceCents":
            admin.firestore.FieldValue.increment(-payoutCents),
          "riderWallet.earningsBalance":
            admin.firestore.FieldValue.increment(-paidAmount),
        };
        if (!isPartial) {
          walletUpdate["riderWallet.lastPayoutAt"] =
            admin.firestore.FieldValue.serverTimestamp();
          walletUpdate["riderWallet.lastPayoutAmountCents"] = payoutCents;
        }
        tx.update(userRef, walletUpdate);

        tx.set(idemRef, {
          status: "completed",
          riderId,
          payoutTxId: payoutTxRef.id,
          paidAmountCents: payoutCents,
          paidAmount,
          currency: wallet.currency || "CLP",
          walletBefore,
          walletAfter,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return {
          replay: false,
          riderId,
          payoutTxId: payoutTxRef.id,
          paidAmountCents: payoutCents,
          paidAmount,
          currency: wallet.currency || "CLP",
          walletBefore,
          walletAfter,
        };
      });

      return res.status(200).json(result);
    } catch (e) {
      logger.error("[adminPayoutRider] Error", e);
      const msg = e?.message ? String(e.message) : String(e);
      if (msg.toLowerCase().includes("not found")) {
        return res.status(404).json({ error: msg });
      }
      if (msg.toLowerCase().includes("idempotency")) {
        return res.status(409).json({ error: msg });
      }
      return res.status(500).json({ error: msg });
    }
  },
);


