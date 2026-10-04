import { describe, expect, test } from "bun:test";
import { mostCommonShorts } from "./channel-summary";

describe("mostCommonShorts", () => {
  test("is the setting most filters have", () => {
    expect(
      mostCommonShorts([
        { shortsFilter: "normal" },
        { shortsFilter: "normal" },
        {},
      ]),
    ).toBe("normal");
  });

  test("reads an absent setting as all", () => {
    expect(mostCommonShorts([{}, {}, { shortsFilter: "shorts" }])).toBe("all");
  });

  test("is all on a tie, even between the other two", () => {
    expect(
      mostCommonShorts([
        { shortsFilter: "normal" },
        { shortsFilter: "shorts" },
      ]),
    ).toBe("all");
    expect(mostCommonShorts([{ shortsFilter: "normal" }, {}])).toBe("all");
  });

  test("is all with no filters", () => {
    expect(mostCommonShorts([])).toBe("all");
  });
});
