# subtube

[![build](https://github.com/hafacc/subtube/actions/workflows/build.yml/badge.svg)](https://github.com/hafacc/subtube/actions/workflows/build.yml)

A personal, subscription-driven YouTube reader: per-channel filters,
self-tracked watched state, and playback through the official embed. Live at
[subtube.hafa.cc](https://subtube.hafa.cc/).

| Directory | What | Open with |
| --- | --- | --- |
| `web/` | the web app (Svelte) | `cd web && bun install && bun run dev` |
| `extension/` | the Chrome extension the web app needs | `cd extension && bun install && bun run build` |
| `apple/` | macOS and iOS apps (SwiftUI) | `apple/SubTube.xcodeproj` in Xcode |
| `android/` | Android app (Compose) | `android/` in Android Studio |
| `shared/` | Drive file schema, filter patterns and test fixtures every client passes | `cd shared && bun install && bun run check` |
| `design/` | the logo, its shortlisted alternatives and animated versions | |
