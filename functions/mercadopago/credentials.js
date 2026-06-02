const redactMercadoPagoSecrets = (value) => {
  if (value == null) return value;

  if (typeof value === 'string') {
    return value.replace(
      /\b(?:APP_USR|TEST)-[A-Za-z0-9_-]+/g,
      (token) => `${token.slice(0, 8)}...${token.slice(-4)}`,
    );
  }

  try {
    return JSON.parse(redactMercadoPagoSecrets(JSON.stringify(value)));
  } catch (_) {
    return '[unserializable]';
  }
};

const getMercadoPagoAccessToken = () => {
  return String(process.env.MERCADOPAGO_ACCESS_TOKEN || '').trim();
};

module.exports = {
  getMercadoPagoAccessToken,
  redactMercadoPagoSecrets,
};
