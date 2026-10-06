import { describe, expect, test } from "bun:test";
import { LOAD_PROGRESS_START, loadFraction } from "./load-progress";

describe("loadFraction", () => {
  test("stands at the first step while the channels aren't known", () => {
    expect(loadFraction(0, null)).toBe(LOAD_PROGRESS_START);
  });

  test("never sits under the first step", () => {
    expect(loadFraction(0, 40)).toBe(LOAD_PROGRESS_START);
    expect(loadFraction(1, 40)).toBe(LOAD_PROGRESS_START);
    expect(loadFraction(0, 0)).toBe(LOAD_PROGRESS_START);
  });

  test("is the share of channels finished", () => {
    expect(loadFraction(10, 40)).toBe(0.25);
    expect(loadFraction(40, 40)).toBe(1);
  });

  test("never passes the end", () => {
    expect(loadFraction(41, 40)).toBe(1);
  });
});
