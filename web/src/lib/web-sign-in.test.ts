import { afterEach, describe, expect, mock, test } from "bun:test";
import { readFileSync } from "node:fs";
import { oauthClientId } from "./config";
import { deleteEverything, returnedToken, signInUrl } from "./web-sign-in";

describe("signInUrl", () => {
  test("asks Google for the app folder only and names where to return", () => {
    const url = new URL(signInUrl("https://subtube.hafa.cc/delete", "abc"));
    expect(url.origin + url.pathname).toBe(
      "https://accounts.google.com/o/oauth2/v2/auth",
    );
    expect(Object.fromEntries(url.searchParams)).toEqual({
      client_id: oauthClientId,
      redirect_uri: "https://subtube.hafa.cc/delete",
      response_type: "token",
      scope: "https://www.googleapis.com/auth/drive.appdata",
      state: "abc",
      prompt: "select_account",
    });
  });

  test("signs in with the extension's client", () => {
    const background = readFileSync(
      new URL("../../../extension/src/background.ts", import.meta.url),
      "utf8",
    );
    expect(background).toContain(`"${oauthClientId}"`);
  });
});

describe("returnedToken", () => {
  test("reads the token of the sign-in this page started", () => {
    expect(
      returnedToken("#state=abc&access_token=tok&token_type=Bearer", "abc"),
    ).toBe("tok");
  });

  test("refuses a token that answers another sign-in, or none", () => {
    expect(returnedToken("#state=other&access_token=tok", "abc")).toBeNull();
    expect(returnedToken("#state=abc&access_token=tok", null)).toBeNull();
    expect(returnedToken("#access_token=tok", "abc")).toBeNull();
  });

  test("has no token when Google reports a refusal or nothing came back", () => {
    expect(returnedToken("#error=access_denied&state=abc", "abc")).toBeNull();
    expect(returnedToken("", "abc")).toBeNull();
  });
});

describe("deleteEverything", () => {
  const realFetch = globalThis.fetch;
  afterEach(() => {
    globalThis.fetch = realFetch;
  });

  function fakeGoogle(deleteStatus: number): string[] {
    const calls: string[] = [];
    globalThis.fetch = mock(async (input: RequestInfo | URL, init = {}) => {
      const url = String(input);
      const method = init.method ?? "GET";
      calls.push(`${method} ${url.split("?")[0]}`);
      if (method === "DELETE") {
        return new Response(null, { status: deleteStatus });
      } else if (url.includes("/drive/v3/files")) {
        return Response.json({
          files: [
            { id: "one", name: "device-a.json", modifiedTime: "" },
            { id: "two", name: "device-b.json", modifiedTime: "" },
          ],
        });
      } else {
        return new Response(null);
      }
    }) as unknown as typeof fetch;
    return calls;
  }

  test("deletes every file, then withdraws the grant", async () => {
    const calls = fakeGoogle(204);
    await deleteEverything("tok");
    expect(calls).toEqual([
      "GET https://www.googleapis.com/drive/v3/files",
      "DELETE https://www.googleapis.com/drive/v3/files/one",
      "DELETE https://www.googleapis.com/drive/v3/files/two",
      "POST https://oauth2.googleapis.com/revoke",
    ]);
  });

  test("keeps the grant when a file couldn't be deleted, so it can be tried again", async () => {
    const calls = fakeGoogle(500);
    await expect(deleteEverything("tok")).rejects.toThrow();
    expect(calls).not.toContain("POST https://oauth2.googleapis.com/revoke");
  });
});
