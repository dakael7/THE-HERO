const DEFAULT_RIDER_SERVICE_FEE_CLP = 0;
const DEFAULT_RIDER_TAX_PERCENTAGE = 0.07;

function toCents(value) {
  const num = Number(value);
  if (!Number.isFinite(num)) return null;
  return Math.round(num * 100);
}

function round2(value) {
  const num = Number(value);
  if (!Number.isFinite(num)) return null;
  return Math.round(num * 100) / 100;
}

function normalizeNonNegativeNumber(value) {
  const num = Number(value);
  if (!Number.isFinite(num) || Number.isNaN(num) || num < 0) return null;
  return num;
}

function calculateRiderCommission({
  deliveryFee,
  serviceFeeCLP = DEFAULT_RIDER_SERVICE_FEE_CLP,
  taxPercentage = DEFAULT_RIDER_TAX_PERCENTAGE,
}) {
  const fee = Math.max(0, Number(deliveryFee) || 0);
  const serviceFeeNum = Number(serviceFeeCLP);
  const taxRateNum = Number(taxPercentage);
  const serviceFee = Number.isFinite(serviceFeeNum) && serviceFeeNum >= 0 ?
    serviceFeeNum :
    DEFAULT_RIDER_SERVICE_FEE_CLP;
  const taxRate = Number.isFinite(taxRateNum) && taxRateNum >= 0 ?
    taxRateNum :
    DEFAULT_RIDER_TAX_PERCENTAGE;
  const netDeliveryFee = Math.max(0, fee - serviceFee);
  const taxDeduction = netDeliveryFee * taxRate;
  const netEarnings = netDeliveryFee - taxDeduction;
  const taxPercent = (taxRate * 100).toFixed(0);

  return {
    deliveryFee: fee,
    serviceFee,
    taxDeduction,
    netEarnings,
    breakdown:
      `Tarifa de envio: $${fee.toFixed(0)}\n` +
      `Comision de servicio: -$${serviceFee.toFixed(0)}\n` +
      `Descuento (${taxPercent}% sobre envio neto): -$${taxDeduction.toFixed(0)}\n` +
      `Ganancia neta: $${netEarnings.toFixed(0)}`,
  };
}

module.exports = {
  DEFAULT_RIDER_SERVICE_FEE_CLP,
  DEFAULT_RIDER_TAX_PERCENTAGE,
  calculateRiderCommission,
  normalizeNonNegativeNumber,
  round2,
  toCents,
};
