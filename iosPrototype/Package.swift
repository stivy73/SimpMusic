// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "StivyPrototype",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [.library(name: "PrototypeCore", targets: ["PrototypeCore"])],
  dependencies: [
    .package(path: "Vendor/YouTubeSDK")
  ],
  targets: [
    .target(name: "PrototypeCore", dependencies: ["YouTubeSDK"], path: "Sources/Core"),
    .testTarget(
      name: "PrototypeCoreTests", dependencies: ["PrototypeCore", "YouTubeSDK"], path: "Tests"),
    .executableTarget(
      name: "NetworkProbe", dependencies: ["YouTubeSDK", "PrototypeCore"], path: "Probe"),
  ]
)
