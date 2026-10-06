# shared

The behaviour every subtube client — web (`web/`), Chrome extension
(`extension/`), Apple (`apple/`), Android (`android/`) — must agree on, written
down as language-neutral data. The clients share no code; they all sign in to
the same Google account and read and write the same files in its Drive app
folder, so they must store and interpret that data identically. Nothing here is
imported at runtime; each client's tests load the fixtures and must pass them.

| Path | What |
| --- | --- |
| `schema/device-file.schema.json` | JSON Schema (2020-12) of `device-<id>.json`, version 1 |
| `patterns/README.md` | the filter pattern language and how to compile it |
| `patterns/meta-regex.txt` | the regex that accepts exactly the valid patterns |
| `fixtures/patterns.json` | valid/invalid patterns, and what valid ones match |
| `fixtures/filters.json` | saved filter + feed item → kept or not (incl. the `topics` gate, and patterns that are not phrases) |
| `fixtures/phrases.json` | typed phrases → filter pattern, and a pattern back to phrases or "not phrases" |
| `fixtures/watch-progress.json` | a watched entry's `position` + the video's length → watched or not, where it resumes, how full its progress bar is; and what a client writes while playing |
| `fixtures/merge.json` | every device's raw file → the merged view of filters, watched marks and settings (incl. tie rule, malformed input, unknown fields, and `seen` travelling with its entry without ordering it) |
| `fixtures/settings.json` | the merged `settings` map → the synced settings a client acts on, with their defaults |
| `fixtures/prune.json` | a device's own watched entries: `seen` set after a full load, and entries neither saved nor loaded for 30 days dropped before a write |
| `fixtures/shorts.json` | classifying uploads as Shorts from the `UUSH` list or a probe |
| `fixtures/feed-order.json` | the feed's orders: latest (the `newest` value), shortest, title (the case-insensitive compare every list uses), and the seeded random one |
| `fixtures/feed-chips.json` | the fifteen topics (YouTube category ids) and their labels, the chip row and what its chips cycle through, the topic chips' order, what the time and topic chips keep, the filter editor's topic order, and what setup's starting point marks watched |
| `fixtures/channel-order.json` | the orders of channel lists: latest (newest video first), name, unwatched (most unwatched first) |
| `fixtures/channel-chips.json` | the channel list's chip row: the topic chips it offers and their order, and which channels its time and topic chips keep |
| `fixtures/device-files/` | example files; `valid-*` pass the schema, `invalid-*` fail it |
| `tools/` | checks for this folder (Bun, plus `swift` and a JDK for the engines) |

Each fixture file is `{ "description": …, "cases": [{ "name": …, … }] }`; the
description states the rule and the field meanings. Fields shown absent mean
unknown (never `null`, except where a description says `null` is a value).

## The rule

Any change to the Drive file format or to what a filter means **starts here**:
change the schema and fixtures (and the pattern spec), run the checks below,
then change every client until its tests pass again. A client never changes
shared behaviour on its own.

## How long watched entries are kept

YouTube's API policies allow keeping what came from the API for 30 days
without refreshing it, so a watched entry lives only while its video keeps
coming back in loads. Each entry has `at` (when it was saved) and an optional
`seen` (when its device last had the video or playlist among the items of a
full load). `fixtures/prune.json` is the rule and its edges; in short, for a
device's **own** file only:

1. After a full load that succeeded, every own entry whose id is among the
   load's items gets `seen` = now, unless its `seen` is less than a day old
   (now - seen < 86400000 ms) or in the future. `at` is not touched.
2. Then, and before every write, an own entry is dropped unless
   now - max(`at`, `seen`) < 30 days (2592000000 ms); a missing or malformed
   `seen` counts as `at`. Exactly 30 days is dropped.

`seen` is not part of merging: `at` alone orders entries, then the device id,
and the winner's `seen` comes with it (`fixtures/merge.json`). A device never
changes another device's file, so a device that is no longer used keeps its
last file in Drive until the profile is deleted.

## Versioning

`version` in a device file changes only for an incompatible change — one an
older reader would misread. Adding an optional field is not one: readers keep
fields they don't know and write them back unchanged, so a newer client's
additions survive an older client's saves. A reader skips any file whose
`version` it doesn't know (including newer ones), and a client that writes a
new version must keep reading the old.

## Loading the fixtures

- **Web** (Bun tests): import by relative path, e.g.
  `import fixture from "../shared/fixtures/filters.json"`; read
  `meta-regex.txt` with `readFileSync(new URL("../shared/patterns/meta-regex.txt", import.meta.url), "utf8")`.
- **Apple** (`SubtubeCore` package tests): resolve from the test file,
  `URL(fileURLWithPath: #filePath)` → up to the repo root → `shared/…`.
- **Android** (`:core` tests): in `core/build.gradle.kts`,
  `tasks.test { systemProperty("subtube.shared", rootProject.file("../shared").absolutePath) }`,
  then `File(System.getProperty("subtube.shared"), "fixtures/filters.json")`.

## Checks

```sh
cd shared && bun install && bun tools/check.ts   # JSON, schema examples, meta regex copies agree
bun shared/tools/cross-engine.ts                 # JS, ICU and Java agree on every pattern
```

`check.ts` uses `ajv` (the one dependency, in `shared/package.json`) to
validate the example device files. `cross-engine.ts` needs `swift` and a JDK
(`JAVA_HOME`, else Android Studio's bundled one); it also runs every pattern
`fixtures/phrases.json` builds.
