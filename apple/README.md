# subtube for macOS and iOS

SwiftUI apps for macOS 15+ and iOS 18+ that share the `SubtubeCore` Swift package.

Open `SubTube.xcodeproj` in Xcode and run the `SubTube` scheme on a Mac, iPhone
or iPad destination.
Sign-in needs a Google iOS OAuth client id in `GoogleClient.iOSClientID`
(`SubtubeCore/Sources/SubtubeCore/Auth.swift`).

Tests: `cd SubtubeCore && swift test`.
