/*
 * Regenerates icons/ from the logo centred in its square, design/icons/sub-play-centred.svg. Needs rsvg-convert
 * (librsvg). The output is committed, so builds don't need it.
 */

import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { $ } from "bun";

const iconsDir = join(import.meta.dir, "../icons");
const logo = await readFile(
  join(import.meta.dir, "../../design/icons/sub-play-centred.svg"),
  "utf8",
);
await rm(iconsDir, { recursive: true, force: true });
await mkdir(iconsDir);
const svgPath = join(iconsDir, "logo.svg");
await writeFile(svgPath, logo);
for (const size of [16, 32, 48, 128]) {
  await $`rsvg-convert -w ${size} -h ${size} ${svgPath} -o ${join(iconsDir, `icon-${size}.png`)}`;
}
await rm(svgPath);
console.log(`wrote icons to ${iconsDir}`);
