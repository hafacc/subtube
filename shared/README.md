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
| `fixtures/filters.json` | saved filter + feed item → kept or not |
| `fixtures/merge.json` | every device's raw file → the merged view (incl. tie rule, malformed input, unknown fields) |
| `fixtures/prune.json` | dropping watched marks older than a year before a write |
| `fixtures/shorts.json` | classifying uploads as Shorts from the `UUSH` list or a probe |
| `fixtures/feed-order.json` | newest-first order |
| `fixtures/channel-order.json` | the order of channel lists |
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
(`JAVA_HOME`, else Android Studio's bundled one).
