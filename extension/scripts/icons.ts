/*
 * Regenerates icons/ from the logo centered in its square, design/icons/sub-play-centred.svg;
 * the 16 pixel one is sub-play-centred-small.svg, with one large bubble. Needs rsvg-convert
 * (librsvg). The output is committed, so builds don't need it.
 */

import { mkdir, rm } from "node:fs/promises";
import { join } from "node:path";
import { $ } from "bun";

const iconsDir = join(import.meta.dir, "../icons");
const design = join(import.meta.dir, "../../design/icons");
await rm(iconsDir, { recursive: true, force: true });
await mkdir(iconsDir);
for (const size of [16, 32, 48, 128]) {
  const logo = join(
    design,
    size <= 16 ? "sub-play-centred-small.svg" : "sub-play-centred.svg",
  );
  await $`rsvg-convert -w ${size} -h ${size} ${logo} -o ${join(iconsDir, `icon-${size}.png`)}`;
}
console.log(`wrote icons to ${iconsDir}`);
