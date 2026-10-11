# subtube

[![build](https://github.com/hafacc/subtube/actions/workflows/build.yml/badge.svg)](https://github.com/hafacc/subtube/actions/workflows/build.yml)
[![extension](https://img.shields.io/badge/dynamic/json?label=extension&prefix=v&query=%24.version&url=https://raw.githubusercontent.com/hafacc/subtube/main/extension/manifest.json)](https://github.com/hafacc/subtube/releases?q=extension-v)
[![macOS](https://img.shields.io/badge/dynamic/regex?label=macOS&search=MARKETING_VERSION%5C%5Bsdk%3Dmacosx%5C*%5C%5D%20%3D%20%28%5CS%2B%29&replace=v%241&url=https://raw.githubusercontent.com/hafacc/subtube/main/apple/Config/Versions.xcconfig)](https://github.com/hafacc/subtube/tags)
[![iOS](https://img.shields.io/badge/dynamic/regex?label=iOS&search=MARKETING_VERSION%5C%5Bsdk%3Diphone%5C*%5C%5D%20%3D%20%28%5CS%2B%29&replace=v%241&url=https://raw.githubusercontent.com/hafacc/subtube/main/apple/Config/Versions.xcconfig)](https://github.com/hafacc/subtube/tags)
[![android](https://img.shields.io/badge/dynamic/regex?label=android&search=versionName%20%3D%20%22%28%5B%5E%22%5D%2B%29%22&replace=v%241&url=https://raw.githubusercontent.com/hafacc/subtube/main/android/app/build.gradle.kts)](https://github.com/hafacc/subtube/releases?q=android-v)

A personal, subscription-driven YouTube reader: per-channel filters,
self-tracked watched state, and playback through the official embed. Live at
[subtube.hafa.cc](https://subtube.hafa.cc/).

| Directory | What | Open with |
| --- | --- | --- |
| `web/` | the web app (Svelte) | `cd web && bun install && bun dev` |
| `extension/` | the Chrome extension the web app needs | `cd extension && bun install && bun export` |
| `apple/` | macOS and iOS apps (SwiftUI) | `apple/SubTube.xcodeproj` in Xcode |
| `android/` | Android app (Compose) | `android/` in Android Studio |
| `shared/` | Drive file schema, filter patterns and test fixtures every client passes | `cd shared && bun install && bun check` |
| `design/` | the logo, its shortlisted alternatives and animated versions | |
