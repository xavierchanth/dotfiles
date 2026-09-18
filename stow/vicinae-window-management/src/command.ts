import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { environment, LocalStorage, showToast, Toast, WindowManagement, type LaunchProps } from "@vicinae/api";
import { moveToDisplay, place, screenForWindow, type Placement, type Rect } from "./geometry";

const execFileAsync = promisify(execFile);
const restoreKey = "previous-window-bounds";
type VisibleScreen = Rect & { id: number; name: string };
type StoredBounds = { windowId: string; bounds: Rect };

function rectFromWindow(window: WindowManagement.Window): Rect {
  return { x: window.bounds.position.x, y: window.bounds.position.y, width: window.bounds.size.width, height: window.bounds.size.height };
}

async function runHelper(payload: object): Promise<unknown> {
  const helper = `${environment.assetsPath}/macos-window-helper.jxa`;
  const { stdout } = await execFileAsync("/usr/bin/osascript", ["-l", "JavaScript", helper, JSON.stringify(payload)], { timeout: 5000, maxBuffer: 1024 * 1024 });
  const trimmed = stdout.trim();
  return trimmed ? JSON.parse(trimmed) : null;
}

async function visibleScreens(): Promise<VisibleScreen[]> {
  const result = await runHelper({ operation: "screens" });
  if (!Array.isArray(result) || result.length === 0) throw new Error("macOS returned no usable screens");
  return result as VisibleScreen[];
}

async function setBounds(window: WindowManagement.Window, bounds: Rect): Promise<void> {
  const app = window.application;
  if (!app?.id) throw new Error("The active window has no application identifier");
  await runHelper({ operation: "set-bounds", bundleId: app.id, windowId: window.id, title: window.title, currentBounds: rectFromWindow(window), bounds });
}

async function remember(window: WindowManagement.Window): Promise<void> {
  const stored: StoredBounds = { windowId: window.id, bounds: rectFromWindow(window) };
  await LocalStorage.setItem(restoreKey, JSON.stringify(stored));
}

async function execute(action: string, args?: { width?: string; height?: string }): Promise<void> {
  const window = await WindowManagement.getActiveWindow();
  if (!window) throw new Error("No active positionable window was found");
  if (action === "restore") {
    const raw = await LocalStorage.getItem<string>(restoreKey);
    if (!raw) throw new Error("No previous window bounds have been saved");
    const stored = JSON.parse(raw) as StoredBounds;
    if (stored.windowId !== window.id) throw new Error("Saved bounds belong to a different window");
    await setBounds(window, stored.bounds);
    return;
  }

  const screens = await visibleScreens();
  const current = rectFromWindow(window);
  const screenIndex = screenForWindow(current, screens);
  if (screenIndex < 0) throw new Error("The active window could not be matched to a display");
  const currentScreen = screens[screenIndex];
  let bounds: Rect;
  if (action === "next-display" || action === "previous-display") {
    if (screens.length < 2) throw new Error("Only one display is connected");
    const delta = action === "next-display" ? 1 : -1;
    bounds = moveToDisplay(current, currentScreen, screens[(screenIndex + delta + screens.length) % screens.length]);
  } else if (action === "resize") {
    const width = Number(args?.width);
    const height = Number(args?.height);
    if (!Number.isFinite(width) || !Number.isFinite(height) || width < 100 || height < 100) throw new Error("Width and height must be numbers of at least 100");
    bounds = place({ ...current, width, height }, currentScreen, "center");
  } else {
    bounds = place(current, currentScreen, action as Placement);
  }
  await remember(window);
  await setBounds(window, bounds);
}

export function command(action: string) {
  return async (props?: LaunchProps<{ arguments: { width?: string; height?: string } }>) => {
    try {
      await execute(action, props?.arguments);
    } catch (error) {
      await showToast({ style: Toast.Style.Failure, title: "Window command failed", message: error instanceof Error ? error.message : String(error) });
    }
  };
}
