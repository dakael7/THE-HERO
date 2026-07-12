const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

const STORAGE_REGION = "southamerica-west1";

exports.processOrderRatings = onDocumentWritten(
  { document: "orders/{orderId}", region: STORAGE_REGION },
  async (event) => {
    const before =
      event.data && event.data.before.exists ? event.data.before.data() : null;
    const after =
      event.data && event.data.after.exists ? event.data.after.data() : null;

    if (!after) return;

    const afterConfirmed = after.confirmedByHero === true;
    const afterLegacyRatingsProcessed = after.ratingStatsProcessed === true;

    // Only process when at least one rating field exists.
    // This allows processing even if confirmedByHero was set earlier by another update.
    const heroRating =
      typeof after.heroRating === "number" ? after.heroRating : null;
    const sellerRating =
      typeof after.sellerRating === "number" ? after.sellerRating : null;
    const buyerRating =
      typeof after.buyerRating === "number" ? after.buyerRating : null;
    const hasConfirmedRatings =
      afterConfirmed &&
      !afterLegacyRatingsProcessed &&
      (heroRating != null || sellerRating != null);
    const hasBuyerRating =
      buyerRating != null && after.buyerRatingStatsProcessed !== true;
    if (!hasConfirmedRatings && !hasBuyerRating) return;

    const orderId = event.params.orderId;

    function readString(value) {
      return value != null ? String(value).trim() : "";
    }

    function readSellerHeroId(order) {
      const explicitSellerId = readString(order.sellerRatingHeroId);
      if (explicitSellerId) return explicitSellerId;

      if (Array.isArray(order.sellerHeroIds)) {
        for (const raw of order.sellerHeroIds) {
          const id = readString(raw);
          if (id) return id;
        }
      } else if (typeof order.sellerHeroIds === "string") {
        const id = order.sellerHeroIds.trim();
        if (id) return id;
      }

      if (!Array.isArray(order.items)) return "";
      for (const item of order.items) {
        if (!item || typeof item !== "object") continue;
        const id = readString(item.sellerHeroIdSnapshot);
        if (id) return id;
      }

      return "";
    }

    function readBuyerHeroId(order) {
      return readString(order.heroId);
    }

    function readRiderId(order) {
      return order.rider?.assignedRiderId
        ? String(order.rider.assignedRiderId).trim()
        : "";
    }

    function readBuyerRatingSellerId(order) {
      const explicitSellerId = readString(order.buyerRatingBySellerId);
      if (explicitSellerId) return explicitSellerId;
      return readSellerHeroId(order);
    }

    function applyNewAverage(currentAvg, currentCount, newValue) {
      const safeAvg = typeof currentAvg === "number" ? currentAvg : 0;
      const safeCount = typeof currentCount === "number" ? currentCount : 0;
      const nextCount = safeCount + 1;
      const nextAvg = (safeAvg * safeCount + newValue) / nextCount;
      return {nextAvg, nextCount};
    }

    function updateHeroProfileRatings(tx, snap, ref, ratings) {
      if (
        !ref ||
        !snap ||
        !snap.exists ||
        !Array.isArray(ratings) ||
        ratings.length === 0
      ) {
        return false;
      }
      const data = snap.data() || {};
      const hp =
        data.heroProfile && typeof data.heroProfile === "object"
          ? data.heroProfile
          : {};
      let nextAvg = typeof hp.rating === "number" ? hp.rating : 0;
      let nextCount = typeof hp.totalRatings === "number" ? hp.totalRatings : 0;
      for (const rating of ratings) {
        const next = applyNewAverage(nextAvg, nextCount, rating);
        nextAvg = next.nextAvg;
        nextCount = next.nextCount;
      }
      tx.update(ref, {
        "heroProfile.rating": nextAvg,
        "heroProfile.totalRatings": nextCount,
      });
      return true;
    }

    function updateRiderProfileRating(tx, snap, ref, rating) {
      if (!ref || !snap || !snap.exists || rating == null) return false;
      const data = snap.data() || {};
      const rp =
        data.riderProfile && typeof data.riderProfile === "object"
          ? data.riderProfile
          : {};
      const {nextAvg, nextCount} = applyNewAverage(
        rp.rating,
        rp.totalRatings,
        rating,
      );
      tx.update(ref, {
        "riderProfile.rating": nextAvg,
        "riderProfile.totalRatings": nextCount,
      });
      return true;
    }

    function uniqueRefs(refs) {
      const seen = new Set();
      const out = [];
      for (const entry of refs) {
        if (!entry.ref) continue;
        const path = entry.ref.path;
        if (seen.has(path)) continue;
        seen.add(path);
        out.push(entry);
      }
      return out;
    }

    const db = admin.firestore();
    const orderRef = db.collection("orders").doc(orderId);

    await db.runTransaction(async (tx) => {
      const freshOrderSnap = await tx.get(orderRef);
      const freshOrder = freshOrderSnap.exists ? freshOrderSnap.data() : null;
      if (!freshOrder) return;

      const freshConfirmed = freshOrder.confirmedByHero === true;
      const legacyRatingsProcessed = freshOrder.ratingStatsProcessed === true;
      const freshHeroRating =
        typeof freshOrder.heroRating === "number"
          ? freshOrder.heroRating
          : null;
      const freshSellerRating =
        typeof freshOrder.sellerRating === "number"
          ? freshOrder.sellerRating
          : null;
      const freshBuyerRating =
        typeof freshOrder.buyerRating === "number"
          ? freshOrder.buyerRating
          : null;

      const shouldProcessRider =
        freshConfirmed &&
        !legacyRatingsProcessed &&
        freshOrder.riderRatingStatsProcessed !== true &&
        freshHeroRating != null;
      const shouldProcessSeller =
        freshConfirmed &&
        !legacyRatingsProcessed &&
        freshOrder.sellerRatingStatsProcessed !== true &&
        freshSellerRating != null;
      const shouldProcessBuyer =
        freshOrder.buyerRatingStatsProcessed !== true &&
        freshBuyerRating != null;
      if (!shouldProcessRider && !shouldProcessSeller && !shouldProcessBuyer) {
        return;
      }

      const freshRiderId = readRiderId(freshOrder);
      const freshSellerHeroId = readSellerHeroId(freshOrder);
      const freshBuyerHeroId = readBuyerHeroId(freshOrder);
      const buyerRatingSellerId = readBuyerRatingSellerId(freshOrder);

      const riderRef =
        shouldProcessRider && freshRiderId
          ? db.collection("users").doc(freshRiderId)
          : null;
      const sellerRef =
        shouldProcessSeller && freshSellerHeroId
          ? db.collection("users").doc(freshSellerHeroId)
          : null;
      const buyerRef =
        shouldProcessBuyer && freshBuyerHeroId
          ? db.collection("users").doc(freshBuyerHeroId)
          : null;

      const heroRatingTargets = new Map();
      function addHeroRatingTarget(ref, rating) {
        if (!ref || rating == null) return;
        const path = ref.path;
        const existing = heroRatingTargets.get(path);
        if (existing) {
          existing.ratings.push(rating);
        } else {
          heroRatingTargets.set(path, {ref, ratings: [rating]});
        }
      }
      addHeroRatingTarget(sellerRef, freshSellerRating);
      addHeroRatingTarget(buyerRef, freshBuyerRating);

      const refs = uniqueRefs([
        {key: "rider", ref: riderRef},
        ...Array.from(heroRatingTargets.entries()).map(([key, target]) => ({
          key,
          ref: target.ref,
        })),
      ]);
      const snapsByPath = new Map();
      for (const entry of refs) {
        snapsByPath.set(entry.ref.path, await tx.get(entry.ref));
      }

      const updatePayload = {
        ratingStatsLastProcessedAt:
          admin.firestore.FieldValue.serverTimestamp(),
      };

      if (shouldProcessRider) {
        updateRiderProfileRating(
          tx,
          riderRef ? snapsByPath.get(riderRef.path) : null,
          riderRef,
          freshHeroRating,
        );
        updatePayload.riderRatingStatsProcessed = true;
      }

      for (const target of heroRatingTargets.values()) {
        updateHeroProfileRatings(
          tx,
          snapsByPath.get(target.ref.path),
          target.ref,
          target.ratings,
        );
      }

      if (shouldProcessSeller) {
        updatePayload.sellerRatingStatsProcessed = true;
      }

      if (shouldProcessBuyer) {
        updatePayload.buyerRatingStatsProcessed = true;
        updatePayload.buyerRatingStatsProcessedAt =
          admin.firestore.FieldValue.serverTimestamp();
        if (buyerRatingSellerId) {
          updatePayload.buyerRatingProcessedBySellerId = buyerRatingSellerId;
        }
      }

      if (shouldProcessRider || shouldProcessSeller) {
        updatePayload.ratingStatsProcessed = true;
        updatePayload.ratingStatsProcessedAt =
          admin.firestore.FieldValue.serverTimestamp();
      }

      tx.update(orderRef, updatePayload);
    });
  },
);


