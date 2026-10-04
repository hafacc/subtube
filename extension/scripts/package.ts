/*
 * Builds the Chrome Web Store upload: dist/ zipped without the manifest's
 * `key`, which the store refuses (it assigns the listing's own key and id).
 *
 *   cd extension && bun run package   # → subtube-extension.zip
 */
import { rm } from "node:fs/promises";
import { join } from "node:path";
import { $ } from "bun";

const extensionDir = join(import.meta.dir, "..");
const distDir = join(extensionDir, "dist");
const zipPath = join(extensionDir, "subtube-extension.zip");
const manifestPath = join(distDir, "manifest.json");

await $`bun build.ts`.cwd(extensionDir);
const manifest = (await Bun.file(manifestPath).json()) as Record<
  string,
  unknown
>;
const { key: _developmentKey, ...storeManifest } = manifest;
await rm(zipPath, { force: true });
try {
  await Bun.write(manifestPath, `${JSON.stringify(storeManifest, null, 2)}\n`);
  await $`zip -r -X ${zipPath} .`.cwd(distDir).quiet();
} finally {
  // dist/ stays loadable unpacked under the development id
  await $`bun build.ts`.cwd(extensionDir).quiet();
}
console.log(`packaged ${zipPath} (version ${String(manifest.version)})`);
