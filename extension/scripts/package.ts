/*
 * Builds the Chrome Web Store upload: dist/ zipped with the store's manifest
 * (`store-manifest.ts`: no `key`, no localhost page).
 *
 *   cd extension && bun run package   # → subtube-extension.zip
 */
import { rm } from "node:fs/promises";
import { join } from "node:path";
import { $ } from "bun";
import { type Manifest, storeManifest } from "./store-manifest";

const extensionDir = join(import.meta.dir, "..");
const distDir = join(extensionDir, "dist");
const zipPath = join(extensionDir, "subtube-extension.zip");
const manifestPath = join(distDir, "manifest.json");

await $`bun build.ts`.cwd(extensionDir);
const manifest = (await Bun.file(manifestPath).json()) as Manifest;
await rm(zipPath, { force: true });
try {
  await Bun.write(
    manifestPath,
    `${JSON.stringify(storeManifest(manifest), null, 2)}\n`,
  );
  await $`zip -r -X ${zipPath} .`.cwd(distDir).quiet();
} finally {
  // dist/ stays loadable unpacked under the development id
  await $`bun build.ts`.cwd(extensionDir).quiet();
}
console.log(`packaged ${zipPath} (version ${String(manifest.version)})`);
