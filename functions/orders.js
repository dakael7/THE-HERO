const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {
  DEFAULT_RIDER_SERVICE_FEE_CLP,
  DEFAULT_RIDER_TAX_PERCENTAGE,
  calculateRiderCommission: _calculateRiderCommission,
  normalizeNonNegativeNumber: _normalizeNonNegativeNumber,
  toCents: _toCents,
} = require("./money");
const {assertHeroWeeklyOrderLimit} = require("./orderLimits");
const {isDevCheckoutBypassEnabled} = require('./devMode');
const {
  aggregateOrderItems,
  computeServerOrderMoney,
  isPendingPaymentOrder,
  readCouponDiscount,
  toInt,
} = require("./orderPricing");

function _parseDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === "object" && Number.isFinite(value._seconds)) {
    return new Date((value._seconds * 1000) + Math.round((value._nanoseconds || 0) / 1000000));
  }
  const parsed = new Date(value);
  return Number.isFinite(parsed.getTime()) ? parsed : null;
}

function _toTimestamp(value, fallback) {
  const parsed = _parseDate(value) || fallback;
  return admin.firestore.Timestamp.fromDate(parsed);
}

function _normalizeOrderForCreate(rawOrder, orderId, heroId) {
  const now = new Date();
  const order = rawOrder && typeof rawOrder === "object" ? {...rawOrder} : {};
  delete order.authIdToken;
  const countryCode = String(order.countryCode || "").trim().toUpperCase();
  if (countryCode) {
    order.countryCode = countryCode;
  } else {
    delete order.countryCode;
  }
  const timestamps = order.timestamps && typeof order.timestamps === "object" ?
    {...order.timestamps} :
    {};

  timestamps.createdAt = _toTimestamp(timestamps.createdAt, now);
  for (const key of ["paidAt", "queuedAt", "assignedAt", "pickedUpAt", "deliveredAt", "canceledAt"]) {
    if (timestamps[key]) timestamps[key] = _toTimestamp(timestamps[key], now);
  }

  return {
    ...order,
    orderId,
    heroId,
    timestamps,
    updatedAt: _toTimestamp(order.updatedAt, now),
    ...(order.paymentExpiresAt ? {paymentExpiresAt: _toTimestamp(order.paymentExpiresAt, now)} : {}),
  };
}

function _countryCodeFromUser(data) {
  const address = data?.address && typeof data.address === "object" ?
    data.address :
    {};
  const primarySlot = String(data?.primaryAddressSlot || data?.primaryAddressUnitType || "").trim();
  const slots = data?.addressSlots && typeof data.addressSlots === "object" ?
    data.addressSlots :
    (data?.addressUnits && typeof data.addressUnits === "object" ? data.addressUnits : {});
  const primaryAddress = primarySlot && slots[primarySlot] && typeof slots[primarySlot] === "object" ?
    slots[primarySlot] :
    {};

  return String(primaryAddress.countryCode || address.countryCode || "").trim().toUpperCase();
}

function _normalizePercentage(value) {
  const num = _normalizeNonNegativeNumber(value);
  if (num == null) return null;
  return num > 1 ? num / 100 : num;
}

async function _getRiderCommissionConfig(db) {
  const snap = await db.collection("settings").doc("pricing").get();
  const data = snap.exists ? snap.data() || {} : {};
  const raw = data.riderCommission && typeof data.riderCommission === "object" ?
    data.riderCommission :
    {};

  return {
    riderServiceFeeCLP: DEFAULT_RIDER_SERVICE_FEE_CLP,
    riderTaxPercentage: _normalizePercentage(raw.taxPercent ?? raw.taxPercentage) ??
      DEFAULT_RIDER_TAX_PERCENTAGE,
  };
}

function _writeUserOrdersIndex(transaction, db, orderId, order) {
  const heroId = String(order.heroId || "").trim();
  if (heroId) {
    transaction.set(
      db.collection("user_orders").doc(heroId).collection("orders").doc(orderId),
      {...order, role: "buyer"},
    );
  }

  const sellerIds = Array.isArray(order.sellerHeroIds) ? order.sellerHeroIds : [];
  for (const rawSellerId of sellerIds) {
    const sellerId = String(rawSellerId || "").trim();
    if (!sellerId) continue;
    transaction.set(
      db.collection("user_orders").doc(sellerId).collection("orders").doc(orderId),
      {...order, role: "seller"},
    );
  }
}

async function _prepareOrderForCreate({transaction, db, rawOrder, orderId, heroId}) {
  const order = _normalizeOrderForCreate(rawOrder, orderId, heroId);
  if (isPendingPaymentOrder(order.status)) {
    return {order, offerUpdates: []};
  }

  const aggregatedItems = aggregateOrderItems(order.items);
  const offerDocs = [];
  for (const item of aggregatedItems) {
    offerDocs.push(await transaction.get(db.collection("offers").doc(item.offerId)));
  }

  const offerPricesById = new Map();
  const offerUpdates = [];
  for (let idx = 0; idx < aggregatedItems.length; idx++) {
    const item = aggregatedItems[idx];
    const offerDoc = offerDocs[idx];
    if (!offerDoc.exists) {
      throw new HttpsError("not-found", `Oferta no encontrada: ${item.offerId}`);
    }

    const offer = offerDoc.data() || {};
    offerPricesById.set(item.offerId, toInt(offer.price ?? 0));

    const currentQty = Number(offer.availableQty ?? offer.stock ?? 0);
    if (!Number.isFinite(currentQty)) {
      throw new HttpsError(
        "failed-precondition",
        `Stock invalido para la oferta ${item.offerId}`,
      );
    }

    const newQty = Math.round(currentQty) - item.qty;
    if (newQty < 0) {
      throw new HttpsError(
        "failed-precondition",
        `Stock insuficiente para la oferta ${item.offerId}`,
      );
    }

    const updateData = {
      stock: newQty,
      availableQty: newQty,
      orderCount: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (newQty === 0) updateData.status = "sold_out";

    offerUpdates.push({ref: offerDoc.ref, updateData});
  }

  const serverSubtotal = aggregatedItems.reduce((sum, item) => {
    return sum + (Math.max(0, toInt(offerPricesById.get(item.offerId))) * item.qty);
  }, 0);
  const discountBase = Math.max(
    0,
    serverSubtotal + toInt(order.deliveryFee) + toInt(order.serviceFee) + toInt(order.tax),
  );
  const couponResult = await readCouponDiscount({
    transaction,
    db,
    source: order.coupon,
    discountBase,
  });

  return {
    order: computeServerOrderMoney(order, offerPricesById, couponResult),
    offerUpdates,
  };
}

async function _resolveCallableAuth(request) {
  if (request.auth && request.auth.uid) return request.auth;

  const idToken = String(request.data?.authIdToken || "").trim();
  if (!idToken) {
    throw new HttpsError("unauthenticated", "Usuario no autenticado");
  }

  try {
    const decoded = await admin.auth().verifyIdToken(idToken, true);
    return {uid: decoded.uid, token: decoded};
  } catch (error) {
    console.error("[orders] Invalid fallback auth token", error);
    throw new HttpsError("unauthenticated", "Usuario no autenticado");
  }
}

exports.createOrder = onCall({memory: "512MiB"}, async (request) => {
  const auth = await _resolveCallableAuth(request);

  const db = admin.firestore();
  const rawOrder = request.data && typeof request.data === "object" ? request.data : {};
  const heroId = String(rawOrder.heroId || "").trim();
  if (!heroId || heroId !== auth.uid) {
    throw new HttpsError(
      "permission-denied",
      "El pedido debe pertenecer al usuario autenticado",
    );
  }

  let createdOrder = null;

  await db.runTransaction(async (transaction) => {
    const requestedOrderId = String(rawOrder.orderId || "").trim();
    const orderRef = requestedOrderId ?
      db.collection("orders").doc(requestedOrderId) :
      db.collection("orders").doc();
    const orderId = orderRef.id;
    const existing = await transaction.get(orderRef);

    if (existing.exists) {
      const existingOrder = existing.data() || {};
      if (String(existingOrder.heroId || "").trim() !== heroId) {
        throw new HttpsError(
          "permission-denied",
          "No tienes permiso para usar este pedido",
        );
      }
      createdOrder = {...existingOrder, orderId};
      return;
    }

    if (!isDevCheckoutBypassEnabled()) {
      await assertHeroWeeklyOrderLimit({
        transaction,
        db,
        heroId,
        excludingOrderId: orderId,
      });
    }

    const prepared = await _prepareOrderForCreate({
      transaction,
      db,
      rawOrder,
      orderId,
      heroId,
    });
    createdOrder = prepared.order;
    for (const update of prepared.offerUpdates) {
      transaction.update(update.ref, update.updateData);
    }
    transaction.set(orderRef, createdOrder);
    _writeUserOrdersIndex(transaction, db, orderId, createdOrder);
  });

  return createdOrder;
});

/**
 * Asigna un pedido a un rider de forma segura
 * Valida: rider verificado, compatibilidad de vehículo, estado del pedido
 *
 * @param {Object} data - { orderId: string }
 * @param {Object} context - Firebase auth context
 * @returns {Promise<Object>} - { success: boolean, orderId: string, message: string }
 */
exports.claimOrder = onCall({invoker: "public"}, async (request) => {
  // ==========================================
  // 1. VALIDAR AUTENTICACIÓN
  // ==========================================
  const auth = await _resolveCallableAuth(request);

  const riderId = auth.uid;
  const orderId = request.data.orderId;

  if (!orderId) {
    throw new HttpsError("invalid-argument", "orderId es requerido");
  }

  console.log(
    `[claimOrder] Rider ${riderId} intentando tomar pedido ${orderId}`,
  );

  // ==========================================
  // 2. OBTENER PERFIL DEL RIDER
  // ==========================================
  const riderDoc = await admin
    .firestore()
    .collection("users")
    .doc(riderId)
    .get();

  if (!riderDoc.exists) {
    throw new HttpsError("not-found", "Rider no encontrado");
  }

  const riderData = riderDoc.data() || {};
  const devCheckoutBypass = isDevCheckoutBypassEnabled();
  const riderProfile =
    riderData.riderProfile && typeof riderData.riderProfile === 'object' ?
      riderData.riderProfile :
      null;
  const identity =
    riderData.identity && typeof riderData.identity === 'object' ?
      riderData.identity :
      {};
  const contact =
    riderData.contact && typeof riderData.contact === 'object' ?
      riderData.contact :
      {};
  const normalizeVehicleType = (value) => {
    const raw = String(value || "").trim().toLowerCase();
    return ["bicycle", "motorcycle", "car", "truck"].includes(raw) ?
      raw :
      null;
  };

  // Validar que el usuario tenga rol de rider
  if (!riderData.roles || !riderData.roles.includes("rider")) {
    throw new HttpsError("permission-denied", "No tienes permisos de rider");
  }

  // ==========================================
  // 3. VALIDAR RIDER VERIFICADO (CRÍTICO)
  // ==========================================
  if (!devCheckoutBypass && !riderProfile) {
    throw new HttpsError(
      "failed-precondition",
      "Debes completar tu perfil de rider",
    );
  }

  if (!devCheckoutBypass && !riderProfile.isActive) {
    throw new HttpsError("failed-precondition", "Tu cuenta no está activa");
  }

  const rutStatus = String(riderData?.rutVerification?.status || "").trim().toLowerCase();
  if (
    !devCheckoutBypass &&
    rutStatus !== "approved" &&
    rutStatus !== "not_required"
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Debes verificar tu RUT para tomar pedidos",
    );
  }

  const activeVehicleType = devCheckoutBypass ?
    'truck' :
    (normalizeVehicleType(riderProfile?.activeVehicleType) ||
      normalizeVehicleType(riderProfile?.vehicle?.type) ||
      'bicycle');
  const vehicles =
    riderProfile?.vehicles && typeof riderProfile.vehicles === 'object' ?
      riderProfile.vehicles :
      {};
  const activeVehicleEntry =
    vehicles[activeVehicleType] && typeof vehicles[activeVehicleType] === "object" ?
      vehicles[activeVehicleType] :
      {};
  const activeVehicle =
    activeVehicleEntry.vehicle && typeof activeVehicleEntry.vehicle === "object" ?
      activeVehicleEntry.vehicle :
      {};
  const activeVerification =
    activeVehicleEntry.verification && typeof activeVehicleEntry.verification === "object" ?
      activeVehicleEntry.verification :
      {};
  const activeVerificationStatus = String(activeVerification.status || "").trim().toLowerCase();
  const activeVehicleVerified =
    activeVerificationStatus === "approved" ||
    activeVerificationStatus === "not_required" ||
    (riderProfile?.isVerified === true && activeVerificationStatus === "");

  if (!devCheckoutBypass && !activeVehicleVerified) {
    throw new HttpsError(
      "failed-precondition",
      "Tu vehiculo activo no esta verificado para aceptar este pedido",
    );
  }

  console.log(`[claimOrder] Rider verificado: ${identity.firstName || riderId}`);

  // ==========================================
  // 4. TRANSACCIÓN ATÓMICA
  // ==========================================
  const orderRef = admin.firestore().collection("orders").doc(orderId);

  return admin.firestore().runTransaction(async (transaction) => {
    const orderDoc = await transaction.get(orderRef);

    if (!orderDoc.exists) {
      throw new HttpsError('not-found', 'Pedido no encontrado');
    }

    const order = orderDoc.data();

    // Validar estado
    if (order.status !== 'queued') {
      throw new HttpsError(
        'failed-precondition',
        `Pedido ya no está disponible (estado: ${order.status})`,
      );
    }

    if (order.rider && order.rider.assignedRiderId) {
      throw new HttpsError('failed-precondition', 'Pedido ya tiene rider asignado');
    }

    const orderCountry = String(order.countryCode || "").trim().toUpperCase();
    const riderCountry = _countryCodeFromUser(riderData);
    if (!orderCountry || !riderCountry || orderCountry !== riderCountry) {
      throw new HttpsError(
        "failed-precondition",
        "Este pedido no esta disponible en tu pais",
      );
    }

    // ==========================================
    // 5. VALIDAR COMPATIBILIDAD DE VEHÍCULO
    // ==========================================
    const orderRequirements =
      order.requirements && typeof order.requirements === 'object' ?
        order.requirements :
        {};
    const requiredVehicle = orderRequirements.requiredVehicle;
    const riderVehicle = devCheckoutBypass ?
      'truck' :
      (normalizeVehicleType(activeVehicle.type) ||
        normalizeVehicleType(riderProfile?.vehicle?.type) ||
        activeVehicleType);
    const compatibleVehicles = getCompatibleVehicles(riderVehicle);

    if (!devCheckoutBypass && !compatibleVehicles.includes(requiredVehicle)) {
      throw new HttpsError(
        'failed-precondition',
        `Tu vehículo (${riderVehicle}) no es compatible con este pedido (requiere ${requiredVehicle})`,
      );
    }

    const riderLimits = devCheckoutBypass ?
      null :
      (activeVehicleEntry.limits && typeof activeVehicleEntry.limits === 'object' ?
        activeVehicleEntry.limits :
        riderProfile?.limits);

    if (riderLimits && riderLimits.maxWeightKg) {
      if (orderRequirements.weightKg > riderLimits.maxWeightKg) {
        throw new HttpsError(
          'failed-precondition',
          `El peso del pedido excede tu capacidad`,
        );
      }
    }

    if (riderLimits && riderLimits.maxDistanceKm) {
      if (orderRequirements.estimatedDistanceKm > riderLimits.maxDistanceKm) {
        throw new HttpsError(
          'failed-precondition',
          `La distancia del pedido excede tu rango`,
        );
      }
    }

    // ==========================================
    // 5b. VALIDAR SALDO PARA PEDIDO EN EFECTIVO
    // ==========================================
    const paymentRef = admin.firestore().collection('payments').doc(`cash-${orderId}`);
    const paymentSnap = await transaction.get(paymentRef);

    const isCashOrder = paymentSnap.exists && (() => {
      const pd = paymentSnap.data() || {};
      const methodId = (pd.paymentMethodId || '').toLowerCase();
      const statusDetail = (pd.statusDetail || '').toLowerCase();
      const method = (pd.paymentMethod || '').toLowerCase();
      return methodId === 'cash' || statusDetail === 'cash_on_delivery' ||
             statusDetail === 'cash_collected' || method === 'cash';
    })();

    const riderRef = admin.firestore().collection('users').doc(riderId);
    const riderSnap = await transaction.get(riderRef);
    const walletData = (riderSnap.exists && riderSnap.data()?.riderWallet) || {};

    let cashAmountToCollect = 0;

    if (isCashOrder && !devCheckoutBypass) {
      const total = typeof order.amountTotal === 'number' ? order.amountTotal : 0;
      cashAmountToCollect = Math.max(0, total); // incluye propina — el rider cobra el total completo

      // Saldo disponible = earningsBalance - cashOnHold (ya retenido por otros pedidos)
      const earningsBalanceCents = typeof walletData.earningsBalanceCents === 'number'
        ? walletData.earningsBalanceCents
        : _toCents(walletData.earningsBalance ?? 0);
      const cashOnHoldCents = typeof walletData.cashOnHoldCents === 'number'
        ? walletData.cashOnHoldCents
        : _toCents(walletData.cashOnHold ?? 0);

      const availableCents = Math.max(0, earningsBalanceCents - cashOnHoldCents);
      const requiredCents = _toCents(cashAmountToCollect);

      if (availableCents < requiredCents) {
        const available = (availableCents / 100).toFixed(0);
        const required = cashAmountToCollect.toFixed(0);
        throw new HttpsError(
          'failed-precondition',
          `Saldo insuficiente para pedido en efectivo. Necesitas $${required} CLP disponibles, tienes $${available} CLP.`,
        );
      }
    }

    // ==========================================
    // 6. ASIGNAR PEDIDO
    // ==========================================
    const now = admin.firestore.FieldValue.serverTimestamp();

    const orderUpdate = {
      status: 'assigned',
      'rider.assignedRiderId': riderId,
      'rider.assignedAt': now,
      'rider.vehicleTypeSnapshot': riderVehicle,
      'rider.riderNameSnapshot':
        `${identity.firstName || 'Rider'} ${identity.lastName || ''}`.trim(),
      'rider.riderPhoneSnapshot': contact.phoneNumber || '',
      'timestamps.assignedAt': now,
      updatedAt: now,
    };

    if (isCashOrder && cashAmountToCollect > 0) {
      orderUpdate['rider.cashHoldAmount'] = cashAmountToCollect;

      const holdCents = _toCents(cashAmountToCollect);
      transaction.update(riderRef, {
        'riderWallet.cashOnHold': admin.firestore.FieldValue.increment(cashAmountToCollect),
        'riderWallet.cashOnHoldCents': admin.firestore.FieldValue.increment(holdCents),
      });

      const holdTxRef = riderRef.collection('riderWalletTransactions').doc();
      transaction.set(holdTxRef, {
        type: 'cash_hold',
        orderId,
        amount: cashAmountToCollect,
        amountCents: holdCents,
        currency: order.currency || 'CLP',
        createdAt: now,
      });
    }

    transaction.update(orderRef, orderUpdate);

    return {
      success: true,
      orderId: orderId,
      message: 'Pedido asignado exitosamente',
    };
  });
});

/**
 * Helper: Obtiene vehículos compatibles según el tipo de vehículo del rider
 *
 * Lógica:
 * - Camión puede tomar: bicycle, motorcycle, car, truck (todos)
 * - Auto puede tomar: bicycle, motorcycle, car
 * - Moto puede tomar: bicycle, motorcycle
 * - Bicicleta puede tomar: bicycle
 *
 * @param {string} riderVehicleType - Tipo de vehículo del rider
 * @returns {string[]} - Array de tipos de vehículos compatibles
 */
function getCompatibleVehicles(riderVehicleType) {
  switch (riderVehicleType) {
    case "bicycle":
      return ["bicycle"];
    case "motorcycle":
      return ["bicycle", "motorcycle"];
    case "car":
      return ["bicycle", "motorcycle", "car"];
    case "truck":
      return ["bicycle", "motorcycle", "car", "truck"];
    default:
      console.warn(
        `[getCompatibleVehicles] Tipo de vehículo desconocido: ${riderVehicleType}`,
      );
      return [];
  }
}

/**
 * Función para actualizar el estado de un pedido
 * Solo el rider asignado puede actualizar el estado
 *
 * @param {Object} data - { orderId: string, newStatus: string }
 * @param {Object} context - Firebase auth context
 */
async function _updateOrderStatusForRider({
  orderId,
  newStatus,
  riderId,
  riderServiceFeeCLP,
  riderTaxPercentage,
}) {
  const db = admin.firestore();
  const orderRef = db.collection("orders").doc(orderId);

  await db.runTransaction(async (transaction) => {
    const orderDoc = await transaction.get(orderRef);
    if (!orderDoc.exists) {
      throw new HttpsError("not-found", "Pedido no encontrado");
    }

    const order = orderDoc.data() || {};
    const sellerIds = Array.isArray(order.sellerHeroIds) ?
      order.sellerHeroIds.map((value) => String(value || "").trim()) :
      [];
    const isAssignedRider =
      Boolean(order.rider) && order.rider.assignedRiderId === riderId;
    const isInPersonSeller =
      order.inPersonPickup === true && sellerIds.includes(riderId);

    if (!isAssignedRider && !isInPersonSeller) {
      throw new HttpsError(
        "permission-denied",
        "No tienes permiso para actualizar este pedido",
      );
    }

    const validTransitions = isAssignedRider ? {
      assigned: ["picked_up"],
      picked_up: ["in_transit"],
      in_transit: ["delivered"],
    } : {
      paid: ["picked_up"],
      queued: ["picked_up"],
      assigned: ["picked_up"],
      picked_up: ["delivered"],
      in_transit: ["delivered"],
    };

    if (
      !validTransitions[order.status] ||
      !validTransitions[order.status].includes(newStatus)
    ) {
      throw new HttpsError(
        "failed-precondition",
        `No se puede cambiar de ${order.status} a ${newStatus}`,
      );
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const updates = {
      status: newStatus,
      updatedAt: now,
    };

    if (newStatus === "picked_up") {
      updates["timestamps.pickedUpAt"] = now;
    } else if (newStatus === "in_transit") {
      updates["timestamps.inTransitAt"] = now;
    } else if (newStatus === "delivered") {
      updates["timestamps.deliveredAt"] = now;
    }

    if (
      isAssignedRider &&
      newStatus === "delivered" &&
      order.riderEarningsProcessed !== true
    ) {
      const deliveryFee = Number(order.deliveryFee || 0);
      const tip = Number(order.tip || 0);
      const earnings = _calculateRiderCommission({
        deliveryFee,
        serviceFeeCLP: riderServiceFeeCLP,
        taxPercentage: riderTaxPercentage,
      });
      const riderRef = db.collection("users").doc(riderId);
      const riderSnap = await transaction.get(riderRef);
      if (!riderSnap.exists) {
        throw new HttpsError("not-found", "Rider no encontrado");
      }

      const riderData = riderSnap.data() || {};
      const wallet =
        riderData.riderWallet && typeof riderData.riderWallet === "object" ?
          riderData.riderWallet :
          {};
      const cashBalance = Number(wallet.cashBalance || 0);
      const cashOnHold = Number(wallet.cashOnHold || 0);
      const cashHoldAmount = Number(order.rider?.cashHoldAmount || 0);
      const isCashOrder = Number.isFinite(cashHoldAmount) && cashHoldAmount > 0;
      const txCollection = riderRef.collection("riderWalletTransactions");

      if (!isCashOrder) {
        const earningsAmount = earnings.netEarnings + tip;
        const earningsCents = _toCents(earningsAmount) || 0;
        const earningsTxRef = txCollection.doc();

        transaction.set(earningsTxRef, {
          type: "delivery_earnings",
          orderId,
          amount: earningsAmount,
          amountCents: earningsCents,
          currency: order.currency || "CLP",
          createdAt: now,
          meta: {
            deliveryFee,
            tip,
            tipCents: _toCents(tip) || 0,
            breakdown: earnings.breakdown,
            isCashOrder: false,
          },
        });

        transaction.update(riderRef, {
          "riderWallet.earningsBalance":
            admin.firestore.FieldValue.increment(earningsAmount),
          "riderWallet.earningsBalanceCents":
            admin.firestore.FieldValue.increment(earningsCents),
          "riderWallet.totalEarnings":
            admin.firestore.FieldValue.increment(earningsAmount),
          "riderWallet.totalEarningsCents":
            admin.firestore.FieldValue.increment(earningsCents),
        });
      } else if (order.cashSettlementProcessed !== true) {
        const cashAmount = cashHoldAmount;
        const cashCents = _toCents(cashAmount) || 0;
        const settlementTxRef = txCollection.doc();

        transaction.set(settlementTxRef, {
          type: "cash_settlement",
          orderId,
          amount: -cashAmount,
          amountCents: -cashCents,
          currency: order.currency || "CLP",
          createdAt: now,
          meta: {
            deliveryFee,
            netEarnings: earnings.netEarnings,
            isCashOrder: true,
          },
        });

        transaction.update(riderRef, {
          "riderWallet.cashOnHold":
            admin.firestore.FieldValue.increment(-cashAmount),
          "riderWallet.cashOnHoldCents":
            admin.firestore.FieldValue.increment(-cashCents),
          "riderWallet.earningsBalance":
            admin.firestore.FieldValue.increment(-cashAmount),
          "riderWallet.earningsBalanceCents":
            admin.firestore.FieldValue.increment(-cashCents),
          "riderWallet.totalEarnings":
            admin.firestore.FieldValue.increment(earnings.netEarnings),
          "riderWallet.totalEarningsCents":
            admin.firestore.FieldValue.increment(_toCents(earnings.netEarnings) || 0),
        });

        updates.cashSettlementProcessed = true;
      }

      updates.riderEarningsProcessed = true;
      updates.riderEarningsProcessedAt = now;
      updates.riderEarningsSnapshot = {
        deliveryFee,
        tip,
        netEarnings: earnings.netEarnings,
        serviceFee: earnings.serviceFee,
        taxDeduction: earnings.taxDeduction,
      };

      if (isCashOrder) {
        updates.riderCashSnapshot = {
          cashBalanceBefore: cashBalance,
          cashOnHoldBefore: cashOnHold,
        };
      }
    }

    transaction.update(orderRef, updates);
  });
}

exports.updateOrderStatus = onCall(async (request) => {
  const auth = await _resolveCallableAuth(request);

  const { orderId, newStatus } = request.data;
  const riderId = auth.uid;

  if (!orderId || !newStatus) {
    throw new HttpsError(
      "invalid-argument",
      "orderId y newStatus son requeridos",
    );
  }

  // Estados válidos para actualización por rider
  const validStatuses = ["picked_up", "in_transit", "delivered"];
  if (!validStatuses.includes(newStatus)) {
    throw new HttpsError(
      "invalid-argument",
      `Estado inválido. Debe ser uno de: ${validStatuses.join(", ")}`,
    );
  }

  const riderCommission = await _getRiderCommissionConfig(admin.firestore());

  await _updateOrderStatusForRider({
    orderId,
    newStatus,
    riderId,
    ...riderCommission,
  });

  console.log(
    `[updateOrderStatus] Pedido ${orderId} actualizado a ${newStatus}`,
  );

  return {
    success: true,
    orderId: orderId,
    newStatus: newStatus,
    message: `Pedido actualizado a ${newStatus}`,
  };

  const orderRef = admin.firestore().collection("orders").doc(orderId);
  const orderDoc = await orderRef.get();

  if (!orderDoc.exists) {
    throw new HttpsError("not-found", "Pedido no encontrado");
  }

  const order = orderDoc.data();

  // Validar que el rider sea el asignado
  if (!order.rider || order.rider.assignedRiderId !== riderId) {
    throw new HttpsError(
      "permission-denied",
      "No tienes permiso para actualizar este pedido",
    );
  }

  // Validar transición de estado
  const validTransitions = {
    assigned: ["picked_up"],
    picked_up: ["in_transit"],
    in_transit: ["delivered"],
  };

  if (
    !validTransitions[order.status] ||
    !validTransitions[order.status].includes(newStatus)
  ) {
    throw new HttpsError(
      "failed-precondition",
      `No se puede cambiar de ${order.status} a ${newStatus}`,
    );
  }

  // Actualizar estado
  const now = admin.firestore.FieldValue.serverTimestamp();
  const updates = {
    status: newStatus,
    updatedAt: now,
  };

  // Actualizar timestamp específico
  if (newStatus === "picked_up") {
    updates["timestamps.pickedUpAt"] = now;
  } else if (newStatus === "in_transit") {
    updates["timestamps.inTransitAt"] = now;
  } else if (newStatus === "delivered") {
    updates["timestamps.deliveredAt"] = now;
  }

  await orderRef.update(updates);

  console.log(
    `[updateOrderStatus] Pedido ${orderId} actualizado a ${newStatus}`,
  );

  return {
    success: true,
    orderId: orderId,
    newStatus: newStatus,
    message: `Pedido actualizado a ${newStatus}`,
  };
});

function _normalizeOrderStatusForCancel(value) {
  return String(value || "").trim().toLowerCase().replace(/[_-]/g, "");
}

function _isUnpaidCancelableStatus(value) {
  const status = _normalizeOrderStatusForCancel(value);
  return status === "created" || status === "pendingpayment";
}

function _isApprovedPaymentDoc(data) {
  return _normalizeOrderStatusForCancel(data?.status) === "approved" ||
    Boolean(data?.approvedAt);
}

function _qtyIntForCancel(value) {
  const parsed = Number(value ?? 1);
  if (!Number.isFinite(parsed)) return 1;
  const rounded = Math.round(parsed);
  return rounded > 0 ? rounded : 1;
}

async function _readPaymentDocsForOrder(transaction, db, orderIds) {
  const ids = [...new Set(orderIds
    .map((value) => String(value || "").trim())
    .filter(Boolean))].slice(0, 10);
  if (ids.length === 0) return [];

  const query = ids.length === 1 ?
    db.collection("payments").where("orderId", "==", ids[0]) :
    db.collection("payments").where("orderId", "in", ids);
  const snap = await transaction.get(query);
  return snap.docs.map((doc) => doc.data() || {});
}

exports.cancelOrder = onCall(async (request) => {
  const auth = await _resolveCallableAuth(request);

  const orderId = String(request.data?.orderId || "").trim();
  const reason = String(request.data?.reason || "Cancelado por el usuario")
    .trim();
  const canceledBy = String(request.data?.canceledBy || auth.uid)
    .trim();

  if (!orderId) {
    throw new HttpsError("invalid-argument", "orderId es requerido");
  }

  const db = admin.firestore();
  const orderRef = db.collection("orders").doc(orderId);
  const result = {
    success: false,
    alreadyCanceled: false,
  };

  await db.runTransaction(async (transaction) => {
    const orderDoc = await transaction.get(orderRef);
    if (!orderDoc.exists) {
      throw new HttpsError("not-found", "Pedido no encontrado");
    }

    const order = orderDoc.data() || {};
    if (String(order.heroId || "") !== auth.uid) {
      throw new HttpsError(
        "permission-denied",
        "No tienes permiso para cancelar este pedido",
      );
    }

    const currentStatus = String(order.status || "");
    if (_normalizeOrderStatusForCancel(currentStatus) === "canceled") {
      result.success = true;
      result.alreadyCanceled = true;
      return;
    }

    if (!_isUnpaidCancelableStatus(currentStatus)) {
      throw new HttpsError(
        "failed-precondition",
        "No se puede cancelar un pedido que ya fue pagado",
      );
    }

    const paymentDocs = await _readPaymentDocsForOrder(transaction, db, [
      orderId,
      order.orderId,
    ]);
    if (paymentDocs.some(_isApprovedPaymentDoc)) {
      throw new HttpsError(
        "failed-precondition",
        "No se puede cancelar un pedido con pago aprobado",
      );
    }

    const reservationRef = db.collection("stockReservations").doc(orderId);
    const reservationDoc = await transaction.get(reservationRef);
    const alreadyRestored = order.stockRestored === true;
    const offerQtyDeltas = new Map();
    let shouldReleaseReservation = false;

    if (!alreadyRestored && reservationDoc.exists) {
      const reservation = reservationDoc.data() || {};
      if (reservation.status === "consumed") {
        throw new HttpsError(
          "failed-precondition",
          "No se puede cancelar un pedido con pago aprobado",
        );
      }
      if (reservation.status === "reserved") {
        shouldReleaseReservation = true;
        const items = Array.isArray(reservation.items) ? reservation.items : [];
        for (const item of items) {
          const offerId = String(item?.offerId || "").trim();
          if (!offerId) continue;
          offerQtyDeltas.set(
            offerId,
            (offerQtyDeltas.get(offerId) || 0) + _qtyIntForCancel(item?.qty),
          );
        }
      }
    }

    if (!alreadyRestored && !shouldReleaseReservation) {
      const items = Array.isArray(order.items) ? order.items : [];
      for (const item of items) {
        const offerId = String(item?.offerId || "").trim();
        if (!offerId) continue;
        offerQtyDeltas.set(
          offerId,
          (offerQtyDeltas.get(offerId) || 0) + _qtyIntForCancel(item?.qty),
        );
      }
    }

    const offerDocs = new Map();
    for (const [offerId] of offerQtyDeltas) {
      const offerRef = db.collection("offers").doc(offerId);
      const offerDoc = await transaction.get(offerRef);
      offerDocs.set(offerId, {ref: offerRef, doc: offerDoc});
    }

    for (const [offerId, delta] of offerQtyDeltas) {
      const entry = offerDocs.get(offerId);
      if (!entry?.doc?.exists) continue;

      const offer = entry.doc.data() || {};
      const currentQty = Number(offer.availableQty ?? 0);
      const restoredQty = currentQty + delta;
      const updateData = {
        stock: restoredQty,
        availableQty: restoredQty,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (offer.status === "sold_out" && restoredQty > 0) {
        updateData.status = "active";
      }
      transaction.update(entry.ref, updateData);
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    if (shouldReleaseReservation) {
      transaction.update(reservationRef, {
        status: "released",
        releasedAt: now,
        releasedBy: "cancelOrder",
        releasedReason: "user_canceled_unpaid_order",
      });
    }

    const cancelPayload = {
      status: "canceled",
      cancelReason: reason || "Cancelado por el usuario",
      canceledBy: canceledBy || auth.uid,
      "timestamps.canceledAt": now,
      stockRestored: true,
      stockRestoredAt: now,
      updatedAt: now,
    };

    transaction.update(orderRef, cancelPayload);

    const heroId = String(order.heroId || "").trim();
    if (heroId) {
      transaction.set(
        db.collection("user_orders").doc(heroId).collection("orders").doc(orderId),
        cancelPayload,
        {merge: true},
      );
    }

    const sellerIds = Array.isArray(order.sellerHeroIds) ?
      order.sellerHeroIds :
      [];
    for (const rawSellerId of sellerIds) {
      const sellerId = String(rawSellerId || "").trim();
      if (!sellerId) continue;
      transaction.set(
        db.collection("user_orders").doc(sellerId).collection("orders").doc(orderId),
        cancelPayload,
        {merge: true},
      );
    }

    result.success = true;
  });

  return result;
});


