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
| `fixtures/merge.json` | every device's raw file → the merged view of filters, watched marks and settings (incl. tie rule, malformed input, unknown fields, `seen` travelling with its entry without ordering it, and two devices filling one group) |
| `fixtures/settings.json` | the merged `settings` map → the synced settings a client acts on, with their defaults |
| `fixtures/prune.json` | a device's own watched entries: `seen` set after a full load, and entries neither saved nor loaded for 30 days dropped before a write |
| `fixtures/shorts.json` | classifying uploads as Shorts from the `UUSH` list; a channel with no list has none, and a probe is asked only when the list couldn't be read |
| `fixtures/setup-start.json` | setup's starting point, applied channel by channel: the record a device keeps, and what each fetch marks and leaves pending |
| `fixtures/feed-order.json` | the feed's orders: latest (the `newest` value), shortest, title (the case-insensitive compare every list uses), and the seeded random one |
| `fixtures/feed-chips.json` | the fifteen topics (YouTube category ids) and their labels, the chip row and what its chips cycle through, the topic chips' order, what the time, topic and group chips keep, the filter editor's topic order, and what setup's starting point marks watched |
| `fixtures/channel-order.json` | the orders of channel lists: latest (newest video first), name, unwatched (most unwatched first) |
| `fixtures/channel-chips.json` | the channel list's chip row: the topic chips it offers and their order, and which channels its time, topic and group chips keep |
| `fixtures/groups.json` | groups of channels: what a name is, which groups exist and their chip order, what a row's title shows while chips are selected, the edits (add or remove a channel, rename incl. merging, delete, the selected chips following), and the editor, which writes only on "Save" |
| `fixtures/player.json` | the one player: what plays after an item ends (the next unwatched item of the list it was started from; nothing with auto-play off or a list started in Watched), what the end does to a large, minimized or card player (play the next where it is; with nothing next the large and the minimized player stay on the ended item and the card player closes), and the minimized player's size |
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

## Setup's starting point

Setup ends with "Where to start": all time, past day or past week; the last
two mark older items watched. One load can't be trusted to do that, since a
channel may fail or be skipped (the daily limit), so it is done channel by
channel. `fixtures/setup-start.json` is the rule and its edges; in short:

1. When setup finishes with `day` or `week`, the device keeps a record
   locally, per account, never in Drive: `start` (the choice), `cutoff` (that
   moment, epoch milliseconds) and `channels` (the ids of the channels that
   were on). Nothing is kept for `all`, or with no channel on.
2. Each time a channel's items are fetched in full, and the channel is in
   the record, its items published before `cutoff` less the span are marked
   watched (those not marked already, in one save), and the channel leaves
   the record. The span counts back from `cutoff`, not from the fetch.
3. A channel that failed or was skipped stays in the record for a later
   fetch. A channel turned on after setup is never in it. Once the record
   has no channel left it is dropped.

## Lists YouTube can't find

A channel's lists are asked for by id (`UU…` uploads, `UUSH…` Shorts).
YouTube answers 404 `playlistNotFound` for a list that doesn't exist, which
is how it answers for a channel with nothing in it:

- the **uploads** list not found: the channel has no uploads. It is fetched,
  with no items, and is not a failed channel;
- the **Shorts** list not found: the channel has no Shorts, and nothing is
  probed (`fixtures/shorts.json`). Only a Shorts list that couldn't be read —
  a server error (5xx) again after one retry, or no answer — is probed
  instead, where the platform has a probe.

## Groups of channels

A group is only a name. Each channel's saved filter may carry
`groups: string[]`, the names of the groups that channel is in, beside its
other fields; it is written and merged with the filter, so no channel id is
stored anywhere new and two devices that put different channels in one group
both do. `fixtures/groups.json` is the rule and its edges; in short:

1. A name is typed text with Unicode white space removed from both ends,
   1 to 24 code points; two names are one group only when identical.
2. A group exists while at least one **listed** channel's filter names it
   (on or off). A filter kept for a channel no longer listed does not make
   a group exist, but rename and delete rewrite it too.
3. Rename rewrites the name on every saved filter that has it, in one save,
   and in the two selection settings; renaming to another group's name
   merges the two. Delete removes it from all of those. Taking the last
   listed channel out of a group deletes it.
4. `groupChips` (the feed's row) and `channelGroupChips` (the channel
   list's row) hold the selected names, apart from each other. A selected
   name that is no existing group is ignored everywhere and left in the
   setting.
5. The feed keeps an item when its channel is in any selected group, and
   the topic, time and watched chips apply on top
   (`fixtures/feed-chips.json`, `groupFilter`). The channel list shows the
   channels in any selected group, off ones too, and its time and topic
   chips apply on top (`fixtures/channel-chips.json`). A channel's own page
   has no group chips and is not filtered by them.
6. While a row has an existing group or a topic selected, its title is
   those names, with "Edit group" (one group selected) and "Clear" buttons
   after it; the rows have no chip that clears topics any more.
7. The group editor writes nothing until "Save" (one save for the name and
   every channel change; disabled without a name and a channel switched
   on; Enter in the name field does nothing); "Cancel" and leaving
   discard. "Delete group" deletes at once. Where a platform's channel
   list already has a search field, the editor's channel list gets the
   same one; otherwise none.

A device that was away while a group was renamed, and then puts a channel in
it under the old name, brings the old name back with that one channel.

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
