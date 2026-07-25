const {HttpsError} = require("firebase-functions/v2/https");

function toInt(value) {
  const n = Number(value);
  return Number.isFinite(n) ? Math.round(n) : 0;
}

function toQtyInt(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 1;
  const q = Math.round(n);
  return q > 0 ? q : 1;
}

function normalizeOrderStatus(value) {
  return String(value || "").trim().toLowerCase().replace(/[_-]/g, "");
}

function isPendingPaymentOrder(value) {
  return normalizeOrderStatus(value) === "pendingpayment";
}

function aggregateOrderItems(rawItems) {
  if (!Array.isArray(rawItems) || rawItems.length === 0) {
    throw new HttpsError("invalid-argument", "El pedido no tiene items");
  }

  const byOffer = new Map();
  for (const item of rawItems) {
    const offerId = String(item?.offerId || "").trim();
    if (!offerId) {
      throw new HttpsError("invalid-argument", "Item sin offerId");
    }

    byOffer.set(offerId, (byOffer.get(offerId) || 0) + toQtyInt(item?.qty));
  }

  return [...byOffer.entries()].map(([offerId, qty]) => ({offerId, qty}));
}

function couponDiscountFromData(code, data, discountBase) {
  if (data.active !== true && data.isActive !== true) {
    throw new HttpsError("failed-precondition", "Cupo inactivo");
  }

  const rawType = String(
    data.type ?? data.discountType ?? data.tipo ?? "",
  ).trim().toLowerCase();
  const type =
    ["percent", "percentage", "porcentual", "porcentaje"].includes(rawType) ?
      "percent" :
      ["fixed", "amount", "fijo", "monto"].includes(rawType) ?
        "fixed" :
        null;
  const value = Number(
    data.value ?? data.discountValue ?? data.amount ?? data.valor ?? 0,
  );
  if (!type || !Number.isFinite(value) || value <= 0) {
    throw new HttpsError("failed-precondition", "Cupo mal configurado");
  }

  const rawAmount = type === "percent" ?
    Math.round(discountBase * Math.min(value, 100) / 100) :
    Math.round(value);
  const amount = Math.min(Math.max(0, rawAmount), Math.max(0, discountBase));
  return {amount, coupon: {code, type, value, discountAmount: amount}};
}

async function readCouponDiscount({transaction, db, source, discountBase}) {
  const code = String(source?.code ?? "").trim().toUpperCase();
  if (!code) return {amount: 0, coupon: null};

  const couponDoc = await transaction.get(db.collection("cupos").doc(code));
  if (!couponDoc.exists) {
    throw new HttpsError("not-found", "Cupo no encontrado");
  }

  return couponDiscountFromData(code, couponDoc.data() || {}, discountBase);
}

function computeServerOrderMoney(order, offerPricesById, couponResult) {
  const items = Array.isArray(order.items) ? order.items : [];
  let subtotal = 0;
  const pricedItems = items.map((item) => {
    const offerId = String(item?.offerId || "").trim();
    const qty = toQtyInt(item?.qty);
    const unitPrice = Math.max(
      0,
      toInt(offerPricesById.get(offerId) ?? item?.unitPriceSnapshot),
    );
    subtotal += unitPrice * qty;
    return {...item, offerId, qty, unitPriceSnapshot: unitPrice};
  });

  const deliveryFee = Math.max(0, toInt(order.deliveryFee));
  const serviceFee = Math.max(0, toInt(order.serviceFee));
  const tax = Math.max(0, toInt(order.tax));
  const tip = Math.max(0, toInt(order.tip));
  const discount = Math.max(0, toInt(couponResult?.amount));
  const amountTotal = Math.max(
    0,
    toInt(subtotal + deliveryFee + serviceFee + tax + tip - discount),
  );

  const next = {
    ...order,
    items: pricedItems,
    subtotal,
    deliveryFee,
    serviceFee,
    tax,
    tip,
    amountTotal,
  };
  if (couponResult?.coupon) {
    next.coupon = couponResult.coupon;
  } else {
    delete next.coupon;
  }
  return next;
}

module.exports = {
  aggregateOrderItems,
  computeServerOrderMoney,
  couponDiscountFromData,
  isPendingPaymentOrder,
  readCouponDiscount,
  toInt,
  toQtyInt,
};
