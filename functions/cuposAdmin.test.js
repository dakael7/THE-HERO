const assert = require('node:assert/strict');
const test = require('node:test');

const {_test} = require('./adminSupport');

test('admin cupo creation normalizes a 100 percent coupon', () => {
  const built = _test.buildCupoWrite({
    code: ' free100 ',
    active: true,
    discountType: 'percentage',
    discountValue: 100,
  });

  assert.deepEqual(built, {
    data: {
      active: true,
      type: 'percent',
      value: 100,
    },
  });
  assert.equal(_test.normalizeCupoCode(' free100 '), 'FREE100');
});

test('admin cupo update can disable without changing discount', () => {
  const built = _test.buildCupoWrite({active: false}, {
    partial: true,
    current: {type: 'fixed', value: 5000},
  });

  assert.deepEqual(built, {data: {active: false}});
});

test('admin cupo rejects percent values over 100', () => {
  const built = _test.buildCupoWrite({
    active: true,
    type: 'percent',
    value: 101,
  });

  assert.equal(built.error, 'percent value must be <= 100');
});
