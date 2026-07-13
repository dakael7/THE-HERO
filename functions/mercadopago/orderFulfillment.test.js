/* eslint-disable require-jsdoc */
const assert = require('node:assert/strict');
const test = require('node:test');
const {
  resolveApprovedOrderFulfillment,
} = require('./orderFulfillment');

class FakeSnapshot {
  constructor(data) {
    this._data = data;
    this.exists = data !== undefined;
  }

  data() {
    return this._data;
  }
}

class FakeRef {
  constructor(store, collection, id) {
    this._store = store;
    this.collection = collection;
    this.id = id;
  }

  get key() {
    return `${this.collection}/${this.id}`;
  }
}

class FakeTransaction {
  constructor(store) {
    this._store = store;
  }

  async get(ref) {
    return new FakeSnapshot(this._store.get(ref.key));
  }

  update(ref, data) {
    const current = this._store.get(ref.key) || {};
    this._store.set(ref.key, {...current, ...data});
  }

  set(ref, data, options) {
    const current = options?.merge ? this._store.get(ref.key) || {} : {};
    this._store.set(ref.key, {...current, ...data});
  }
}

class FakeDb {
  constructor(seed) {
    this.store = new Map(Object.entries(seed));
  }

  collection(name) {
    return {
      doc: (id) => new FakeRef(this.store, name, id),
    };
  }

  async runTransaction(callback) {
    return callback(new FakeTransaction(this.store));
  }

  get(path) {
    return this.store.get(path);
  }
}

test('consumes an existing reserved stock reservation', async () => {
  const db = new FakeDb({
    'stockReservations/order-1': {
      status: 'reserved',
      items: [{offerId: 'offer-1', qty: 2}],
    },
    'offers/offer-1': {availableQty: 5, stock: 5, orderCount: 2},
  });

  const result = await resolveApprovedOrderFulfillment({
    db,
    orderId: 'order-1',
    orderData: {items: [{offerId: 'offer-1', qty: 2}]},
    reservationRef: db.collection('stockReservations').doc('order-1'),
    paymentId: 'pay-1',
  });

  assert.equal(result.canFulfill, true);
  assert.equal(result.recoveryStatus, 'reserved_consumed');
  assert.equal(db.get('stockReservations/order-1').status, 'consumed');
  assert.equal(db.get('offers/offer-1').availableQty, 5);
  assert.equal(db.get('offers/offer-1').orderCount, 3);
});

test('recovers a released reservation when stock is still available', async () => {
  const db = new FakeDb({
    'stockReservations/order-1': {status: 'released'},
    'offers/offer-1': {availableQty: 3, stock: 3, orderCount: 0},
  });

  const result = await resolveApprovedOrderFulfillment({
    db,
    orderId: 'order-1',
    orderData: {
      heroId: 'hero-1',
      items: [
        {offerId: 'offer-1', qty: 1},
        {offerId: 'offer-1', qty: 1},
      ],
    },
    reservationRef: db.collection('stockReservations').doc('order-1'),
    paymentId: 'pay-1',
  });

  const reservation = db.get('stockReservations/order-1');

  assert.equal(result.canFulfill, true);
  assert.equal(result.recoveryStatus, 'stock_recovered');
  assert.equal(db.get('offers/offer-1').availableQty, 1);
  assert.equal(db.get('offers/offer-1').orderCount, 1);
  assert.equal(reservation.status, 'consumed');
  assert.deepEqual(reservation.items, [{offerId: 'offer-1', qty: 2}]);
});

test('blocks fulfillment when released stock is no longer available', async () => {
  const db = new FakeDb({
    'stockReservations/order-1': {status: 'released'},
    'offers/offer-1': {availableQty: 1, stock: 1},
  });

  const result = await resolveApprovedOrderFulfillment({
    db,
    orderId: 'order-1',
    orderData: {items: [{offerId: 'offer-1', qty: 2}]},
    reservationRef: db.collection('stockReservations').doc('order-1'),
    paymentId: 'pay-1',
  });

  assert.equal(result.canFulfill, false);
  assert.equal(result.recoveryStatus, 'blocked');
  assert.equal(result.recoveryReason, 'stock_unavailable:offer-1');
  assert.equal(db.get('offers/offer-1').availableQty, 1);
  assert.equal(db.get('stockReservations/order-1').status, 'released');
});
