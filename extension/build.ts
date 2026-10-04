/* Bundles the extension into extension/dist, which Chrome loads unpacked. */
import { cp, rm } from "node:fs/promises";
import { join } from "node:path";

const extensionDir = import.meta.dir;
const distDir = join(extensionDir, "dist");

await rm(distDir, { recursive: true, force: true });
const result = await Bun.build({
  entrypoints: [join(extensionDir, "src/background.ts")],
  outdir: distDir,
  target: "browser",
  format: "esm",
  minify: true,
});
if (!result.success) {
  for (const log of result.logs) {
    console.error(log);
  }
  process.exit(1);
}
await cp(join(extensionDir, "manifest.json"), join(distDir, "manifest.json"));
await cp(join(extensionDir, "icons"), join(distDir, "icons"), {
  recursive: true,
});
console.log(`built ${distDir}`);
