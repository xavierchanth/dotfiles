import assert from "node:assert/strict";
import test from "node:test";
import { moveToDisplay, place, screenForWindow } from "../src/geometry";

const screen = { x: 0, y: 25, width: 1200, height: 775 };
test("places halves and quarters inside usable bounds", () => {
  assert.deepEqual(place({ x: 20, y: 40, width: 600, height: 400 }, screen, "left-half"), { x: 0, y: 25, width: 600, height: 775 });
  assert.deepEqual(place({ x: 20, y: 40, width: 600, height: 400 }, screen, "bottom-right-quarter"), { x: 600, y: 413, width: 600, height: 387 });
});
test("keeps right and bottom placements within odd-sized usable bounds", () => {
  const oddScreen = { x: -1201, y: 23, width: 1201, height: 777 };
  const window = { x: -1000, y: 100, width: 500, height: 400 };
  for (const placement of ["right-half", "top-right-quarter", "bottom-left-quarter", "bottom-right-quarter"] as const) {
    const result = place(window, oddScreen, placement);
    assert.ok(result.x >= oddScreen.x && result.y >= oddScreen.y);
    assert.ok(result.x + result.width <= oddScreen.x + oddScreen.width);
    assert.ok(result.y + result.height <= oddScreen.y + oddScreen.height);
  }
});
test("centers without exceeding the usable screen", () => { assert.deepEqual(place({ x: 0, y: 0, width: 1400, height: 900 }, screen, "center"), screen); });
test("matches the display containing the window center", () => { assert.equal(screenForWindow({ x: 1300, y: 100, width: 500, height: 400 }, [screen, { x: 1200, y: 0, width: 1000, height: 700 }]), 1); });
test("moves between displays while preserving relative placement", () => { assert.deepEqual(moveToDisplay({ x: 300, y: 125, width: 600, height: 400 }, screen, { x: 1200, y: 0, width: 1000, height: 700 }), { x: 1400, y: 80, width: 600, height: 400 }); });
