/*
 * Regenerates the site's icons in public/ from the logo. logo.svg, shown beside the
 * name, is design/icons/sub-play.svg (the hull centred, the tower above the line);
 * the icons, which stand alone, are design/icons/sub-play-centred.svg (all of it centred).
 * Needs rsvg-convert (librsvg) and ImageMagick's magick. The output is committed,
 * so builds don't need either.
 */

import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { $ } from "bun";

const publicDir = join(import.meta.dir, "../public");
const logo = await readFile(
  join(import.meta.dir, "../../design/icons/sub-play.svg"),
  "utf8",
);
await writeFile(join(publicDir, "logo.svg"), logo);
const svgPath = join(publicDir, "icon.svg");
await writeFile(
  svgPath,
  await readFile(
    join(import.meta.dir, "../../design/icons/sub-play-centred.svg"),
    "utf8",
  ),
);

for (const size of [192, 512]) {
  await $`rsvg-convert -w ${size} -h ${size} ${svgPath} -o ${join(publicDir, `icon-${size}.png`)}`;
}
await $`rsvg-convert -w 32 -h 32 ${svgPath} -o ${join(publicDir, "favicon-32.png")}`;
// iOS fills transparency with black, so the touch icon gets a white square
const touchMark = join(publicDir, "touch-mark.png");
await $`rsvg-convert -w 148 -h 148 ${svgPath} -o ${touchMark}`;
await $`magick -size 180x180 xc:white ${touchMark} -gravity center -composite ${join(publicDir, "apple-touch-icon.png")}`;
await $`rm ${touchMark}`;
console.log(`wrote icons to ${publicDir}`);
