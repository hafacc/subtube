import { describe, expect, test } from "bun:test";
import { INFO_PAGES, textParts, updatedLabel } from "./pages";

describe("info pages", () => {
  test("every shared page reads", () => {
    expect(INFO_PAGES.privacy.sections.length).toBeGreaterThan(0);
    expect(INFO_PAGES.terms.intro.length).toBe(1);
  });

  test("links split out of the text", () => {
    expect(
      textParts("Mail [us](mailto:a@b.c) or see [x](https://x.y/z)."),
    ).toEqual([
      { text: "Mail " },
      { text: "us", href: "mailto:a@b.c" },
      { text: " or see " },
      { text: "x", href: "https://x.y/z" },
      { text: "." },
    ]);
    expect(textParts("plain (text)")).toEqual([{ text: "plain (text)" }]);
  });

  test("the date reads in American English", () => {
    expect(updatedLabel("2026-10-13")).toBe("Last updated October 13, 2026");
  });
});
