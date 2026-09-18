import { LocalStorage } from "@vicinae/api";
import type { EntryId } from "./domain";

const STORAGE_KEY = "favorite-entry-ids-v1";
const validId = (value: unknown): value is EntryId => typeof value === "string" && /^[^:]+:[^:]+$/.test(value);

export async function loadFavorites(): Promise<ReadonlySet<EntryId>> {
  const raw = await LocalStorage.getItem<string>(STORAGE_KEY);
  if (!raw) return new Set();
  try {
    const parsed: unknown = JSON.parse(raw);
    return new Set(Array.isArray(parsed) ? parsed.filter(validId) : []);
  } catch { return new Set(); }
}

export async function saveFavorites(favorites: ReadonlySet<EntryId>): Promise<void> {
  await LocalStorage.setItem(STORAGE_KEY, JSON.stringify([...favorites].sort()));
}
