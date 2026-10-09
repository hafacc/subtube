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
  deviceIdFromName,
  editedEntry,
  editedFilter,
  hasProfile,
  markedEntry,
  mergeDeviceFiles,
  mergeOwnCopies,
  parseDeviceFile,
  playedEntry,
  pruneDeviceFile,
  refreshSeen,
  SEEN_REFRESH_MS,
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

describe("parseDeviceFile settings", () => {
  test("a file without settings reads without them, so it is written back as it was", () => {
    const file = parseDeviceFile({ version: 1, channels: {}, watched: {} });
    expect(file && "settings" in file).toBe(false);
  });

  test("keeps well-formed entries and unknown fields, drops the rest", () => {
    const file = parseDeviceFile({
      version: 1,
      settings: {
        feedSort: { at: 3, value: "title", setOn: "tv" },
        autoplay: { at: 3 },
        timeChip: "day",
      },
    });
    expect(file?.settings).toEqual({
      feedSort: { at: 3, value: "title", setOn: "tv" },
    });
  });

  test("a merged view always has settings", () => {
    expect(mergeDeviceFiles([]).settings).toEqual({});
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

describe("editedEntry", () => {
  test("keeps unknown fields beside the edited ones", () => {
    const prior: { at: number; watched: boolean; note?: string } = {
      at: 1,
      watched: false,
      note: "from a newer client",
    };
    expect(editedEntry(prior, { at: 5, watched: true })).toEqual({
      at: 5,
      watched: true,
      note: "from a newer client",
    });
  });

  test("is just the edit when there was no entry", () => {
    expect(editedEntry(undefined, { at: 5, watched: true })).toEqual({
      at: 5,
      watched: true,
    });
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

  test("keeps an old mark seen within retention", () => {
    const now = WATCHED_RETENTION_MS + 100;
    const file: DeviceFile = {
      version: 1,
      channels: {},
      watched: {
        seen: { at: 50, watched: true, seen: 101 },
        unseen: { at: 50, watched: true, seen: 100 },
      },
    };
    expect(Object.keys(pruneDeviceFile(file, now).watched)).toEqual(["seen"]);
  });

  test("returns the same file when nothing is dropped", () => {
    const file: DeviceFile = {
      version: 1,
      channels: {},
      watched: { kept: { at: 200, watched: true } },
    };
    expect(pruneDeviceFile(file, 300)).toBe(file);
  });
});

describe("refreshSeen", () => {
  const now = 10 * SEEN_REFRESH_MS;
  const file: DeviceFile = {
    version: 1,
    channels: {},
    watched: {
      never: { at: 5, watched: true, position: 12 },
      stale: { at: 5, watched: true, seen: now - SEEN_REFRESH_MS },
      fresh: { at: 5, watched: true, seen: now - SEEN_REFRESH_MS + 1 },
      absent: { at: 5, watched: true },
    },
  };

  test("sets seen on loaded entries without a recent one and leaves at alone", () => {
    const refreshed = refreshSeen(
      file,
      new Set(["never", "stale", "fresh", "unknown"]),
      now,
    );
    expect(refreshed.watched).toEqual({
      never: { at: 5, watched: true, position: 12, seen: now },
      stale: { at: 5, watched: true, seen: now },
      fresh: { at: 5, watched: true, seen: now - SEEN_REFRESH_MS + 1 },
      absent: { at: 5, watched: true },
    });
    expect(file.watched.never.seen).toBeUndefined();
  });

  test("returns the same file when nothing needs a new seen", () => {
    expect(refreshSeen(file, new Set(["fresh", "unknown"]), now)).toBe(file);
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

  test("lists no channel that isn't subscribed, whatever its saved filter holds", () => {
    const merged: DeviceFile = {
      version: 1,
      channels: {
        UCgone: { at: 1, filter: filter({}) },
        UCold: { at: 1, filter: filter({ fromOlderVersion: true }) },
      },
      watched: {},
    };
    expect(Array.from(channelsFor(merged, []).keys())).toEqual([]);
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

describe("watched entries", () => {
  const playing = { at: 1, watched: false, position: 40, speed: 2 };

  test("playing saves the position and leaves the video unmarked", () => {
    expect(playedEntry({ at: 1, watched: true }, 5, 40, false)).toEqual({
      at: 5,
      watched: false,
      position: 40,
    });
  });

  test("the player's end marks it watched, unknown fields kept", () => {
    expect(playedEntry(playing, 5, 600, true)).toEqual({
      at: 5,
      watched: true,
      position: 600,
      speed: 2,
    });
  });

  test("a mark keeps the position", () => {
    expect(markedEntry(playing, 5, true)).toEqual({
      at: 5,
      watched: true,
      position: 40,
      speed: 2,
    });
    expect(markedEntry(undefined, 5, true)).toEqual({ at: 5, watched: true });
  });

  test("an unmark drops the position", () => {
    expect(markedEntry(playing, 5, false)).toEqual({
      at: 5,
      watched: false,
      speed: 2,
    });
  });
});

describe("editedFilter", () => {
  const base: ChannelFilter = { enabled: true, regex: "", mode: "include" };

  test("keeps a pattern built from phrases and every other field", () => {
    const filter = {
      ...base,
      regex: "\\btrailer\\b",
      topics: ["10"],
      later: 1,
    };
    expect(editedFilter(filter)).toEqual(filter);
  });

  test("drops a pattern that is not phrases, and identity fields", () => {
    expect(
      editedFilter({ ...base, regex: "(ep|episode) ?\\d+", title: "Chan" }),
    ).toEqual(base);
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

  for (const name of readdirSync(deviceFilesDir).filter((file) =>
    file.startsWith("valid-"),
  )) {
    test(`example ${name} is read and written back unchanged`, () => {
      const content = JSON.parse(
        readFileSync(new URL(name, deviceFilesDir), "utf8"),
      );
      const read = parseDeviceFile(content);
      expect(read).not.toBeNull();
      const written = JSON.parse(
        JSON.stringify(sanitizeDeviceFile(read as DeviceFile)),
      );
      expect(written).toStrictEqual(content);
      expect(validate(written)).toBe(true);
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
      const loaded = "loaded" in testCase ? testCase.loaded : undefined;
      const refreshed =
        file && loaded
          ? refreshSeen(file, new Set<string>(loaded), testCase.now)
          : file;
      expect(refreshed && pruneDeviceFile(refreshed, testCase.now)).toEqual(
        testCase.expected as unknown as DeviceFile,
      );
    });
  }
});

describe("mergeOwnCopies", () => {
  const copy = (watched: DeviceFile["watched"]): DeviceFile => ({
    version: 1,
    channels: {},
    watched,
  });

  test("keeps every key, and of one key the entry saved last", () => {
    const merged = mergeOwnCopies(
      copy({ a: { at: 5, watched: true }, b: { at: 1, watched: false } }),
      copy({ b: { at: 2, watched: true }, c: { at: 3, watched: true } }),
    );
    expect(merged.watched).toEqual({
      a: { at: 5, watched: true },
      b: { at: 2, watched: true },
      c: { at: 3, watched: true },
    });
  });

  test("of two entries saved at once, the one seen in a load last, else the first copy's", () => {
    const merged = mergeOwnCopies(
      copy({
        a: { at: 1, watched: true, seen: 4 },
        b: { at: 1, watched: true, position: 7 },
      }),
      copy({
        a: { at: 1, watched: true, seen: 9 },
        b: { at: 1, watched: true },
      }),
    );
    expect(merged.watched.a.seen).toBe(9);
    expect(merged.watched.b.position).toBe(7);
  });

  test("keeps settings and fields it doesn't know from either copy", () => {
    const merged = mergeOwnCopies(
      { ...copy({}), later: 1 },
      { ...copy({}), settings: { autoplay: { at: 1, value: true } } },
    );
    expect(merged.later).toBe(1);
    expect(merged.settings).toEqual({ autoplay: { at: 1, value: true } });
  });
});
