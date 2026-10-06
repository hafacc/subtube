import { afterEach, describe, expect, test } from "bun:test";
import {
  DailyLimitError,
  fetchShortIds,
  fetchUploads,
  GoogleRequestError,
  isDailyLimit,
  parseIsoDuration,
  shortsPlaylistId,
  uploadsPlaylistId,
} from "./youtube";

describe("uploadsPlaylistId", () => {
  test("swaps the UC channel prefix for UU", () => {
    expect(uploadsPlaylistId("UCabcdef12345")).toBe("UUabcdef12345");
  });
});

describe("parseIsoDuration", () => {
  test("parses hours, minutes, and seconds", () => {
    expect(parseIsoDuration("PT1H2M3S")).toBe(3723);
    expect(parseIsoDuration("PT45S")).toBe(45);
    expect(parseIsoDuration("PT3M")).toBe(180);
    expect(parseIsoDuration("PT2H")).toBe(7200);
  });

  test("parses a day component", () => {
    expect(parseIsoDuration("P1DT2H")).toBe(93600);
  });

  test("parses a whole-day duration with no time part", () => {
    expect(parseIsoDuration("P1D")).toBe(86400);
    expect(parseIsoDuration("P2D")).toBe(172800);
  });

  test("live/upcoming (P0D) and unparseable input yield 0", () => {
    expect(parseIsoDuration("P0D")).toBe(0);
    expect(parseIsoDuration("")).toBe(0);
    expect(parseIsoDuration("garbage")).toBe(0);
  });
});

describe("shortsPlaylistId", () => {
  test("swaps the UC channel prefix for UUSH", () => {
    expect(shortsPlaylistId("UCabcdef12345")).toBe("UUSHabcdef12345");
  });
});

describe("a Shorts list that fails", () => {
  const realFetch = globalThis.fetch;
  const realError = console.error;

  afterEach(() => {
    globalThis.fetch = realFetch;
    console.error = realError;
  });

  /** Answer each request by its playlist id, counting the requests made. */
  function answer(byPlaylist: (playlistId: string, call: number) => Response): {
    calls: string[];
  } {
    const calls: string[] = [];
    console.error = () => undefined;
    globalThis.fetch = (async (input: RequestInfo | URL) => {
      const playlistId =
        new URL(String(input)).searchParams.get("playlistId") ?? "";
      calls.push(playlistId);
      return byPlaylist(playlistId, calls.length);
    }) as typeof fetch;
    return { calls };
  }

  const backendError = () =>
    new Response('{"error":{"errors":[{"reason":"backendError"}]}}', {
      status: 500,
    });
  const list = (videoIds: string[]) =>
    Response.json({
      items: videoIds.map((videoId) => ({ contentDetails: { videoId } })),
    });

  test("a 5xx on the Shorts list, twice, is a list that couldn't be read", async () => {
    const { calls } = answer(backendError);
    expect(await fetchShortIds("UCabc", "token")).toBe("failed");
    expect(calls).toEqual(["UUSHabc", "UUSHabc"]);
  });

  test("a Shorts list request that gets no answer is a list that couldn't be read", async () => {
    answer(() => {
      throw new TypeError("Failed to fetch");
    });
    expect(await fetchShortIds("UCabc", "token")).toBe("failed");
  });

  test("an uploads list YouTube can't find is a channel with no uploads", async () => {
    const { calls } = answer(
      () =>
        new Response('{"error":{"errors":[{"reason":"playlistNotFound"}]}}', {
          status: 404,
        }),
    );
    expect(await fetchUploads("UCabc", "Chan", "token")).toEqual([]);
    expect(calls).toEqual(["UUabc"]);
  });

  test("a 5xx on the uploads list is still an error", async () => {
    answer(backendError);
    await expect(fetchUploads("UCabc", "Chan", "token")).rejects.toBeInstanceOf(
      GoogleRequestError,
    );
  });

  test("a 5xx on the Shorts list is tried once more", async () => {
    answer((_, call) => (call === 1 ? backendError() : list(["s1"])));
    expect(await fetchShortIds("UCabc", "token")).toEqual(new Set(["s1"]));
  });

  test("a 404 playlistNotFound still reads as no Shorts list, without a retry", async () => {
    const { calls } = answer(
      () =>
        new Response('{"error":{"errors":[{"reason":"playlistNotFound"}]}}', {
          status: 404,
        }),
    );
    expect(await fetchShortIds("UCabc", "token")).toBeNull();
    expect(calls).toHaveLength(1);
  });

  test("another failure on the Shorts list is still an error", async () => {
    answer(() => new Response("{}", { status: 403 }));
    await expect(fetchShortIds("UCabc", "token")).rejects.toBeInstanceOf(
      GoogleRequestError,
    );
  });

  const quotaExceeded = () =>
    new Response(
      '{"error":{"code":403,"errors":[{"domain":"youtube.quota","reason":"quotaExceeded"}]}}',
      { status: 403 },
    );

  test("the daily limit on the Shorts list is the daily limit, asked once", async () => {
    const { calls } = answer(quotaExceeded);
    await expect(fetchShortIds("UCabc", "token")).rejects.toBeInstanceOf(
      DailyLimitError,
    );
    expect(calls).toHaveLength(1);
  });

  test("the daily limit says so in the app's words", async () => {
    answer(quotaExceeded);
    await expect(fetchUploads("UCabc", "Chan", "token")).rejects.toThrow(
      "SubTube has reached YouTube's daily limit. Try again after midnight Pacific time.",
    );
  });

  test("uploads fetched without Shorts marks don't ask for the Shorts list", async () => {
    const { calls } = answer(() =>
      Response.json({
        items: [
          {
            id: "v1",
            snippet: { title: "One", description: "", thumbnails: {} },
            contentDetails: { videoId: "v1", duration: "PT1M" },
          },
        ],
      }),
    );
    const plain = await fetchUploads(
      "UCabc",
      "Chan",
      "token",
      50,
      undefined,
      false,
    );
    expect(plain[0].isShort).toBeUndefined();
    expect(calls).not.toContain("UUSHabc");
    await fetchUploads("UCabc", "Chan", "token", 50);
    expect(calls).toContain("UUSHabc");
  });

  test("a 5xx on the uploads list is still an error, with no retry", async () => {
    const { calls } = answer(backendError);
    await expect(fetchUploads("UCabc", "Chan", "token")).rejects.toBeInstanceOf(
      GoogleRequestError,
    );
    expect(calls).toEqual(["UUabc"]);
  });
});

describe("isDailyLimit", () => {
  const body = (domain: string, reason: string) =>
    JSON.stringify({ error: { code: 403, errors: [{ domain, reason }] } });

  test("a 403 quotaExceeded or dailyLimitExceeded is the daily limit", () => {
    expect(isDailyLimit(403, body("youtube.quota", "quotaExceeded"))).toBe(
      true,
    );
    expect(isDailyLimit(403, body("usageLimits", "dailyLimitExceeded"))).toBe(
      true,
    );
  });

  test("the per-minute limit, another refusal or another status is not", () => {
    expect(isDailyLimit(403, body("usageLimits", "rateLimitExceeded"))).toBe(
      false,
    );
    expect(isDailyLimit(403, body("global", "insufficientPermissions"))).toBe(
      false,
    );
    expect(isDailyLimit(429, body("youtube.quota", "quotaExceeded"))).toBe(
      false,
    );
  });

  test("a body that isn't the error shape is not", () => {
    expect(isDailyLimit(403, "quotaExceeded")).toBe(false);
    expect(isDailyLimit(403, '{"error":{"errors":"quotaExceeded"}}')).toBe(
      false,
    );
    expect(isDailyLimit(403, "null")).toBe(false);
  });
});
