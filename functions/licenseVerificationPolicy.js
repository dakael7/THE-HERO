function decideLicenseVerificationStatus({
  documentDetected,
  keywordsOk,
  extractedRut,
  strictRutOk,
  dvValid,
  declaredRut,
  matchDeclared,
  extractedName,
  nameMatchOk,
  expiryIso,
  expired,
  licenseClassDetected,
  classOk,
  textureValid,
}) {
  if (expiryIso && expired) return "rejected";
  if (licenseClassDetected && !classOk) return "rejected";

  const matchingRutOk =
    Boolean(declaredRut) &&
    Boolean(extractedRut) &&
    strictRutOk &&
    dvValid &&
    matchDeclared;
  const identityOk = matchingRutOk || nameMatchOk;
  const documentLooksLikeLicense =
    documentDetected &&
    (keywordsOk || Boolean(extractedRut) || Boolean(extractedName));
  const sparseSealedLicenseOk = matchingRutOk && textureValid;

  return identityOk && (documentLooksLikeLicense || sparseSealedLicenseOk)
    ? "approved"
    : "rejected";
}

module.exports = {
  decideLicenseVerificationStatus,
};
