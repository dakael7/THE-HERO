function isSupportUser(auth) {
  const allowlistRaw = process.env.SUPPORT_EMAIL_ALLOWLIST || "";
  const allowlist = allowlistRaw
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);

  const email = auth?.token?.email
    ? String(auth.token.email).toLowerCase()
    : null;
  if (email && allowlist.includes(email)) return true;

  if (auth?.token?.support === true) return true;
  if (auth?.token?.admin === true) return true;

  return false;
}

module.exports = {
  isSupportUser,
};
