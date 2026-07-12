const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

const _deleteQueryDocumentTrees = async (query, stats, statKey) => {
  const snapshot = await query.get();
  if (snapshot.empty) return;

  for (const doc of snapshot.docs) {
    await admin.firestore().recursiveDelete(doc.ref);
    stats[statKey] = (stats[statKey] || 0) + 1;
  }
};

const _deleteDocumentTreeIfExists = async (docRef, stats, statKey) => {
  const snap = await docRef.get();
  if (!snap.exists) return;

  await admin.firestore().recursiveDelete(docRef);
  stats[statKey] = (stats[statKey] || 0) + 1;
};

const _deleteStoragePrefix = async (bucket, prefix, stats) => {
  const [files] = await bucket.getFiles({ prefix });
  if (!files.length) return;

  await Promise.all(files.map((file) => file.delete({ ignoreNotFound: true })));
  stats.storageFiles = (stats.storageFiles || 0) + files.length;
};

exports.deleteMyAccount = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (request) => {
    const uid = request.auth?.uid ? String(request.auth.uid).trim() : "";
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "Debes iniciar sesion para eliminar tu cuenta",
      );
    }

    if (request.data?.confirm !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Confirma la eliminacion de la cuenta para continuar",
      );
    }

    const db = admin.firestore();
    const stats = {};
    const userRef = db.collection("users").doc(uid);

    await userRef.set(
      {
        accountDeletion: {
          status: "processing",
          requestedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      },
      { merge: true },
    );

    try {
      const bucket = admin.storage().bucket();
      await _deleteStoragePrefix(bucket, `users/${uid}/`, stats);
      await _deleteStoragePrefix(bucket, `offers/${uid}/`, stats);
      await _deleteStoragePrefix(bucket, `processed/offers/${uid}/`, stats);

      await _deleteQueryDocumentTrees(
        db.collection("offers").where("heroId", "==", uid),
        stats,
        "offers",
      );
      await _deleteQueryDocumentTrees(
        db.collection("notifications").where("userId", "==", uid),
        stats,
        "notifications",
      );
      await _deleteQueryDocumentTrees(
        db.collection("chats").where("participantIds", "array-contains", uid),
        stats,
        "chats",
      );
      await _deleteQueryDocumentTrees(
        db.collection("offer_reports").where("reporterId", "==", uid),
        stats,
        "offerReports",
      );
      await _deleteQueryDocumentTrees(
        db.collection("user_reports").where("reporterId", "==", uid),
        stats,
        "userReports",
      );

      await _deleteDocumentTreeIfExists(
        db.collection("favorites").doc(uid),
        stats,
        "favoritesRoots",
      );
      await _deleteDocumentTreeIfExists(
        db.collection("user_orders").doc(uid),
        stats,
        "userOrderRoots",
      );
      await _deleteDocumentTreeIfExists(
        db.collection("rider_stats").doc(uid),
        stats,
        "riderStats",
      );
      await _deleteDocumentTreeIfExists(userRef, stats, "users");

      await admin.auth().deleteUser(uid);

      logger.info("Account deleted", { uid, stats });
      return { success: true, stats };
    } catch (error) {
      logger.error("deleteMyAccount failed", { uid, error });
      await userRef.set(
        {
          accountDeletion: {
            status: "failed",
            failedAt: admin.firestore.FieldValue.serverTimestamp(),
            message: error?.message || String(error),
          },
        },
        { merge: true },
      ).catch(() => {});

      throw new HttpsError(
        "internal",
        "No pudimos eliminar la cuenta. Intentalo nuevamente o contacta soporte.",
      );
    }
  },
);


