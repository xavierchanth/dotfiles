export type EntryId = `${string}:${string}`;

export type TotpConfig = Readonly<{
  secret: Uint8Array;
  algorithm: "sha1" | "sha256" | "sha512";
  digits: 6 | 7 | 8;
  period: number;
}>;

export type VaultEntry = Readonly<{
  id: EntryId;
  title: string;
  username: string;
  password: string;
  url: string;
  group: string;
  totp?: TotpConfig;
}>;

export type Vault = Readonly<{ rootUuid: string; entries: readonly VaultEntry[] }>;

export type CredentialMode =
  | Readonly<{ kind: "password" }>
  | Readonly<{ kind: "password-key-file"; keyFilePath: string }>
  | Readonly<{ kind: "key-file-only"; keyFilePath: string }>;

export type VaultState =
  | Readonly<{ kind: "locked" }>
  | Readonly<{ kind: "unlocking" }>
  | Readonly<{ kind: "unlocked"; vault: Vault; expiresAt: number }>
  | Readonly<{ kind: "error"; message: string }>;
