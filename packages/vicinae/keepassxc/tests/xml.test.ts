import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { parseKeePassXml } from "../src/xml";

const fixture = readFileSync(join(__dirname, "fixtures/vault.xml"), "utf8");

test("parses entries and excludes recycle-bin and history content", () => {
  const vault = parseKeePassXml(fixture);
  assert.equal(vault.rootUuid, "root-uuid");
  assert.deepEqual(vault.entries.map(({ id, title, username, group }) => ({ id, title, username, group })), [
    { id: "root-uuid:entry-1", title: "Example", username: "alice", group: "Root / Work & Labs" },
    { id: "root-uuid:entry-history-holder", title: "Current", username: "", group: "Root / Work & Labs" },
  ]);
  assert.ok(vault.entries[0].totp);
});

test("parses KeePassXC XML shapes with padded UUIDs and protected values", () => {
  const xml = readFileSync(join(__dirname, "fixtures/genuine-shape.xml"), "utf8");
  const vault = parseKeePassXml(xml);
  assert.equal(vault.rootUuid, "AQIDBAUGBwgJCgsMDQ4PEA==");
  assert.equal(vault.entries[0].id, "AQIDBAUGBwgJCgsMDQ4PEA==:ERITFBUWFxgZGhscHR4fIA==");
  assert.equal(vault.entries[0].password, "redacted-fixture-value");
  assert.equal(vault.entries[0].totp?.digits, 6);
});

test("rejects DTDs and custom entities", () => {
  assert.throws(() => parseKeePassXml('<!DOCTYPE x [<!ENTITY leak SYSTEM "file:///etc/passwd">]><KeePassFile/>'), /forbidden/);
  assert.throws(() => parseKeePassXml("<KeePassFile>&leak;</KeePassFile>"), /entity/);
});

test("rejects oversized exports before parsing", () => {
  assert.throws(() => parseKeePassXml(`<KeePassFile>${"x".repeat(16 * 1024 * 1024)}</KeePassFile>`), /16 MiB/);
});
