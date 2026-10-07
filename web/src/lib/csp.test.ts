import { describe, expect, test } from "bun:test";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

function source(path: string): string {
  return readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
}

/* The Content-Security-Policy in vite.config.ts lets the page shell's inline theme script run by hash; an edit to the script must change the hash. SvelteKit adds the hashes of its own scripts at build. */
describe("Content-Security-Policy", () => {
  const shell = source("src/app.html");
  const config = source("vite.config.ts");

  test("allows exactly the page shell's inline scripts", () => {
    const scripts = Array.from(
      shell.matchAll(/<script>([\s\S]*?)<\/script>/g),
      ([, body]) => body,
    );
    expect(scripts.length).toBeGreaterThan(0);
    for (const body of scripts) {
      expect(config).toContain(
        `"sha256-${createHash("sha256").update(body).digest("base64")}"`,
      );
    }
    expect(config.match(/"sha256-/g)).toHaveLength(scripts.length);
    expect(config).not.toContain("unsafe-eval");
    expect(config).not.toMatch(/"script-src": \[[^\]]*"unsafe-inline"/);
  });

  test("comes before anything it governs", () => {
    expect(shell.indexOf("%sveltekit.head%")).toBeLessThan(
      shell.indexOf("<script"),
    );
    expect(shell.indexOf("%sveltekit.head%")).toBeLessThan(
      shell.indexOf("<link"),
    );
  });
});
