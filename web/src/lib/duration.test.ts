import { describe, expect, test } from "bun:test";
import { formatDuration, shortDate } from "./duration";

describe("formatDuration", () => {
  test("under a minute pads the seconds", () => {
    expect(formatDuration(0)).toBe("0:00");
    expect(formatDuration(5)).toBe("0:05");
    expect(formatDuration(59)).toBe("0:59");
  });

  test("minutes and seconds", () => {
    expect(formatDuration(65)).toBe("1:05");
    expect(formatDuration(600)).toBe("10:00");
  });

  test("an hour or more switches to H:MM:SS", () => {
    expect(formatDuration(3600)).toBe("1:00:00");
    expect(formatDuration(3661)).toBe("1:01:01");
    expect(formatDuration(36000)).toBe("10:00:00");
  });
});

describe("shortDate", () => {
  const now = new Date(2026, 9, 8);

  test("a date of this year has no year", () => {
    expect(shortDate(new Date(2026, 8, 24).toISOString(), now)).not.toContain(
      "2026",
    );
  });

  test("a date of another year has its year", () => {
    expect(shortDate(new Date(2025, 8, 24).toISOString(), now)).toContain(
      "2025",
    );
    expect(shortDate(new Date(2025, 11, 31).toISOString(), now)).toContain(
      "2025",
    );
  });
});
