# subtube for macOS and iOS

SwiftUI apps for macOS 15+ and iOS 18+ that share the `SubtubeCore` Swift package.

Open `subtube.xcodeproj` in Xcode and run `subtube-macOS` or `subtube-iOS`.
Sign-in needs a Google iOS OAuth client id in `GoogleClient.iOSClientID`
(`SubtubeCore/Sources/SubtubeCore/Auth.swift`).

Tests: `cd SubtubeCore && swift test`.
