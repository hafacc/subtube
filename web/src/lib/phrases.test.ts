import { describe, expect, test } from "bun:test";
import fixture from "../../../shared/fixtures/phrases.json";
import { compilePattern, isValidPattern } from "./filters";
import {
  patternToPhrases,
  phrasePatternOnly,
  phrasesToPattern,
} from "./phrases";

interface PhraseCase {
  name: string;
  op: string;
  phrases?: string[];
  pattern: string;
  canonical?: string[];
  matches?: { text: string; caseSensitive: boolean; matches: boolean }[];
  expected?: string[] | null;
}

describe("shared phrase fixtures", () => {
  for (const testCase of fixture.cases as PhraseCase[]) {
    test(testCase.name, () => {
      if (testCase.op === "build") {
        const pattern = phrasesToPattern(testCase.phrases ?? []);
        expect(pattern).toBe(testCase.pattern);
        expect(isValidPattern(pattern)).toBe(true);
        expect(patternToPhrases(pattern)).toEqual(testCase.canonical ?? []);
        expect(phrasesToPattern(testCase.canonical ?? [])).toBe(pattern);
        for (const check of testCase.matches ?? []) {
          expect(
            compilePattern(pattern, check.caseSensitive).test(check.text),
          ).toBe(check.matches);
        }
      } else {
        expect(testCase.op).toBe("parse");
        expect(patternToPhrases(testCase.pattern)).toEqual(
          testCase.expected ?? null,
        );
      }
    });
  }
});

describe("phrasePatternOnly", () => {
  test("keeps a pattern built from phrases", () => {
    expect(phrasePatternOnly("\\btrailer\\b|#shorts\\b")).toBe(
      "\\btrailer\\b|#shorts\\b",
    );
  });

  test("reads anything else as no pattern", () => {
    expect(phrasePatternOnly("(ep|episode) ?\\d+")).toBe("");
    expect(phrasePatternOnly(undefined)).toBe("");
    expect(phrasePatternOnly(7)).toBe("");
  });
});
