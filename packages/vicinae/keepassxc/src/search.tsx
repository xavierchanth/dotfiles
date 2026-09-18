import React, { useCallback, useEffect, useState } from "react";
import { Action, ActionPanel, Clipboard, Form, Icon, List, environment, getPreferenceValues, showToast, Toast } from "@vicinae/api";
import type { CredentialMode, EntryId, VaultEntry, VaultState } from "./domain";
import { forgetPassword, parseCredentialMode, rememberPassword, unlockVault, type UnlockConfig, type UnlockRequest } from "./exporter";
import { loadFavorites, saveFavorites } from "./favorites";
import { currentTotp } from "./totp";

type Preferences = {
  databasePath: string;
  credentialMode: "password" | "password-key-file" | "key-file-only";
  keyFilePath?: string;
  expiryMinutes: string;
};

const safeMessage = (error: unknown) => error instanceof Error ? error.message.replace(/[\r\n]+/g, " ").slice(0, 240) : "Unlock failed";

export default function SearchKeePassXC() {
  const preferences = getPreferenceValues<Preferences>();
  const expiryMs = Math.max(1, Number(preferences.expiryMinutes) || 5) * 60_000;
  const [state, setState] = useState<VaultState>({ kind: "locked" });
  const [favorites, setFavorites] = useState<ReadonlySet<EntryId>>(new Set());
  const credentials = parseCredentialMode(preferences);
  const config: UnlockConfig = {
    databasePath: preferences.databasePath,
    helperPath: `${environment.assetsPath}/vicinae-keepassxc-helper`,
    credentials,
  };

  useEffect(() => { void loadFavorites().then(setFavorites); }, []);
  useEffect(() => {
    if (state.kind !== "unlocked") return;
    const delay = Math.max(0, state.expiresAt - Date.now());
    const timer = setTimeout(() => setState({ kind: "locked" }), delay);
    return () => clearTimeout(timer);
  }, [state]);

  const touch = useCallback(() => setState((current) => current.kind === "unlocked" ? { ...current, expiresAt: Date.now() + expiryMs } : current), [expiryMs]);
  const unlock = useCallback(async (request: UnlockRequest, remember = false) => {
    setState({ kind: "unlocking" });
    try {
      const vault = await unlockVault(config, request);
      if (remember && request.kind === "prompt") await rememberPassword(config, request.password);
      setState({ kind: "unlocked", vault, expiresAt: Date.now() + expiryMs });
    } catch (error) {
      setState({ kind: "error", message: safeMessage(error) });
    }
  }, [config, expiryMs]);

  if (state.kind === "unlocking") return <List isLoading searchBarPlaceholder="Unlocking KeePassXC…" />;
  if (state.kind === "error") return <UnlockForm error={state.message} credentials={credentials} onUnlock={unlock} />;
  if (state.kind === "locked") return <UnlockForm credentials={credentials} onUnlock={unlock} />;

  const ordered = [...state.vault.entries].sort((left, right) => Number(favorites.has(right.id)) - Number(favorites.has(left.id)) || left.title.localeCompare(right.title));
  const toggleFavorite = async (id: EntryId) => {
    const next = new Set(favorites);
    if (next.has(id)) next.delete(id); else next.add(id);
    setFavorites(next);
    await saveFavorites(next);
    touch();
  };
  const paste = async (value: string) => { touch(); await Clipboard.paste(value); };
  const forget = async () => {
    try {
      await forgetPassword(config);
      await showToast({ style: Toast.Style.Success, title: "Forgot remembered password" });
      setState({ kind: "locked" });
    } catch (error) {
      await showToast({ style: Toast.Style.Failure, title: "Could not forget password", message: safeMessage(error) });
    }
  };

  return <List searchBarPlaceholder="Search title, username, group, or URL…">
    {ordered.map((entry) => <List.Item
      key={entry.id}
      id={entry.id}
      title={entry.title}
      subtitle={entry.username}
      keywords={[entry.username, entry.group, entry.url]}
      icon={favorites.has(entry.id) ? Icon.Star : Icon.Key}
      accessories={[...(favorites.has(entry.id) ? [{ icon: Icon.Star, tooltip: "Pinned" }] : []), ...(entry.group ? [{ text: entry.group }] : [])]}
      actions={<EntryActions entry={entry} pinned={favorites.has(entry.id)} canForget={credentials.kind !== "key-file-only"} onPaste={paste} onToggle={() => void toggleFavorite(entry.id)} onLock={() => setState({ kind: "locked" })} onForget={() => void forget()} />}
    />)}
  </List>;
}

function UnlockForm({ error, credentials, onUnlock }: { error?: string; credentials: CredentialMode; onUnlock: (request: UnlockRequest, remember?: boolean) => Promise<void> }) {
  const [password, setPassword] = useState("");
  const [remember, setRemember] = useState(false);
  const passwordBearing = credentials.kind !== "key-file-only";
  return <Form actions={<ActionPanel>
    <Action.SubmitForm title="Unlock Database" icon={Icon.LockUnlocked} onSubmit={() => onUnlock(passwordBearing ? { kind: "prompt", password } : { kind: "key-file-only" }, remember)} />
    {passwordBearing ? <Action title="Unlock with macOS Keychain" icon={Icon.Fingerprint} onAction={() => void onUnlock({ kind: "keychain" })} /> : null}
  </ActionPanel>}>
    {error ? <Form.Description title="Unlock failed" text={error} /> : null}
    {credentials.kind === "key-file-only" ? <Form.Description text="This database will unlock with its configured key file and no password." /> : null}
    {passwordBearing ? <Form.Description text="Enter the password below, or choose Unlock with macOS Keychain from the actions." /> : null}
    {passwordBearing ? <Form.PasswordField id="password" title="Database Password" value={password} onChange={setPassword} storeValue={false} autoFocus /> : null}
    {passwordBearing ? <Form.Checkbox id="remember" label="Remember in macOS Keychain" value={remember} onChange={setRemember} /> : null}
  </Form>;
}

function EntryActions({ entry, pinned, canForget, onPaste, onToggle, onLock, onForget }: { entry: VaultEntry; pinned: boolean; canForget: boolean; onPaste: (value: string) => Promise<void>; onToggle: () => void; onLock: () => void; onForget: () => void }) {
  const pasteTotp = async () => {
    if (!entry.totp) return;
    try { await onPaste(currentTotp(entry.totp)); }
    catch { await showToast({ style: Toast.Style.Failure, title: "Could not generate TOTP" }); }
  };
  return <ActionPanel>
    <Action title="Paste Password" icon={Icon.Key} autoFocus onAction={() => void onPaste(entry.password)} />
    <Action title="Paste Username" icon={Icon.Person} onAction={() => void onPaste(entry.username)} />
    {entry.totp ? <Action title="Paste Current TOTP" icon={Icon.Clock} onAction={() => void pasteTotp()} /> : null}
    <Action title={pinned ? "Unpin" : "Pin"} icon={Icon.Star} onAction={onToggle} />
    {canForget ? <Action title="Forget Remembered Password" icon={Icon.Trash} style={Action.Style.Destructive} onAction={onForget} /> : null}
    <Action title="Lock" icon={Icon.Lock} style={Action.Style.Destructive} onAction={onLock} />
  </ActionPanel>;
}
