/*
 * Regenerates the site's icons in static/ and src/lib/logo-drawing.ts from the logo.
 * logo.svg, shown beside the name, is design/icons/sub-play.svg (fin and body centered,
 * tower and bubbles above the line), and logo-drawing.ts is its shapes, which Logo.svelte
 * draws. The icons, which stand alone, are design/icons/sub-play-centred.svg (all of it
 * centered); the browser tab's, drawn at 16 points, are sub-play-centred-small.svg (one
 * large bubble). Needs rsvg-convert (librsvg) and ImageMagick's magick. The output is
 * committed, so builds don't need either.
 */

import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { $ } from "bun";

const staticDir = join(import.meta.dir, "../static");
const design = join(import.meta.dir, "../../design/icons");
const logo = await readFile(join(design, "sub-play.svg"), "utf8");
await writeFile(join(staticDir, "logo.svg"), logo);

const [hull, triangle] = [...logo.matchAll(/ d="([^"]+)"/g)].map(
  ([, path]) => path,
);
const bubbles = [
  ...logo.matchAll(/cx="([^"]+)" cy="([^"]+)" r="([^"]+)"/g),
].map(([, x, y, radius]) => `[${x}, ${y}, ${radius}]`);
await writeFile(
  join(import.meta.dir, "../src/lib/logo-drawing.ts"),
  `// Written by scripts/icons.ts from design/icons/sub-play.svg; don't edit.

/** The logo's yellow outline: body, tail fin and tower. */
export const HULL =
  "${hull}";

/** The play triangle. */
export const TRIANGLE = "${triangle}";

/** The still bubbles, each [x, y, radius]. */
export const BUBBLES = [${bubbles.join(", ")}];
`,
);
await $`bunx biome format --write ${join(import.meta.dir, "../src/lib/logo-drawing.ts")}`.quiet();

const svgPath = join(staticDir, "icon.svg");
await writeFile(
  svgPath,
  await readFile(join(design, "sub-play-centred.svg"), "utf8"),
);
for (const size of [192, 512]) {
  await $`rsvg-convert -w ${size} -h ${size} ${svgPath} -o ${join(staticDir, `icon-${size}.png`)}`;
}
// iOS fills transparency with black, so the touch icon gets a white square
const touchMark = join(staticDir, "touch-mark.png");
await $`rsvg-convert -w 148 -h 148 ${svgPath} -o ${touchMark}`;
await $`magick -size 180x180 xc:white ${touchMark} -gravity center -composite ${join(staticDir, "apple-touch-icon.png")}`;
await $`rm ${touchMark}`;

const tabPath = join(staticDir, "favicon.svg");
await writeFile(
  tabPath,
  await readFile(join(design, "sub-play-centred-small.svg"), "utf8"),
);
await $`rsvg-convert -w 32 -h 32 ${tabPath} -o ${join(staticDir, "favicon-32.png")}`;
console.log(`wrote icons to ${staticDir}`);
