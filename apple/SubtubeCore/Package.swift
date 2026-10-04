// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SubtubeCore",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [
    .library(name: "SubtubeCore", targets: ["SubtubeCore"])
  ],
  targets: [
    .target(name: "SubtubeCore"),
    .testTarget(name: "SubtubeCoreTests", dependencies: ["SubtubeCore"]),
  ]
)
