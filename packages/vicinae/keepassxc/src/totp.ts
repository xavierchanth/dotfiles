import { createHmac } from "node:crypto";
import type { TotpConfig } from "./domain";

const BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

export function decodeBase32(value: string): Uint8Array {
  const normalized = value.replace(/[ -]/g, "").replace(/=+$/, "").toUpperCase();
  if (!normalized || /[^A-Z2-7]/.test(normalized)) throw new Error("TOTP secret is not valid Base32");
  let bits = 0;
  let accumulator = 0;
  const bytes: number[] = [];
  for (const character of normalized) {
    accumulator = (accumulator << 5) | BASE32.indexOf(character);
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((accumulator >>> bits) & 0xff);
    }
  }
  if (bits > 0 && (accumulator & ((1 << bits) - 1)) !== 0) throw new Error("TOTP secret has non-zero trailing bits");
  return Uint8Array.from(bytes);
}

export function parseTotp(value: string): TotpConfig {
  let secret = value;
  let algorithm = "sha1";
  let digits = 6;
  let period = 30;
  if (value.startsWith("otpauth://")) {
    const url = new URL(value);
    if (url.protocol !== "otpauth:" || url.hostname !== "totp") throw new Error("Only otpauth TOTP URIs are supported");
    secret = url.searchParams.get("secret") ?? "";
    algorithm = (url.searchParams.get("algorithm") ?? "sha1").toLowerCase();
    digits = Number(url.searchParams.get("digits") ?? "6");
    period = Number(url.searchParams.get("period") ?? "30");
  }
  if (algorithm !== "sha1" && algorithm !== "sha256" && algorithm !== "sha512") throw new Error("Unsupported TOTP algorithm");
  if (digits !== 6 && digits !== 7 && digits !== 8) throw new Error("TOTP digits must be 6, 7, or 8");
  if (!Number.isInteger(period) || period < 1 || period > 300) throw new Error("TOTP period must be between 1 and 300 seconds");
  return { secret: decodeBase32(secret), algorithm, digits, period };
}

export function currentTotp(config: TotpConfig, now = Date.now()): string {
  const counter = Math.floor(now / 1000 / config.period);
  const message = Buffer.alloc(8);
  message.writeBigUInt64BE(BigInt(counter));
  const digest = createHmac(config.algorithm, config.secret).update(message).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const binary = ((digest[offset] & 0x7f) << 24) | (digest[offset + 1] << 16) | (digest[offset + 2] << 8) | digest[offset + 3];
  return (binary % 10 ** config.digits).toString().padStart(config.digits, "0");
}
