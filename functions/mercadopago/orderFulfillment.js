const admin = require('firebase-admin');

const _timestamp = () => admin.firestore.FieldValue.serverTimestamp();

const _toQtyInt = (value) => {
  const n = Number(value);
  if (!Number.isFinite(n)) return 1;
  const q = Math.round(n);
  return q > 0 ? q : 1;
};

const _normalizeStatus = (value) => String(value || '').trim().toLowerCase();

const _aggregateOrderItems = (orderData) => {
  const rawItems = Array.isArray(orderData?.items) ? orderData.items : [];
  const qtyByOfferId = new Map();

  for (const item of rawItems) {
    const offerId = String(item?.offerId ?? item?.id ?? '').trim();
    if (!offerId) continue;

    qtyByOfferId.set(
        offerId,
        (qtyByOfferId.get(offerId) ?? 0) + _toQtyInt(item?.qty ?? item?.quantity),
    );
  }

  return Array.from(qtyByOfferId.entries()).map(([offerId, qty]) => ({
    offerId,
    qty,
  }));
};

const _itemsFromReservationOrOrder = (reservation, orderData) => {
  const reservationItems = Array.isArray(reservation?.items) ?
    reservation.items :
    [];
  if (reservationItems.length > 0) {
    return _aggregateOrderItems({items: reservationItems});
  }
  return _aggregateOrderItems(orderData);
};

const _incrementOrderCounts = async (transaction, db, items) => {
  const offerEntries = [];
  for (const item of items) {
    const offerRef = db.collection('offers').doc(item.offerId);
    const offerDoc = await transaction.get(offerRef);
    offerEntries.push({offerRef, offerDoc});
  }

  for (const entry of offerEntries) {
    if (!entry.offerDoc.exists) continue;

    const data = entry.offerDoc.data() || {};
    const orderCount = Number(data.orderCount ?? 0);
    transaction.update(entry.offerRef, {
      orderCount: (Number.isFinite(orderCount) ? orderCount : 0) + 1,
      updatedAt: _timestamp(),
    });
  }
};

const resolveApprovedOrderFulfillment = async ({
  db,
  orderId,
  orderData,
  reservationRef,
  paymentId,
}) => {
  const result = {
    canFulfill: false,
    reservationExists: false,
    reservationStatus: null,
    recoveryStatus: 'not_attempted',
    recoveryReason: null,
  };

  await db.runTransaction(async (transaction) => {
    const reservationDoc = await transaction.get(reservationRef);
    const reservation = reservationDoc.exists ? (reservationDoc.data() || {}) : {};
    const reservationStatus = _normalizeStatus(reservation.status);

    result.reservationExists = reservationDoc.exists;
    result.reservationStatus = reservationStatus || null;

    if (reservationStatus === 'consumed') {
      result.canFulfill = true;
      result.recoveryStatus = 'already_consumed';
      return;
    }

    if (reservationStatus === 'reserved') {
      const items = _itemsFromReservationOrOrder(reservation, orderData);
      await _incrementOrderCounts(transaction, db, items);

      transaction.update(reservationRef, {
        status: 'consumed',
        consumedAt: _timestamp(),
        paymentId: paymentId || null,
        paymentStatusSnapshot: 'approved',
        orderCountIncremented: true,
        updatedAt: _timestamp(),
      });
      result.canFulfill = true;
      result.recoveryStatus = 'reserved_consumed';
      return;
    }

    if (reservationStatus && reservationStatus !== 'released') {
      result.recoveryStatus = 'blocked';
      result.recoveryReason = `reservation_${reservationStatus}`;
      return;
    }

    const items = _aggregateOrderItems(orderData);
    if (items.length === 0) {
      result.recoveryStatus = 'blocked';
      result.recoveryReason = 'missing_order_items';
      return;
    }

    const offerEntries = [];
    for (const item of items) {
      const offerRef = db.collection('offers').doc(item.offerId);
      const offerDoc = await transaction.get(offerRef);
      offerEntries.push({item, offerRef, offerDoc});
    }

    for (const entry of offerEntries) {
      if (!entry.offerDoc.exists) {
        result.recoveryStatus = 'blocked';
        result.recoveryReason = `offer_missing:${entry.item.offerId}`;
        return;
      }

      const data = entry.offerDoc.data() || {};
      const currentQty = Number(data.availableQty ?? 0);
      if (!Number.isFinite(currentQty)) {
        result.recoveryStatus = 'blocked';
        result.recoveryReason = `invalid_available_qty:${entry.item.offerId}`;
        return;
      }

      if (currentQty - entry.item.qty < 0) {
        result.recoveryStatus = 'blocked';
        result.recoveryReason = `stock_unavailable:${entry.item.offerId}`;
        return;
      }
    }

    for (const entry of offerEntries) {
      const data = entry.offerDoc.data() || {};
      const currentQty = Number(data.availableQty ?? 0);
      const newQty = currentQty - entry.item.qty;
      const orderCount = Number(data.orderCount ?? 0);
      const updateData = {
        stock: newQty,
        availableQty: newQty,
        orderCount: (Number.isFinite(orderCount) ? orderCount : 0) + 1,
        updatedAt: _timestamp(),
      };

      if (newQty === 0) {
        updateData.status = 'sold_out';
      }

      transaction.update(entry.offerRef, updateData);
    }

    const reservationUpdate = {
      orderId: String(orderId || reservationRef.id),
      heroId: String(orderData?.heroId || ''),
      items,
      status: 'consumed',
      recoveryReason: 'approved_payment_without_consumable_reservation',
      recoveredAt: _timestamp(),
      consumedAt: _timestamp(),
      paymentId: paymentId || null,
      paymentStatusSnapshot: 'approved',
      updatedAt: _timestamp(),
    };

    if (!reservationDoc.exists) {
      reservationUpdate.createdAt = _timestamp();
    }

    transaction.set(reservationRef, reservationUpdate, {merge: true});

    result.canFulfill = true;
    result.recoveryStatus = 'stock_recovered';
  });

  return result;
};

module.exports = {
  resolveApprovedOrderFulfillment,
  _aggregateOrderItems,
};
