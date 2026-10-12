import { describe, expect, test } from "bun:test";
import fixture from "../../../shared/fixtures/watch-progress.json";
import {
  isWatchedEntry,
  playlistProgress,
  playlistStart,
  progressFraction,
  resumePosition,
  type WatchEntry,
} from "./progress";

interface ProgressCase {
  name: string;
  op: string;
  entry?: WatchEntry;
  duration?: number;
  videos?: string[];
  index?: number;
  count?: number;
  position?: number;
  expected: boolean | number | null;
}

function result(testCase: ProgressCase): boolean | number | null {
  const { entry, duration } = testCase;
  if (testCase.op === "watched") {
    return isWatchedEntry(entry, duration);
  } else if (testCase.op === "resume") {
    return resumePosition(entry, duration);
  } else if (testCase.op === "bar") {
    return progressFraction(entry, duration);
  } else if (testCase.op === "playlistVideo") {
    return playlistStart(entry, testCase.videos ?? []).index;
  } else if (testCase.op === "playlistPosition") {
    return playlistStart(entry, testCase.videos ?? []).position;
  } else if (testCase.op === "playlistProgress") {
    return playlistProgress(
      testCase.index ?? 0,
      testCase.count ?? 0,
      testCase.position ?? 0,
      duration ?? 0,
    );
  } else {
    throw new Error(`unknown op ${testCase.op}`);
  }
}

describe("shared watch progress fixtures", () => {
  for (const testCase of fixture.cases as ProgressCase[]) {
    test(testCase.name, () => {
      expect(result(testCase)).toBe(testCase.expected);
    });
  }
});
