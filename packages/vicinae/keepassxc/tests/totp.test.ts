import assert from "node:assert/strict";
import test from "node:test";
import { currentTotp, parseTotp } from "../src/totp";

test("matches the RFC 6238 SHA-1 vector", () => {
  const config = parseTotp("otpauth://totp/test?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&algorithm=SHA1&digits=8&period=30");
  assert.equal(currentTotp(config, 59_000), "94287082");
});

test("accepts strict supported parameters", () => {
  assert.equal(parseTotp("JBSWY3DPEHPK3PXP").digits, 6);
  assert.throws(() => parseTotp("otpauth://hotp/test?secret=JBSWY3DPEHPK3PXP"), /Only otpauth TOTP/);
  assert.throws(() => parseTotp("otpauth://totp/test?secret=JBSWY3DPEHPK3PXP&algorithm=MD5"), /algorithm/);
  assert.throws(() => parseTotp("otpauth://totp/test?secret=JBSWY3DPEHPK3PXP&digits=9"), /digits/);
  assert.throws(() => parseTotp("%%%%"), /Base32/);
});
