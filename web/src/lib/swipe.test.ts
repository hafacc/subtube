import { describe, expect, test } from "bun:test";
import { swipeIntent, swipeOffset, swipePasses } from "./swipe";

describe("swipeIntent", () => {
  test("is undecided until the pointer has moved far enough", () => {
    expect(swipeIntent(0, 0)).toBe("undecided");
    expect(swipeIntent(9, 0)).toBe("undecided");
    expect(swipeIntent(-6, 9)).toBe("undecided");
  });

  test("is a swipe when the movement is clearly sideways, either way", () => {
    expect(swipeIntent(10, 0)).toBe("swipe");
    expect(swipeIntent(-10, 0)).toBe("swipe");
    expect(swipeIntent(20, 10)).toBe("swipe");
    expect(swipeIntent(-30, -12)).toBe("swipe");
  });

  test("is a scroll when the movement is upright or diagonal", () => {
    expect(swipeIntent(0, 10)).toBe("scroll");
    expect(swipeIntent(0, -10)).toBe("scroll");
    expect(swipeIntent(10, 10)).toBe("scroll");
    expect(swipeIntent(19, 10)).toBe("scroll");
    expect(swipeIntent(-12, 8)).toBe("scroll");
  });
});

describe("swipeOffset", () => {
  test("follows the pointer", () => {
    expect(swipeOffset(40, 360)).toBe(40);
    expect(swipeOffset(-40, 360)).toBe(-40);
  });

  test("stops at the card's width", () => {
    expect(swipeOffset(500, 360)).toBe(360);
    expect(swipeOffset(-500, 360)).toBe(-360);
  });
});

describe("swipePasses", () => {
  test("passes at a quarter of the card's width, in either direction", () => {
    expect(swipePasses(90, 360)).toBe(true);
    expect(swipePasses(-90, 360)).toBe(true);
    expect(swipePasses(200, 360)).toBe(true);
  });

  test("falls short under a quarter", () => {
    expect(swipePasses(89, 360)).toBe(false);
    expect(swipePasses(-89, 360)).toBe(false);
    expect(swipePasses(0, 360)).toBe(false);
  });

  test("never passes on a card with no width", () => {
    expect(swipePasses(0, 0)).toBe(false);
    expect(swipePasses(50, 0)).toBe(false);
  });
});
