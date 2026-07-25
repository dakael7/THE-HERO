const test = require('node:test');
const assert = require('node:assert/strict');

const {isDevCheckoutBypassEnabled} = require('./devMode');

test('DEV_CHECKOUT_BYPASS accepts common truthy values only', () => {
  assert.equal(isDevCheckoutBypassEnabled({DEV_CHECKOUT_BYPASS: 'true'}), true);
  assert.equal(isDevCheckoutBypassEnabled({DEV_CHECKOUT_BYPASS: '1'}), true);
  assert.equal(isDevCheckoutBypassEnabled({DEV_CHECKOUT_BYPASS: 'yes'}), true);
  assert.equal(isDevCheckoutBypassEnabled({DEV_CHECKOUT_BYPASS: 'on'}), true);
  assert.equal(isDevCheckoutBypassEnabled({DEV_CHECKOUT_BYPASS: 'false'}), false);
  assert.equal(isDevCheckoutBypassEnabled({}), false);
});
