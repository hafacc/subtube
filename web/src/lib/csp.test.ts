import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

/* Each page's Content-Security-Policy lets its inline theme script run by hash; an edit to the script must change the hash. */
describe("Content-Security-Policy", () => {
  for (const page of ["index.html", "privacy.html", "terms.html"]) {
    const html = readFileSync(
      new URL(`../../${page}`, import.meta.url),
      "utf8",
    );
    const policy =
      /http-equiv="Content-Security-Policy"\s+content="([^"]+)"/.exec(
        html,
      )?.[1] ?? "";

    test(`${page} allows exactly its inline scripts`, () => {
      const scripts = Array.from(
        html.matchAll(/<script>([\s\S]*?)<\/script>/g),
        ([, body]) => body,
      );
      const hashes = scripts.map(
        (body) =>
          `'sha256-${createHash("sha256").update(body).digest("base64")}'`,
      );
      expect(scripts.length).toBeGreaterThan(0);
      for (const hash of hashes) {
        expect(policy).toContain(hash);
      }
      expect(policy.match(/'sha256-/g)).toHaveLength(hashes.length);
      expect(policy).not.toContain("'unsafe-eval'");
      expect(policy).not.toMatch(/script-src[^;]*'unsafe-inline'/);
    });

    test(`${page} comes before anything it governs`, () => {
      expect(html.indexOf("Content-Security-Policy")).toBeLessThan(
        html.indexOf("<script"),
      );
      expect(html.indexOf("Content-Security-Policy")).toBeLessThan(
        html.indexOf("<link"),
      );
    });
  }
});
