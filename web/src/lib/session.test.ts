import { afterAll, beforeEach, describe, expect, test } from "bun:test";

/* The extension, Google and local storage, faked before the session's modules load. */
const kept = new Map<string, string>();
const messages: {
  type: string;
  interactive?: boolean;
  fresh?: boolean;
  loginHint?: string;
}[] = [];
let signedInAs = "A";
let tokenAnswer: (message: { interactive?: boolean }) => unknown = () => ({
  accessToken: `token-${signedInAs}`,
  expiresIn: 3600,
});
let extensionAnswers = true;
let driveFiles: { id: string; name: string; modifiedTime: string }[] = [];

const realFetch = globalThis.fetch;
afterAll(() => {
  globalThis.fetch = realFetch;
  delete (globalThis as { localStorage?: unknown }).localStorage;
  delete (globalThis as { chrome?: unknown }).chrome;
});

(globalThis as { localStorage?: unknown }).localStorage = {
  getItem: (key: string) => kept.get(key) ?? null,
  setItem: (key: string, value: string) => void kept.set(key, value),
  removeItem: (key: string) => void kept.delete(key),
};
(globalThis as { chrome?: unknown }).chrome = {
  runtime: {
    sendMessage(
      _extensionId: string,
      message: { type: string; interactive?: boolean },
      callback: (response: unknown) => void,
    ) {
      messages.push(message);
      if (!extensionAnswers && message.type !== "ping") {
        callback(undefined);
      } else if (message.type === "token") {
        callback(tokenAnswer(message));
      } else {
        callback(message.type === "ping" ? { version: "1" } : { ok: true });
      }
    },
  },
};
globalThis.fetch = (async (
  input: string | URL | Request,
  init?: RequestInit,
) => {
  const url = new URL(String(input));
  const token = new Headers(init?.headers).get("Authorization") ?? "";
  const who = token.replace("Bearer token-", "");
  if (url.pathname.endsWith("/youtube/v3/channels")) {
    return Response.json({
      items: [{ id: `UC${who}`, snippet: { title: who, thumbnails: {} } }],
    });
  } else if (url.pathname.endsWith("/drive/v3/about")) {
    return Response.json({
      user: {
        displayName: who,
        emailAddress: `${who}@example.com`,
        permissionId: `g${who}`,
      },
    });
  } else {
    return Response.json({ files: driveFiles });
  }
}) as typeof fetch;

const { Session, setupDoneFor } = await import("./session.svelte");
const { expectAccount, forgetToken, getValidToken, withToken } = await import(
  "./auth"
);
const { TokenExpiredError } = await import("./youtube");
const { recheckPlatform } = await import("./platform");
// an earlier test file may have looked for the extension before it was faked
await recheckPlatform();

beforeEach(() => {
  kept.clear();
  messages.length = 0;
  signedInAs = "A";
  extensionAnswers = true;
  driveFiles = [];
  tokenAnswer = () => ({ accessToken: `token-${signedInAs}`, expiresIn: 3600 });
  forgetToken();
});

describe("Session", () => {
  test("setup done is kept per account: a second account starts setup", async () => {
    const session = new Session();
    expect(await session.signIn()).toBe(true);
    expect(session.account?.channelId).toBe("UCA");
    expect(session.setupDone).toBe(false);
    session.finishSetup();
    expect(session.setupDone).toBe(true);
    await session.signOut();
    expect(session.account).toBeNull();
    expect(setupDoneFor("UCA")).toBe(true);

    signedInAs = "B";
    expect(await session.signIn()).toBe(true);
    expect(session.account?.channelId).toBe("UCB");
    expect(session.setupDone).toBe(false);
    await session.signOut();

    signedInAs = "A";
    expect(await session.signIn()).toBe(true);
    expect(session.setupDone).toBe(true);
    session.store?.close();
  });

  test("the browser-wide mark of earlier versions becomes the stored account's", () => {
    kept.set(
      "subtube.account",
      JSON.stringify({ channelId: "UCA", title: "A", thumbnail: "" }),
    );
    kept.set("subtube.setupDone", "true");
    const session = new Session();
    expect(session.setupDone).toBe(true);
    expect(kept.has("subtube.setupDone")).toBe(false);
    expect(setupDoneFor("UCA")).toBe(true);
    session.store?.close();
  });

  test("sign-out forgets the account even when the extension doesn't answer, and revokes nothing", async () => {
    const session = new Session();
    await session.signIn();
    extensionAnswers = false;
    await session.signOut();
    expect(session.account).toBeNull();
    expect(session.store).toBeNull();
    expect(kept.has("subtube.account")).toBe(false);
    expect(messages.some((message) => message.type === "revoke")).toBe(false);
    expect(messages.at(-1)?.type).toBe("signOut");
  });

  test("deleting the profile withdraws Google's grant", async () => {
    const session = new Session();
    await session.signIn();
    session.finishSetup();
    await session.deleteProfile();
    expect(messages.at(-1)?.type).toBe("revoke");
    expect(session.account).toBeNull();
    expect(setupDoneFor("UCA")).toBe(false);
  });

  test("a sign-in the user calls off shows nothing", async () => {
    const session = new Session();
    tokenAnswer = () => ({
      error: "The user did not approve access.",
      cancelled: true,
    });
    expect(await session.signIn()).toBe(false);
    expect(session.error).toBeNull();
  });

  test("a sign-in that fails shows the one message, never the extension's text", async () => {
    const session = new Session();
    tokenAnswer = () => ({ error: "sign-in state mismatch" });
    expect(await session.signIn()).toBe(false);
    expect(session.error).toBe(
      "Couldn't reach Google. Check your connection and try again.",
    );
  });

  test("a silent renewal names the account and refuses another account's token", async () => {
    const session = new Session();
    await session.signIn();
    forgetToken();
    messages.length = 0;
    expect(await getValidToken()).toBe("token-A");
    expect(messages[0]).toMatchObject({
      type: "token",
      interactive: false,
      loginHint: "A@example.com",
    });
    forgetToken();
    signedInAs = "B";
    await expect(getValidToken()).rejects.toThrow("Sign in again to continue.");
    session.store?.close();
  });
});

describe("withToken", () => {
  test("a request refused after another's renewal runs again with the renewed token", async () => {
    let minted = 0;
    tokenAnswer = () => {
      minted += 1;
      return { accessToken: `token-${minted}`, expiresIn: 3600 };
    };
    expectAccount(null);
    const refused = await getValidToken();
    let refuseLate: () => void = () => undefined;
    const held = new Promise<void>((resolve) => {
      refuseLate = resolve;
    });
    const late = withToken(async (token) => {
      if (token === refused) {
        await held;
        throw new TokenExpiredError();
      } else {
        return token;
      }
    });
    const early = await withToken(async (token) => {
      if (token === refused) {
        throw new TokenExpiredError();
      } else {
        return token;
      }
    });
    expect(early).toBe("token-2");
    refuseLate();
    expect(await late).toBe("token-2");
    expect(minted).toBe(2);
  });
});
