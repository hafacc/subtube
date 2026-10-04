import { describe, expect, test } from "bun:test";
import { environmentFor } from "./environment";

const agents = {
  macChrome:
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
  macSafari:
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
  macFirefox:
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:143.0) Gecko/20100101 Firefox/143.0",
  windowsEdge:
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0",
  iphone:
    "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
  iphoneChrome:
    "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/141.0.0.0 Mobile/15E148 Safari/604.1",
  androidChrome:
    "Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36",
};

describe("environmentFor", () => {
  test("desktop Chromium browsers get the web app", () => {
    expect(
      environmentFor({ userAgent: agents.macChrome, maxTouchPoints: 0 }),
    ).toEqual({ kind: "chrome" });
    expect(
      environmentFor({ userAgent: agents.windowsEdge, maxTouchPoints: 0 }),
    ).toEqual({ kind: "chrome" });
  });

  test("desktop Safari gets the Mac app page", () => {
    expect(
      environmentFor({ userAgent: agents.macSafari, maxTouchPoints: 0 }),
    ).toEqual({ kind: "safari" });
  });

  test("an iPad asking for the desktop site is still an iPad", () => {
    expect(
      environmentFor({ userAgent: agents.macSafari, maxTouchPoints: 5 }),
    ).toEqual({ kind: "phone", platform: "ipados" });
  });

  test("phones get their app page, whatever the browser", () => {
    expect(
      environmentFor({ userAgent: agents.iphone, maxTouchPoints: 5 }),
    ).toEqual({ kind: "phone", platform: "ios" });
    expect(
      environmentFor({ userAgent: agents.iphoneChrome, maxTouchPoints: 5 }),
    ).toEqual({ kind: "phone", platform: "ios" });
    expect(
      environmentFor({ userAgent: agents.androidChrome, maxTouchPoints: 5 }),
    ).toEqual({ kind: "phone", platform: "android" });
  });

  test("other desktop browsers get the needs-Chrome page", () => {
    expect(
      environmentFor({ userAgent: agents.macFirefox, maxTouchPoints: 0 }),
    ).toEqual({ kind: "other" });
  });
});
