const test = require('node:test');
const assert = require('node:assert/strict');
const {
  _buildWasabilPayload,
  _buildWasabilDetails,
  _buildWasabilReceiptDetails,
  _webhookSecret,
} = require('./onOrderPaidCreateInvoice').__test;

/**
 * Builds a minimal paid order for invoice total tests.
 * @param {object} values Tax and total values.
 * @return {object} Order fixture.
 */
function orderWith({tax, total}) {
  return {
    items: [{titleSnapshot: 'Producto', qty: 1, unitPriceSnapshot: 10000}],
    subtotal: 10000,
    deliveryFee: 1000,
    serviceFee: 500,
    tax,
    amountTotal: total,
  };
}

test('marks products exempt when IVA only applies to app fees', () => {
  const details = _buildWasabilDetails(orderWith({tax: 285, total: 11785}));
  assert.equal(details[0].exempt, true);
  assert.equal(details[1].exempt, undefined);
  assert.equal(details[2].exempt, undefined);
});

test('keeps products affected when IVA applies to every line', () => {
  const details = _buildWasabilDetails(orderWith({tax: 2185, total: 13685}));
  assert.equal(details[0].exempt, false);
});

test('rejects totals that Wasabil would emit differently', () => {
  assert.throws(
      () => _buildWasabilDetails(orderWith({tax: 100, total: 11600})),
      /Invoice IVA mismatch/,
  );
});

test('builds a DTE 39 receipt whose details match the paid total', () => {
  const order = {
    ...orderWith({tax: 285, total: 11785}),
    documentType: 'boleta',
    currency: 'CLP',
  };
  const details = _buildWasabilReceiptDetails(order);
  const total = details.reduce(
      (sum, detail) => sum + (detail.price * detail.quantity),
      0,
  );
  const payload = _buildWasabilPayload({order, invoiceId: 'order-1'});

  assert.equal(total, 11785);
  assert.equal(payload.sii_document_type_id, 39);
  assert.equal(payload.receiver_input, 'none');
  assert.equal(payload.price_includes_iva, true);
  assert.equal(payload.invoice_reference, 'order-1');
  assert.equal('document_date' in payload, false);
});

test('accepts raw and Bearer webhook secrets', () => {
  assert.equal(_webhookSecret('secret'), 'secret');
  assert.equal(_webhookSecret('Bearer secret'), 'secret');
});
