import { describe, expect, test } from "bun:test";
import fixture from "../../../shared/fixtures/settings.json";
import { DEFAULT_SETTINGS, readSettings, type Settings } from "./settings";

describe("shared settings fixtures", () => {
  for (const testCase of fixture.cases) {
    test(testCase.name, () => {
      expect(
        readSettings(
          testCase.settings as Record<string, { at: number; value: unknown }>,
        ),
      ).toEqual(testCase.expected as Settings);
    });
  }
});

describe("readSettings", () => {
  test("an old file's missing settings are the defaults", () => {
    expect(readSettings({})).toEqual(DEFAULT_SETTINGS);
  });
});
