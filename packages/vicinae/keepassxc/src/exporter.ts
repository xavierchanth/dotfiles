import { spawn } from "node:child_process";
import { isAbsolute } from "node:path";
import type { CredentialMode, Vault } from "./domain";
import { MAX_EXPORT_BYTES, parseKeePassXml } from "./xml";

export type RawCredentialPreferences = Readonly<{
  credentialMode: "password" | "password-key-file" | "key-file-only";
  keyFilePath?: string;
}>;

export type UnlockConfig = Readonly<{ databasePath: string; helperPath: string; credentials: CredentialMode }>;
export type Invocation = Readonly<{ executable: string; args: readonly string[]; stdin?: string }>;
export type UnlockRequest =
  | Readonly<{ kind: "prompt"; password: string }>
  | Readonly<{ kind: "keychain" }>
  | Readonly<{ kind: "key-file-only" }>;

function exactPath(path: string | undefined, label: string): string {
  if (!path || !isAbsolute(path)) throw new Error(`${label} must be configured as an absolute path`);
  return path;
}

export function parseCredentialMode(preferences: RawCredentialPreferences): CredentialMode {
  switch (preferences.credentialMode) {
    case "password": return { kind: "password" };
    case "password-key-file": return { kind: "password-key-file", keyFilePath: exactPath(preferences.keyFilePath, "Key file") };
    case "key-file-only": return { kind: "key-file-only", keyFilePath: exactPath(preferences.keyFilePath, "Key file") };
  }
}

export function promptInvocation(config: UnlockConfig, password?: string): Invocation {
  const args = config.credentials.kind === "key-file-only"
    ? ["key-file-export", config.databasePath, config.credentials.keyFilePath]
    : ["prompt-export", config.databasePath, ...(config.credentials.kind === "password-key-file" ? [config.credentials.keyFilePath] : [])];
  if (config.credentials.kind !== "key-file-only" && password === undefined) throw new Error("Database password is required");
  return { executable: exactPath(config.helperPath, "KeePassXC helper"), args, ...(password === undefined ? {} : { stdin: password }) };
}

export function helperExportInvocation(config: UnlockConfig): Invocation {
  if (config.credentials.kind === "key-file-only") throw new Error("Remembered-password export is unavailable for this credential mode");
  return { executable: exactPath(config.helperPath, "Keychain helper"), args: ["export", config.databasePath, ...(config.credentials.kind === "password-key-file" ? [config.credentials.keyFilePath] : [])] };
}

export function unlockInvocation(config: UnlockConfig, request: UnlockRequest): Invocation {
  if (config.credentials.kind === "key-file-only") {
    if (request.kind !== "key-file-only") throw new Error("This database uses only a key file");
    return promptInvocation(config);
  }
  if (request.kind === "key-file-only") throw new Error("This database requires a password");
  return request.kind === "keychain" ? helperExportInvocation(config) : promptInvocation(config, request.password);
}

function run(invocation: Invocation, maxBytes: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(invocation.executable, [...invocation.args], { shell: false, stdio: ["pipe", "pipe", "pipe"], windowsHide: true });
    const stdout: Buffer[] = [];
    let stdoutBytes = 0;
    const timer = setTimeout(() => child.kill(), 30_000);
    child.stdout.on("data", (chunk: Buffer) => {
      stdoutBytes += chunk.length;
      if (stdoutBytes > maxBytes) child.kill(); else stdout.push(chunk);
    });
    child.stderr.resume();
    child.on("error", () => { clearTimeout(timer); reject(new Error("Could not start the credential helper")); });
    child.on("close", (code, signal) => {
      clearTimeout(timer);
      if (stdoutBytes > maxBytes) return reject(new Error("KeePass export exceeds the safety limit"));
      if (code !== 0) return reject(new Error(`KeePassXC could not unlock the database (${signal ? "terminated" : `exit ${code}`})`));
      resolve(Buffer.concat(stdout).toString("utf8"));
    });
    child.stdin.end(invocation.stdin === undefined ? undefined : `${invocation.stdin}\n`);
  });
}

export async function unlockVault(config: UnlockConfig, request: UnlockRequest): Promise<Vault> {
  const xml = await run(unlockInvocation(config, request), MAX_EXPORT_BYTES);
  return parseKeePassXml(xml);
}

export async function rememberPassword(config: UnlockConfig, password: string): Promise<void> {
  if (config.credentials.kind === "key-file-only") throw new Error("This database does not use a password");
  await run({ executable: exactPath(config.helperPath, "Keychain helper"), args: ["store", config.databasePath], stdin: password }, 1024);
}

export async function forgetPassword(config: UnlockConfig): Promise<void> {
  await run({ executable: exactPath(config.helperPath, "Keychain helper"), args: ["delete", config.databasePath] }, 1024);
}
