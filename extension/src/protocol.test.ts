import { describe, expect, test } from "bun:test";
import devManifest from "../manifest.dev.json";
import manifest from "../manifest.json";
import {
  EXTENSION_ORIGIN_MATCHES,
  isAllowedOrigin,
  silentFailureNeedsUser,
} from "./protocol";

describe("protocol", () => {
  test("the dev manifest lets in exactly the pages the protocol names", () => {
    expect(devManifest.externally_connectable.matches).toEqual([
      ...EXTENSION_ORIGIN_MATCHES,
    ]);
  });

  test("the store manifest lets in only the protocol's https pages", () => {
    expect(manifest.externally_connectable.matches).toEqual(
      EXTENSION_ORIGIN_MATCHES.filter((match) => match.startsWith("https:")),
    );
    expect(manifest).not.toHaveProperty("key");
  });

  test("isAllowedOrigin lets in what the given match patterns name, on any port", () => {
    const matches = [...EXTENSION_ORIGIN_MATCHES];
    expect(isAllowedOrigin("https://subtube.hafa.cc", matches)).toBe(true);
    expect(isAllowedOrigin("http://localhost:3000", matches)).toBe(true);
    expect(isAllowedOrigin("http://localhost", matches)).toBe(true);
    expect(isAllowedOrigin("https://localhost:3000", matches)).toBe(false);
    expect(isAllowedOrigin("https://evil.example", matches)).toBe(false);
    expect(
      isAllowedOrigin("https://subtube.hafa.cc.evil.example", matches),
    ).toBe(false);
    expect(isAllowedOrigin("not an origin", matches)).toBe(false);
    expect(isAllowedOrigin(undefined, matches)).toBe(false);
  });

  test("silentFailureNeedsUser is true only when Google or Chrome wanted the user", () => {
    expect(silentFailureNeedsUser("login_required")).toBe(true);
    expect(silentFailureNeedsUser("interaction_required")).toBe(true);
    expect(silentFailureNeedsUser("consent_required")).toBe(true);
    expect(silentFailureNeedsUser("User interaction required.")).toBe(true);
    expect(
      silentFailureNeedsUser("Authorization page could not be loaded."),
    ).toBe(false);
    expect(silentFailureNeedsUser("sign-in returned no response")).toBe(false);
  });
});
