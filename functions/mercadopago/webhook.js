const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {MercadoPagoConfig, Payment} = require("mercadopago");
const crypto = require("crypto");
const {
  getMercadoPagoAccessToken,
  redactMercadoPagoSecrets,
} = require("./credentials");

const _timestampToMillis = (value) => {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const parsed = new Date(value).getTime();
  return Number.isFinite(parsed) ? parsed : 0;
};

const _getHeader = (req, key) => {
  const value =
    req.get?.(key) ??
    req.headers?.[key] ??
    req.headers?.[key.toLowerCase()] ??
    req.headers?.[key.toUpperCase()];
  return value != null ? String(value) : "";
};

const _parseSignatureHeader = (signatureHeader) => {
  const pairs = String(signatureHeader || "")
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);

  const values = {};
  for (const pair of pairs) {
    const idx = pair.indexOf("=");
    if (idx <= 0) continue;
    const key = pair.slice(0, idx).trim().toLowerCase();
    const value = pair.slice(idx + 1).trim();
    if (!key || !value) continue;
    values[key] = value;
  }

  return {
    ts: values.ts || "",
    v1: values.v1 || "",
  };
};

const _safeEqual = (left, right) => {
  const a = String(left || "");
  const b = String(right || "");
  if (!a || !b) return false;
  if (a.length !== b.length) return false;

  const aBuf = Buffer.from(a, "utf8");
  const bBuf = Buffer.from(b, "utf8");
  if (aBuf.length !== bBuf.length) return false;

  return crypto.timingSafeEqual(aBuf, bBuf);
};

const _resolveDataIdForSignature = (query, body) => {
  const raw =
    query?.["data.id"] ??
    query?.data_id ??
    body?.data?.id ??
    query?.id ??
    body?.id ??
    "";

  return String(raw || "").trim().toLowerCase();
};

const _validateWebhookSignature = ({req, query, body, webhookSecret}) => {
  const signatureHeader = _getHeader(req, "x-signature");
  const requestId = _getHeader(req, "x-request-id");
  const {ts, v1} = _parseSignatureHeader(signatureHeader);
  const dataId = _resolveDataIdForSignature(query, body);

  if (!signatureHeader || !requestId || !ts || !v1 || !dataId) {
    return {
      valid: false,
      reason: "missing_fields",
      details: {
        hasSignatureHeader: Boolean(signatureHeader),
        hasRequestId: Boolean(requestId),
        hasTs: Boolean(ts),
        hasV1: Boolean(v1),
        hasDataId: Boolean(dataId),
      },
    };
  }

  const manifest = `id:${dataId};request-id:${requestId};ts:${ts};`;
  const expectedV1 = crypto
    .createHmac("sha256", webhookSecret)
    .update(manifest)
    .digest("hex");

  return {
    valid: _safeEqual(expectedV1.toLowerCase(), v1.toLowerCase()),
    reason: "computed",
    details: {
      requestId,
      dataId,
      ts,
    },
  };
};

/**
 * Webhook handler for MercadoPago payment notifications
 * Updates payment and order status based on payment events
 */
exports.mercadopagoWebhook = onRequest(
  {
    secrets: ["MERCADOPAGO_ACCESS_TOKEN", "MERCADOPAGO_WEBHOOK_SECRET"],
  },
  async (req, res) => {
    try {
      const body = req.body || {};
      const query = req.query || {};

      const topic = (query.topic || query.type || body.topic || body.type || "")
        .toString()
        .toLowerCase();
      const queryId = (query.id || body.id || body?.data?.id || "").toString();

      const webhookSecret = String(process.env.MERCADOPAGO_WEBHOOK_SECRET || "").trim();
      if (!webhookSecret) {
        console.error("MercadoPago webhook secret not configured");
        res.status(500).send("Server configuration error");
        return;
      }

      const signatureValidation = _validateWebhookSignature({
        req,
        query,
        body,
        webhookSecret,
      });
      if (!signatureValidation.valid) {
        console.warn("MercadoPago webhook rejected: invalid signature", {
          topic,
          queryId,
          reason: signatureValidation.reason,
          details: signatureValidation.details,
        });
        res.status(401).send("Invalid webhook signature");
        return;
      }

      console.log("MercadoPago webhook received:", {
        topic,
        queryId,
        query,
        bodyKeys: Object.keys(body || {}),
      });

      // Get MercadoPago Access Token
      const accessToken = getMercadoPagoAccessToken();
      if (!accessToken) {
        console.error("MercadoPago credentials not configured");
        res.status(500).send("Server configuration error");
        return;
      }

      const liveMode =
        typeof body?.live_mode === "boolean"
          ? body.live_mode
          : typeof query?.live_mode === "string"
            ? query.live_mode === "true"
            : null;

      console.log("MercadoPago webhook mode:", {
        live_mode: liveMode,
      });

      try {
        const meRes = await fetch("https://api.mercadopago.com/users/me", {
          method: "GET",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
        });

        if (meRes.ok) {
          const me = await meRes.json();
          console.log(
            "MercadoPago users/me (webhook):",
            JSON.stringify(
              {
                id: me?.id ?? null,
                nickname: me?.nickname ?? null,
                site_id: me?.site_id ?? null,
                email: me?.email ?? null,
              },
              null,
              2,
            ),
          );
        } else {
          const text = await meRes.text();
          console.warn(
            "MercadoPago users/me failed (webhook):",
            meRes.status,
            redactMercadoPagoSecrets(text),
          );
        }
      } catch (meErr) {
        console.warn(
          "MercadoPago users/me error (webhook):",
          redactMercadoPagoSecrets(meErr?.message ?? meErr),
        );
      }

      // Initialize MercadoPago client
      const client = new MercadoPagoConfig({
        accessToken: accessToken,
        options: {timeout: 5000},
      });

      const payment = new Payment(client);

      const fetchMerchantOrder = async (merchantOrderId) => {
        const url = `https://api.mercadopago.com/merchant_orders/${merchantOrderId}`;
        const resp = await fetch(url, {
          method: "GET",
          headers: {
            Authorization: `Bearer ${accessToken}`,
          },
        });

        if (!resp.ok) {
          const text = await resp.text().catch(() => "");
          throw new Error(
            `Failed to fetch merchant_order ${merchantOrderId}: ${resp.status} ${text}`,
          );
        }

        return await resp.json();
      };

      const searchPaymentsByExternalReference = async (externalReference) => {
        if (!externalReference) return [];
        const url = new URL("https://api.mercadopago.com/v1/payments/search");
        url.searchParams.set("external_reference", String(externalReference));

        const resp = await fetch(url.toString(), {
          method: "GET",
          headers: {
            Authorization: `Bearer ${accessToken}`,
          },
        });

        if (!resp.ok) {
          const text = await resp.text().catch(() => "");
          throw new Error(
            `Failed to search payments by external_reference ${externalReference}: ${resp.status} ${text}`,
          );
        }

        const data = await resp.json();
        return Array.isArray(data?.results) ? data.results : [];
      };

      const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

      const extractLastNumber = (value) => {
        if (!value) return "";
        const s = String(value);
        const match = s.match(/(\d+)(?!.*\d)/);
        return match ? match[1] : "";
      };

      const fetchNotification = async (notificationId) => {
        if (!notificationId) return null;

        const urls = [
          `https://api.mercadopago.com/v1/notifications/${notificationId}`,
          `https://api.mercadopago.com/notifications/${notificationId}`,
        ];

        for (const url of urls) {
          const resp = await fetch(url, {
            method: "GET",
            headers: {
              Authorization: `Bearer ${accessToken}`,
            },
          });

          if (resp.ok) {
            return await resp.json();
          }
        }

        return null;
      };

      const resolvePaymentId = async () => {
        if (topic === "payment") {
          const paymentIdFromQuery = extractLastNumber(query?.["data.id"]);
          const paymentIdFromBody = extractLastNumber(body?.data?.id);
          const paymentIdFromResource = extractLastNumber(body?.resource);
          const paymentIdFromQueryId = extractLastNumber(queryId);
          const notificationId = extractLastNumber(body?.id) || paymentIdFromQueryId;

          // NOTE: Mercado Pago webhooks sometimes include a notification id in `id` and the
          // actual resource id inside `data.id` or `resource`.
          const resolvedPaymentId =
            paymentIdFromQuery ||
            paymentIdFromBody ||
            paymentIdFromResource ||
            paymentIdFromQueryId;

          console.log("Resolved payment id (payment topic):", {
            paymentIdFromQuery,
            paymentIdFromBody,
            paymentIdFromResource,
            paymentIdFromQueryId,
            notificationId,
            resolvedPaymentId,
          });

          return resolvedPaymentId || null;
        }

        if (topic === "merchant_order") {
          if (!queryId) return null;
          let mo = await fetchMerchantOrder(queryId);
          let payments = Array.isArray(mo?.payments) ? mo.payments : [];

          // Mercado Pago can notify merchant_order before the payment is attached.
          // Retry a couple of times to capture the payment id.
          for (let attempt = 1; attempt <= 2 && payments.length === 0; attempt++) {
            await sleep(1500);
            mo = await fetchMerchantOrder(queryId);
            payments = Array.isArray(mo?.payments) ? mo.payments : [];
          }

          if (payments.length === 0) {
            console.log(
              `merchant_order ${queryId} has no payments yet after retries. Current status: ${mo?.status}`,
            );

            const diag = {
              paymentsSearch: {
                byExternalReferenceCount: 0,
                byExternalReferenceSample: [],
              },
            };

            try {
              const externalRef = mo?.external_reference;
              const results = await searchPaymentsByExternalReference(externalRef);
              diag.paymentsSearch.byExternalReferenceCount = results.length;
              diag.paymentsSearch.byExternalReferenceSample = results.slice(0, 5).map((r) => ({
                id: r?.id ?? null,
                status: r?.status ?? null,
                status_detail: r?.status_detail ?? null,
              }));

              if (results.length > 0) {
                const pid = (results[0]?.id ?? "").toString();
                if (pid) {
                  console.log(
                    `Found payment via search for external_reference ${externalRef}: ${pid}`,
                  );
                  return pid;
                }
              }
            } catch (searchErr) {
              console.error(
                `Failed to search payments for merchant_order ${queryId}:`,
                searchErr,
              );
            }

            try {
              await admin
                .firestore()
                .collection("mercadopagoMerchantOrders")
                .doc(String(queryId))
                .set(
                  {
                    merchantOrderId: String(queryId),
                    status: mo?.status ?? null,
                    orderStatus: mo?.order_status ?? null,
                    externalReference: mo?.external_reference ?? null,
                    paymentsCount: payments.length,
                    payments: payments,
                    raw: mo ?? null,
                    diagnostics: diag,
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                  },
                  {merge: true},
                );
            } catch (persistErr) {
              console.error(
                `Failed to persist merchant_order snapshot ${queryId}:`,
                persistErr,
              );
            }

            return null;
          }

          const last = payments[payments.length - 1];
          const pid = (last?.id ?? last?.payment_id ?? "").toString();
          return pid || null;
        }

        // Fallback: old format { type: 'payment', data: { id } }
        const fallbackId = (body?.data?.id ?? body?.id ?? "").toString();
        return fallbackId || null;
      };

      const paymentId = await resolvePaymentId();
      if (!paymentId) {
        res.status(200).send("OK - No payment to process");
        return;
      }

      const persistWebhookError = async (payload) => {
        try {
          await admin
            .firestore()
            .collection("mercadopagoWebhookErrors")
            .add({
              topic,
              queryId,
              paymentId: paymentId?.toString?.() ?? String(paymentId),
              query: query ?? null,
              body: body ?? null,
              ...payload,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
        } catch (persistErr) {
          console.error("Failed to persist webhook error:", persistErr);
        }
      };

      // Get payment details from MercadoPago (with short retry for eventual consistency)
      let paymentData;
      try {
        paymentData = await payment.get({id: paymentId});
      } catch (err) {
        const status = err?.status;
        const errorName = err?.error;

        if (status === 404 || errorName === "not_found") {
          const notificationIdCandidate =
            extractLastNumber(body?.id) || extractLastNumber(queryId);

          if (notificationIdCandidate) {
            try {
              const notif = await fetchNotification(notificationIdCandidate);
              const notifResource = notif?.resource ?? notif?.data?.resource ?? null;
              const paymentIdFromNotifResource = extractLastNumber(notifResource);
              const paymentIdFromNotifData = extractLastNumber(notif?.data?.id);
              const paymentIdFromNotification =
                paymentIdFromNotifResource || paymentIdFromNotifData;

              console.log("Resolved payment from notification:", {
                notificationId: notificationIdCandidate,
                notifResource,
                paymentIdFromNotification,
              });

              if (paymentIdFromNotification && paymentIdFromNotification !== paymentId) {
                try {
                  paymentData = await payment.get({id: paymentIdFromNotification});
                } catch (notifPaymentErr) {
                  await persistWebhookError({
                    error: {
                      message: redactMercadoPagoSecrets(
                        notifPaymentErr?.message ?? notifPaymentErr,
                      ),
                      status: notifPaymentErr?.status ?? null,
                      error: notifPaymentErr?.error ?? null,
                      cause: redactMercadoPagoSecrets(notifPaymentErr?.cause ?? null),
                    },
                    diagnostics: {
                      attemptedPaymentId: paymentId?.toString?.() ?? String(paymentId),
                      notificationId: notificationIdCandidate,
                      notifResource,
                      resolvedPaymentIdFromNotification: paymentIdFromNotification,
                    },
                  });
                  res.status(200).send("OK - Payment not found");
                  return;
                }
              }
            } catch (notifErr) {
              console.warn("Failed to resolve payment via notification:", notifErr);
            }
          }

          if (paymentData) {
            // Resolved via notification.
          } else {
          const delaysMs = [1000, 2000, 4000, 8000];
          let lastErr = err;
          let resolved = false;

          for (let attempt = 0; attempt < delaysMs.length; attempt++) {
            await sleep(delaysMs[attempt]);
            try {
              paymentData = await payment.get({id: paymentId});
              resolved = true;
              break;
            } catch (retryErr) {
              lastErr = retryErr;
              const retryStatus = retryErr?.status;
              const retryErrorName = retryErr?.error;
              if (retryStatus !== 404 && retryErrorName !== "not_found") {
                break;
              }
            }
          }

          if (!resolved) {
            await persistWebhookError({
              error: {
                message: redactMercadoPagoSecrets(lastErr?.message ?? lastErr),
                status: lastErr?.status ?? null,
                error: lastErr?.error ?? null,
                cause: redactMercadoPagoSecrets(lastErr?.cause ?? null),
              },
              diagnostics: {
                attemptedPaymentId: paymentId?.toString?.() ?? String(paymentId),
                notificationId: notificationIdCandidate,
                retryDelaysMs: delaysMs,
              },
            });
            res.status(200).send("OK - Payment not found");
            return;
          }
          }
        } else {
          await persistWebhookError({
            error: {
              message: redactMercadoPagoSecrets(err?.message ?? err),
              status: err?.status ?? null,
              error: err?.error ?? null,
              cause: redactMercadoPagoSecrets(err?.cause ?? null),
            },
          });
          throw err;
        }
      }

      console.log("Payment data from MercadoPago:", {
        id: paymentData.id,
        status: paymentData.status,
        status_detail: paymentData.status_detail,
        external_reference: paymentData.external_reference,
      });

      const orderId = paymentData.external_reference;
      if (!orderId) {
        console.error("No external_reference (orderId) in payment");
        res.status(400).send("Missing order reference");
        return;
      }

      const reservationRef = admin
        .firestore()
        .collection("stockReservations")
        .doc(String(orderId));

      const restoreReservationStockIfNeeded = async () => {
        await admin.firestore().runTransaction(async (transaction) => {
          const reservationDoc = await transaction.get(reservationRef);
          if (!reservationDoc.exists) return;

          const reservation = reservationDoc.data() || {};
          if (reservation.status !== "reserved") return;

          const items = Array.isArray(reservation.items) ? reservation.items : [];

          const offerQtyDeltas = new Map();
          for (const item of items) {
            const offerId = item.offerId;
            if (!offerId) continue;

            const qty = Number(item.qty ?? 1);
            const qtyInt = Number.isFinite(qty) ? Math.max(1, Math.round(qty)) : 1;
            const key = String(offerId);
            offerQtyDeltas.set(key, (offerQtyDeltas.get(key) ?? 0) + qtyInt);
          }

          const offerDocs = new Map();
          for (const [offerId] of offerQtyDeltas) {
            const offerRef = admin.firestore().collection("offers").doc(offerId);
            const offerDoc = await transaction.get(offerRef);
            offerDocs.set(offerId, {ref: offerRef, doc: offerDoc});
          }

          for (const [offerId, delta] of offerQtyDeltas) {
            const entry = offerDocs.get(offerId);
            if (!entry?.doc?.exists) continue;

            const data = entry.doc.data() || {};
            const currentQty = Number(data.availableQty ?? 0);
            const newQty = currentQty + Number(delta ?? 0);

            const updateData = {
              availableQty: newQty,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            };

            if (data.status === "sold_out" && newQty > 0) {
              updateData.status = "active";
            }

            transaction.update(entry.ref, updateData);
          }

          transaction.update(reservationRef, {
            status: "released",
            releasedAt: admin.firestore.FieldValue.serverTimestamp(),
            paymentStatusSnapshot: paymentData.status,
          });
        });
      };

      const consumeReservationIfNeeded = async () => {
        let consumed = false;
        await admin.firestore().runTransaction(async (transaction) => {
          const reservationDoc = await transaction.get(reservationRef);
          if (!reservationDoc.exists) return;

          const reservation = reservationDoc.data() || {};
          if (reservation.status !== "reserved") return;

          const expiresAtMs = _timestampToMillis(reservation.expiresAt);
          if (expiresAtMs > 0 && expiresAtMs <= Date.now()) return;

          transaction.update(reservationRef, {
            status: "consumed",
            consumedAt: admin.firestore.FieldValue.serverTimestamp(),
            paymentId: paymentData.id?.toString?.() ?? null,
          });
          consumed = true;
        });
        return consumed;
      };

      // Update payment document in Firestore
      const paymentsCollection = admin.firestore().collection("payments");

      const preferenceIdForDoc = (paymentData.preference_id ?? "").toString();
      const mpPaymentIdForDoc = (paymentData.id ?? "").toString();

      // The client creates an initial payment doc with id = preferenceId.
      // If we only write to doc(paymentId), the UI/order stays pending because it watches doc(preferenceId).
      const primaryPaymentDocId = preferenceIdForDoc || mpPaymentIdForDoc;
      const paymentRef = paymentsCollection.doc(primaryPaymentDocId);

      const paymentUpdate = {
        paymentId: paymentData.id.toString(),
        preferenceId: preferenceIdForDoc || null,
        status: paymentData.status,
        statusDetail: paymentData.status_detail,
        paymentMethod: paymentData.payment_type_id,
        paymentMethodId: paymentData.payment_method_id,
        amount: paymentData.transaction_amount,
        currency: paymentData.currency_id,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          transactionAmount: paymentData.transaction_amount,
          netAmount: paymentData.transaction_details?.net_received_amount,
          installments: paymentData.installments,
          cardLastFourDigits: paymentData.card?.last_four_digits,
        },
      };

      if (!preferenceIdForDoc) {
        delete paymentUpdate.preferenceId;
      }

      // If approved, add approval timestamp
      if (paymentData.status === "approved") {
        paymentUpdate.approvedAt = admin.firestore.FieldValue.serverTimestamp();
      }

      await paymentRef.set(paymentUpdate, {merge: true});

      // Mirror update into doc(paymentId) as well (optional), to keep a lookup by MercadoPago payment id.
      if (mpPaymentIdForDoc && mpPaymentIdForDoc !== primaryPaymentDocId) {
        await paymentsCollection.doc(mpPaymentIdForDoc).set(paymentUpdate, {merge: true});
      }

      // Fallback: if Mercado Pago doesn't provide a preference_id (can happen in sandbox / some flows),
      // update the payment doc created by the client (usually docId = preferenceId) by looking it up via orderId.
      if (!preferenceIdForDoc && orderId) {
        const candidateSnap = await paymentsCollection
          .where("orderId", "==", String(orderId))
          .get();

        const tsToMillis = (value) => {
          if (!value) return 0;
          if (typeof value.toMillis === "function") return value.toMillis();
          const asDate = new Date(value);
          const ms = asDate.getTime();
          return Number.isFinite(ms) ? ms : 0;
        };

        const candidates = candidateSnap.docs
          .filter((doc) => doc.id !== primaryPaymentDocId && doc.id !== mpPaymentIdForDoc)
          .map((doc) => {
            const data = doc.data() || {};
            return {
              ref: doc.ref,
              updatedAtMs: tsToMillis(data.updatedAt),
              createdAtMs: tsToMillis(data.createdAt),
              id: doc.id,
            };
          })
          .sort((a, b) => {
            if (b.updatedAtMs !== a.updatedAtMs) return b.updatedAtMs - a.updatedAtMs;
            if (b.createdAtMs !== a.createdAtMs) return b.createdAtMs - a.createdAtMs;
            return a.id.localeCompare(b.id);
          });

        if (candidates.length > 0) {
          await candidates[0].ref.set(paymentUpdate, {merge: true});
        }
      }

      // Update order status based on payment status
      const ordersCollection = admin.firestore().collection("orders");
      const rawOrderId = String(orderId);
      const prefixedOrderId = rawOrderId.startsWith("HRO-")
        ? rawOrderId
        : `HRO-${rawOrderId}`;
      const unprefixedOrderId = rawOrderId.startsWith("HRO-")
        ? rawOrderId.substring(4)
        : rawOrderId;

      const candidateOrderIds = [rawOrderId, prefixedOrderId, unprefixedOrderId]
        .filter(Boolean)
        .filter((v, i, arr) => arr.indexOf(v) === i);

      let orderDoc = null;
      for (const candidateId of candidateOrderIds) {
        const candidateDoc = await ordersCollection.doc(candidateId).get();
        if (candidateDoc.exists) {
          orderDoc = candidateDoc;
          break;
        }
      }

      const fallbackOrderId = prefixedOrderId;

      let newOrderStatus = null;

      switch (paymentData.status) {
      case "approved":
        if (await consumeReservationIfNeeded()) {
          newOrderStatus = "queued"; // Order is ready for riders
        } else {
          console.warn(
            `Approved payment ignored for expired or released reservation order=${orderId}`,
          );
        }
        break;
      case "rejected":
      case "cancelled":
        newOrderStatus = "payment_failed";
        await restoreReservationStockIfNeeded();
        break;
      case "pending":
      case "in_process":
      case "in_mediation":
        newOrderStatus = "pending_payment";
        break;
      case "refunded":
      case "charged_back":
        newOrderStatus = "refunded";
        await restoreReservationStockIfNeeded();
        break;
      }

      if (!orderDoc || !orderDoc.exists) {
        console.warn(
          `Order doc not found for external_reference=${orderId}. Persisting orphan payment update.`,
        );
        await admin
          .firestore()
          .collection("mercadopagoOrphanPayments")
          .doc(String(paymentData.id ?? paymentId))
          .set(
            {
              orderId: String(orderId),
              fallbackOrderId,
              unprefixedOrderId,
              candidateOrderIds,
              paymentId: paymentData.id?.toString?.() ?? String(paymentId),
              preferenceId: preferenceIdForDoc || null,
              status: paymentData.status,
              statusDetail: paymentData.status_detail,
              raw: paymentData ?? null,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
          );
        res.status(200).send("OK - Orphan payment persisted");
        return;
      }

      const resolvedOrderRef = orderDoc.ref;

      if (newOrderStatus) {
        await resolvedOrderRef.set(
          {
            status: newOrderStatus,
            paymentId: paymentData.id.toString(),
            paymentStatus: paymentData.status,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true},
        );
      }
      console.log(`Order ${orderId} status updated to ${newOrderStatus}`);

      res.status(200).send("OK");
    } catch (error) {
      console.error("Error processing webhook:", error);
      res.status(500).send("Internal Server Error");
    }
  },
);
