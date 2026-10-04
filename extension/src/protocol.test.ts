import { describe, expect, test } from "bun:test";
import manifest from "../manifest.json";
import { EXTENSION_ORIGIN_MATCHES, isAllowedOrigin } from "./protocol";

describe("protocol", () => {
  test("the manifest lets in exactly the pages the protocol names", () => {
    expect(manifest.externally_connectable.matches).toEqual([
      ...EXTENSION_ORIGIN_MATCHES,
    ]);
  });

  test("isAllowedOrigin mirrors the match patterns", () => {
    expect(isAllowedOrigin("https://subtube.hafa.cc")).toBe(true);
    expect(isAllowedOrigin("http://localhost:3000")).toBe(true);
    expect(isAllowedOrigin("http://localhost")).toBe(true);
    expect(isAllowedOrigin("https://localhost:3000")).toBe(false);
    expect(isAllowedOrigin("https://evil.example")).toBe(false);
    expect(isAllowedOrigin(undefined)).toBe(false);
  });
});
