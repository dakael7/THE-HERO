const test = require("node:test");
const assert = require("node:assert/strict");
const {
  decideLicenseVerificationStatus,
} = require("./licenseVerificationPolicy");

const approvedSignals = {
  documentDetected: true,
  keywordsOk: true,
  extractedRut: "12345678-5",
  strictRutOk: true,
  dvValid: true,
  declaredRut: "12345678-5",
  matchDeclared: true,
  extractedName: "JUAN PEREZ",
  nameMatchOk: true,
  expiryIso: "2030-01-01T23:59:59.000Z",
  expired: false,
  licenseClassDetected: true,
  classOk: true,
  textureValid: true,
  suspiciousAttempt: false,
};

test("approves only high-confidence license OCR", () => {
  assert.equal(decideLicenseVerificationStatus(approvedSignals), "approved");
});

test("approves soft OCR misses when identity still matches", () => {
  assert.equal(
    decideLicenseVerificationStatus({
      ...approvedSignals,
      extractedName: null,
      nameMatchOk: false,
      textureValid: false,
      suspiciousAttempt: true,
    }),
    "approved",
  );
});

test("approves missing expiry, but rejects confirmed expired license", () => {
  assert.equal(
    decideLicenseVerificationStatus({
      ...approvedSignals,
      expiryIso: null,
    }),
    "approved",
  );

  assert.equal(
    decideLicenseVerificationStatus({
      ...approvedSignals,
      expiryIso: "2020-01-01T23:59:59.000Z",
      expired: true,
    }),
    "rejected",
  );
});

test("rejects confirmed incompatible license class", () => {
  assert.equal(
    decideLicenseVerificationStatus({
      ...approvedSignals,
      classOk: false,
    }),
    "rejected",
  );
});

test("rejects when neither rut nor name can identify the rider", () => {
  assert.equal(
    decideLicenseVerificationStatus({
      ...approvedSignals,
      matchDeclared: false,
      extractedName: null,
      nameMatchOk: false,
    }),
    "rejected",
  );
});
