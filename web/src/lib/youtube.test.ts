import { afterEach, describe, expect, test } from "bun:test";
import {
  fetchShortIds,
  fetchUploads,
  GoogleRequestError,
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

  test("a 5xx on the Shorts list, twice, reads as no Shorts list", async () => {
    const { calls } = answer(backendError);
    expect(await fetchShortIds("UCabc", "token")).toBeNull();
    expect(calls).toEqual(["UUSHabc", "UUSHabc"]);
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

  test("a 5xx on the uploads list is still an error, with no retry", async () => {
    const { calls } = answer(backendError);
    await expect(fetchUploads("UCabc", "Chan", "token")).rejects.toBeInstanceOf(
      GoogleRequestError,
    );
    expect(calls).toEqual(["UUabc"]);
  });
});
