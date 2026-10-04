import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import Ajv2020 from "ajv/dist/2020";
import mergeFixture from "../../../shared/fixtures/merge.json";
import pruneFixture from "../../../shared/fixtures/prune.json";
import schema from "../../../shared/schema/device-file.schema.json";
import {
  channelsFor,
  type DeviceFile,
  defaultFilter,
  deletedElsewhere,
  deviceIdFromName,
  followedIds,
  hasProfile,
  mergeDeviceFiles,
  parseDeviceFile,
  pruneDeviceFile,
  sanitizeDeviceFile,
  savedFilter,
  WATCHED_RETENTION_MS,
} from "./sync-merge";
import type { ChannelFilter } from "./types";

const deviceFilesDir = new URL(
  "../../../shared/fixtures/device-files/",
  import.meta.url,
);

const subscription = { channelId: "UCone", title: "One", thumbnail: "one.jpg" };

function filter(overrides: Partial<ChannelFilter>): ChannelFilter {
  return { ...defaultFilter(), ...overrides };
}

describe("mergeDeviceFiles", () => {
  test("keeps the newest entry per key across devices", () => {
    const laptop: DeviceFile = {
      version: 1,
      channels: { UCone: { at: 5, filter: filter({ regex: "laptop" }) } },
      watched: { a: { at: 1, watched: true }, b: { at: 9, watched: true } },
    };
    const phone: DeviceFile = {
      version: 1,
      channels: { UCone: { at: 7, filter: filter({ regex: "phone" }) } },
      watched: { a: { at: 3, watched: false } },
    };
    const merged = mergeDeviceFiles([
      { deviceId: "laptop", file: laptop },
      { deviceId: "phone", file: phone },
    ]);
    expect(merged.channels.UCone.filter.regex).toBe("phone");
    expect(merged.watched).toEqual({
      a: { at: 3, watched: false },
      b: { at: 9, watched: true },
    });
  });
});

describe("parseDeviceFile", () => {
  test("reads an unknown version as nothing", () => {
    expect(parseDeviceFile({ version: 2, channels: { x: 1 } })).toBeNull();
    expect(parseDeviceFile(null)).toBeNull();
  });
});

describe("hasProfile", () => {
  test("an empty folder is an account not set up yet", () => {
    expect(hasProfile([])).toBe(false);
  });

  test("any device's file means the account is set up", () => {
    expect(hasProfile(["device-abc.json"])).toBe(true);
    expect(hasProfile(["notes.txt", "device-A_b-9.json"])).toBe(true);
  });

  test("other files don't count", () => {
    expect(hasProfile(["device-.json", "device-abc.json.bak", "x.json"])).toBe(
      false,
    );
  });
});

describe("deletedElsewhere", () => {
  const own = "device-me.json";

  test("a device that never uploaded has nothing to miss", () => {
    expect(deletedElsewhere(false, [], own)).toBe(false);
    expect(deletedElsewhere(false, ["device-other.json"], own)).toBe(false);
  });

  test("an uploaded file still listed is not a delete", () => {
    expect(deletedElsewhere(true, ["device-other.json", own], own)).toBe(false);
  });

  test("an uploaded file gone from the listing is a delete", () => {
    expect(deletedElsewhere(true, [], own)).toBe(true);
    expect(deletedElsewhere(true, ["device-other.json"], own)).toBe(true);
  });
});

describe("deviceIdFromName", () => {
  test("takes the id from a device file name and nothing else", () => {
    expect(deviceIdFromName("device-1f2e-ab.json")).toBe("1f2e-ab");
    expect(deviceIdFromName("settings.json")).toBeNull();
    expect(deviceIdFromName("device-.json")).toBeNull();
  });
});

describe("pruneDeviceFile", () => {
  test("drops watched marks past retention", () => {
    const now = WATCHED_RETENTION_MS + 100;
    const file: DeviceFile = {
      version: 1,
      channels: {},
      watched: {
        old: { at: 50, watched: true },
        kept: { at: 200, watched: true },
      },
    };
    expect(Object.keys(pruneDeviceFile(file, now).watched)).toEqual(["kept"]);
  });
});

describe("channelsFor", () => {
  test("defaults new subscriptions and takes identity from YouTube", () => {
    const merged: DeviceFile = {
      version: 1,
      channels: { UCone: { at: 1, filter: filter({ regex: "x" }) } },
      watched: {},
    };
    const channels = channelsFor(merged, [
      subscription,
      { channelId: "UCtwo", title: "Two", thumbnail: "two.jpg" },
    ]);
    expect(channels.get("UCone")).toMatchObject({
      title: "One",
      thumbnail: "one.jpg",
      filter: { regex: "x" },
    });
    expect(channels.get("UCtwo")?.filter).toEqual(defaultFilter());
  });

  test("adds followed channels with looked-up identity, leaves unsubscribed ones out", () => {
    const merged: DeviceFile = {
      version: 1,
      channels: {
        UCgone: { at: 1, filter: filter({}) },
        UCfollow: { at: 1, filter: filter({ followed: true }) },
        UCunknown: { at: 1, filter: filter({ followed: true }) },
      },
      watched: {},
    };
    const channels = channelsFor(
      merged,
      [],
      new Map([
        [
          "UCfollow",
          { channelId: "UCfollow", title: "Follow", thumbnail: "f.jpg" },
        ],
      ]),
    );
    expect(Array.from(channels.keys())).toEqual(["UCfollow", "UCunknown"]);
    expect(channels.get("UCfollow")?.title).toBe("Follow");
    expect(channels.get("UCunknown")?.title).toBe("UCunknown");
    expect(followedIds(merged)).toEqual(["UCfollow", "UCunknown"]);
  });
});

describe("savedFilter", () => {
  test("drops identity and keeps unknown fields", () => {
    const saved = savedFilter({
      ...defaultFilter(),
      channelId: "UC1",
      title: "Chan",
      thumbnail: "x",
      futureField: { nested: true },
    });
    expect(saved).toEqual({
      ...defaultFilter(),
      futureField: { nested: true },
    });
  });
});

describe("written device files match the shared schema", () => {
  const ajv = new Ajv2020({ strict: false });
  const validate = ajv.compile(schema);

  test("a sanitized file with identity fields validates", () => {
    const file = sanitizeDeviceFile({
      version: 1,
      channels: {
        UC1: {
          at: 1,
          filter: filter({ channelId: "UC1", title: "Chan", thumbnail: "" }),
        },
      },
      watched: { v1: { at: 2, watched: true } },
    });
    expect(validate(file)).toBe(true);
  });

  for (const name of readdirSync(deviceFilesDir)) {
    test(`example ${name}`, () => {
      const content = JSON.parse(
        readFileSync(new URL(name, deviceFilesDir), "utf8"),
      );
      expect(validate(content)).toBe(name.startsWith("valid-"));
    });
  }
});

describe("shared merge fixtures", () => {
  for (const testCase of mergeFixture.cases) {
    test(testCase.name, () => {
      const sources = testCase.files.flatMap(({ deviceId, content }) => {
        const file = parseDeviceFile(content);
        return file ? [{ deviceId, file }] : [];
      });
      expect(mergeDeviceFiles(sources)).toEqual(
        testCase.expected as unknown as DeviceFile,
      );
    });
  }
});

describe("shared prune fixtures", () => {
  for (const testCase of pruneFixture.cases) {
    test(testCase.name, () => {
      const file = parseDeviceFile(testCase.file);
      expect(file && pruneDeviceFile(file, testCase.now)).toEqual(
        testCase.expected as unknown as DeviceFile,
      );
    });
  }
});
