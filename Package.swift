// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "CamapKit", platforms: [.iOS(.v15), .macOS(.v12)],
  products: [.library(name: "CamapKit", targets: ["CamapKit"])],
  targets: [
    .target(name: "CamapKit", path: "swift/Sources/CamapKit"),
    .testTarget(
      name: "CamapKitTests", dependencies: ["CamapKit"], path: "swift/Tests/CamapKitTests",
      resources: [.copy("Fixtures")]),
  ])
