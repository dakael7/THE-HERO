const _truthy = (value) => {
  const normalized = String(value || '').trim().toLowerCase();
  return ['true', '1', 'yes', 'on'].includes(normalized);
};

const isDevCheckoutBypassEnabled = (env = process.env) =>
  _truthy(env.DEV_CHECKOUT_BYPASS);

module.exports = {
  isDevCheckoutBypassEnabled,
};
