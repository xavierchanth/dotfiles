export type Rect = { x: number; y: number; width: number; height: number };
export type Placement = "left-half" | "right-half" | "top-left-quarter" | "top-right-quarter" | "bottom-left-quarter" | "bottom-right-quarter" | "maximize" | "center";

const roundRect = (rect: Rect): Rect => ({ x: Math.round(rect.x), y: Math.round(rect.y), width: Math.round(rect.width), height: Math.round(rect.height) });

export function containsPoint(rect: Rect, x: number, y: number): boolean {
  return x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height;
}

export function screenForWindow(window: Rect, screens: Rect[]): number {
  const centerX = window.x + window.width / 2;
  const centerY = window.y + window.height / 2;
  const containing = screens.findIndex((screen) => containsPoint(screen, centerX, centerY));
  if (containing >= 0) return containing;
  let bestIndex = -1;
  let bestArea = 0;
  for (const [index, screen] of screens.entries()) {
    const width = Math.max(0, Math.min(window.x + window.width, screen.x + screen.width) - Math.max(window.x, screen.x));
    const height = Math.max(0, Math.min(window.y + window.height, screen.y + screen.height) - Math.max(window.y, screen.y));
    const area = width * height;
    if (area > bestArea) { bestArea = area; bestIndex = index; }
  }
  return bestIndex;
}

export function place(window: Rect, screen: Rect, placement: Placement): Rect {
  const right = Math.round(screen.x + screen.width);
  const bottom = Math.round(screen.y + screen.height);
  const middleX = Math.round(screen.x + screen.width / 2);
  const middleY = Math.round(screen.y + screen.height / 2);
  const leftWidth = middleX - Math.round(screen.x);
  const rightWidth = right - middleX;
  const topHeight = middleY - Math.round(screen.y);
  const bottomHeight = bottom - middleY;
  switch (placement) {
    case "left-half": return { x: Math.round(screen.x), y: Math.round(screen.y), width: leftWidth, height: bottom - Math.round(screen.y) };
    case "right-half": return { x: middleX, y: Math.round(screen.y), width: rightWidth, height: bottom - Math.round(screen.y) };
    case "top-left-quarter": return { x: Math.round(screen.x), y: Math.round(screen.y), width: leftWidth, height: topHeight };
    case "top-right-quarter": return { x: middleX, y: Math.round(screen.y), width: rightWidth, height: topHeight };
    case "bottom-left-quarter": return { x: Math.round(screen.x), y: middleY, width: leftWidth, height: bottomHeight };
    case "bottom-right-quarter": return { x: middleX, y: middleY, width: rightWidth, height: bottomHeight };
    case "maximize": return roundRect(screen);
    case "center": return roundRect({ x: screen.x + (screen.width - Math.min(window.width, screen.width)) / 2, y: screen.y + (screen.height - Math.min(window.height, screen.height)) / 2, width: Math.min(window.width, screen.width), height: Math.min(window.height, screen.height) });
  }
}

export function moveToDisplay(window: Rect, source: Rect, target: Rect): Rect {
  const relativeX = source.width > window.width ? (window.x - source.x) / (source.width - window.width) : 0;
  const relativeY = source.height > window.height ? (window.y - source.y) / (source.height - window.height) : 0;
  const width = Math.min(window.width, target.width);
  const height = Math.min(window.height, target.height);
  return roundRect({ x: target.x + Math.max(0, target.width - width) * Math.max(0, Math.min(1, relativeX)), y: target.y + Math.max(0, target.height - height) * Math.max(0, Math.min(1, relativeY)), width, height });
}
