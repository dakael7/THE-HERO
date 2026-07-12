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
}) {
  if (expiryIso && expired) return "rejected";
  if (licenseClassDetected && !classOk) return "rejected";

  const identityOk = matchDeclared || nameMatchOk;
  const documentLooksLikeLicense =
    documentDetected && (keywordsOk || Boolean(extractedRut) || Boolean(extractedName));

  return identityOk && documentLooksLikeLicense ? "approved" : "rejected";
}

module.exports = {
  decideLicenseVerificationStatus,
};
