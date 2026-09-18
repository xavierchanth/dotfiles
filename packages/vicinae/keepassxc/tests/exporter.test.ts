import assert from "node:assert/strict";
import test from "node:test";
import { helperExportInvocation, parseCredentialMode, promptInvocation, unlockInvocation, type UnlockConfig } from "../src/exporter";

const base = { databasePath: "/vault/main.kdbx", helperPath: "/extension/assets/vicinae-keepassxc-helper" };

test("password prompt sends the secret only on stdin", () => {
  const invocation = promptInvocation({ ...base, credentials: { kind: "password" } }, "correct horse");
  assert.deepEqual(invocation.args, ["prompt-export", "/vault/main.kdbx"]);
  assert.equal(invocation.executable, "/extension/assets/vicinae-keepassxc-helper");
  assert.equal(invocation.stdin, "correct horse");
  assert.equal(invocation.args.includes("correct horse"), false);
});

test("key-file-only is the only mode that passes --no-password", () => {
  const invocation = promptInvocation({ ...base, credentials: { kind: "key-file-only", keyFilePath: "/keys/main.keyx" } });
  assert.deepEqual(invocation.args, ["key-file-export", "/vault/main.kdbx", "/keys/main.keyx"]);
  assert.equal(invocation.stdin, undefined);
});

test("password plus key file remains a password-bearing mode", () => {
  const config: UnlockConfig = { ...base, credentials: { kind: "password-key-file", keyFilePath: "/keys/main.keyx" } };
  assert.throws(() => promptInvocation(config), /password is required/i);
  assert.equal(promptInvocation(config, "secret").args.includes("--no-password"), false);
});

test("remembered mode delegates export to the helper without a password", () => {
  const invocation = helperExportInvocation({ ...base, credentials: { kind: "password-key-file", keyFilePath: "/keys/main.keyx" } });
  assert.deepEqual(invocation, { executable: "/extension/assets/vicinae-keepassxc-helper", args: ["export", "/vault/main.kdbx", "/keys/main.keyx"] });
});

test("key-file modes require an absolute key-file path", () => {
  assert.throws(() => parseCredentialMode({ credentialMode: "key-file-only" }), /key file/i);
  assert.throws(() => parseCredentialMode({ credentialMode: "password-key-file", keyFilePath: "relative.keyx" }), /absolute/i);
});

test("password modes keep prompt and Keychain unlock paths independently available", () => {
  const config: UnlockConfig = { ...base, credentials: { kind: "password" } };
  assert.equal(unlockInvocation(config, { kind: "prompt", password: "fallback" }).stdin, "fallback");
  assert.deepEqual(unlockInvocation(config, { kind: "keychain" }).args, ["export", "/vault/main.kdbx"]);
});

test("credential mode rejects unlock requests from incompatible flows", () => {
  const keyOnly: UnlockConfig = { ...base, credentials: { kind: "key-file-only", keyFilePath: "/keys/main.keyx" } };
  assert.throws(() => unlockInvocation(keyOnly, { kind: "prompt", password: "unused" }), /only a key file/i);
  assert.throws(() => unlockInvocation({ ...base, credentials: { kind: "password" } }, { kind: "key-file-only" }), /requires a password/i);
});
