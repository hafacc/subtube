import { describe, expect, test } from "bun:test";
import fixture from "../../../shared/fixtures/groups.json";
import {
  chipMarks,
  chipTitle,
  deleteGroup,
  type GroupSelections,
  groupKeptChannels,
  groupName,
  groupNames,
  keptByBoth,
  renameGroup,
  saveGroup,
  selectedGroups,
  setMembers,
} from "./groups";
import { defaultFilter } from "./sync-merge";
import type { ChannelFilter } from "./types";

interface FixtureCase {
  name: string;
  op: string;
  text?: string;
  channels?: Record<string, ChannelFilter>;
  groups?: string[];
  groupChips?: string[];
  topics?: string[];
  topicChips?: string[];
  saved?: Record<string, ChannelFilter>;
  listed?: string[];
  settings?: GroupSelections;
  channelIds?: string[];
  group?: string | null;
  members?: string[];
  member?: boolean;
  from?: string;
  to?: string;
  expected: unknown;
}

const NO_SELECTIONS: GroupSelections = {
  groupChips: [],
  channelGroupChips: [],
};

function result(testCase: FixtureCase): unknown {
  const saved = testCase.saved ?? {};
  const settings = testCase.settings ?? NO_SELECTIONS;
  if (testCase.op === "name") {
    return groupName(testCase.text ?? "");
  } else if (testCase.op === "groups") {
    return groupNames(Object.values(testCase.channels ?? {}));
  } else if (testCase.op === "title") {
    return chipTitle(
      testCase.groups ?? [],
      testCase.groupChips ?? [],
      testCase.topics ?? [],
      testCase.topicChips ?? [],
    );
  } else if (testCase.op === "members") {
    return setMembers(
      saved,
      testCase.listed ?? [],
      settings,
      testCase.channelIds ?? [],
      testCase.group ?? "",
      testCase.member === true,
    );
  } else if (testCase.op === "save") {
    return saveGroup(
      saved,
      testCase.listed ?? [],
      settings,
      testCase.group ?? null,
      testCase.to ?? "",
      testCase.members ?? [],
    );
  } else if (testCase.op === "rename") {
    return renameGroup(saved, settings, testCase.from ?? "", testCase.to ?? "");
  } else if (testCase.op === "delete") {
    return deleteGroup(saved, settings, testCase.group ?? "");
  } else {
    throw new Error(`unknown op ${testCase.op}`);
  }
}

describe("shared group fixtures", () => {
  for (const testCase of fixture.cases as unknown as FixtureCase[]) {
    test(testCase.name, () => {
      expect(result(testCase)).toEqual(testCase.expected);
    });
  }
});

function grouped(...groups: string[]): ChannelFilter {
  return { ...defaultFilter(), groups };
}

describe("groups", () => {
  const filters = new Map([
    ["UCa", grouped("Making")],
    ["UCb", grouped("Making", "Cooking")],
    ["UCc", defaultFilter()],
  ]);

  test("selected groups come in chip order, without names of no group", () => {
    expect(
      selectedGroups(["Cooking", "Making"], ["Making", "Gone", "Cooking"]),
    ).toEqual(["Cooking", "Making"]);
  });

  test("no existing group selected keeps every channel", () => {
    expect(groupKeptChannels(filters, [])).toBeNull();
    expect(groupKeptChannels(filters, ["Gone"])).toBeNull();
  });

  test("a selected group keeps its channels", () => {
    expect(groupKeptChannels(filters, ["Cooking"])).toEqual(new Set(["UCb"]));
    expect(groupKeptChannels(filters, ["Cooking", "Making"])).toEqual(
      new Set(["UCa", "UCb"]),
    );
  });

  test("two kept sets keep what both do", () => {
    expect(keptByBoth(null, null)).toBeNull();
    expect(keptByBoth(new Set(["UCa"]), null)).toEqual(new Set(["UCa"]));
    expect(keptByBoth(null, new Set(["UCb"]))).toEqual(new Set(["UCb"]));
    expect(keptByBoth(new Set(["UCa", "UCb"]), new Set(["UCb"]))).toEqual(
      new Set(["UCb"]),
    );
  });

  test("a save counts only listed channels as members", () => {
    const saved = { UCa: grouped("Making"), UCgone: grouped("Making") };
    const selections = { groupChips: ["Making"], channelGroupChips: [] };
    expect(
      saveGroup(saved, ["UCa"], selections, "Making", "Making", ["UCgone"]),
    ).toEqual({ channels: {}, settings: {} });
    expect(
      saveGroup(saved, ["UCa", "UCb"], selections, "Making", "Workshop", [
        "UCb",
        "UCgone",
      ]),
    ).toEqual({
      channels: {
        UCa: grouped(),
        UCb: grouped("Workshop"),
        UCgone: grouped("Workshop"),
      },
      settings: { groupChips: ["Workshop"] },
    });
    expect(
      saveGroup({}, ["UCa"], NO_SELECTIONS, null, "Making", ["UCa", "UCgone"]),
    ).toEqual({ channels: { UCa: grouped("Making") }, settings: {} });
  });

  test("an edit leaves what it was given untouched", () => {
    const saved = { UCa: grouped("Making") };
    renameGroup(saved, NO_SELECTIONS, "Making", "Workshop");
    setMembers(saved, ["UCa"], NO_SELECTIONS, ["UCa"], "Making", false);
    expect(saved).toEqual({ UCa: grouped("Making") });
  });
});

describe("chipMarks", () => {
  const groups = ["Evenings", "Woodworking"];
  const topics = ["10", "20", "27"];

  test("selected groups, then selected topics, in chip order", () => {
    expect(
      chipMarks(groups, ["Woodworking", "Gone"], topics, ["27", "10"], 4),
    ).toEqual([
      { kind: "group", name: "Woodworking" },
      { kind: "topic", categoryId: "10" },
      { kind: "topic", categoryId: "27" },
    ]);
  });

  test("nothing selected leaves no marks", () => {
    expect(chipMarks(groups, [], topics, [], 2)).toEqual([]);
  });

  test("the last mark counts what doesn't fit", () => {
    expect(chipMarks(groups, groups, topics, ["20"], 2)).toEqual([
      { kind: "group", name: "Evenings" },
      { kind: "more", count: 2 },
    ]);
  });
});
