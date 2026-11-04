// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "CamapKit", platforms: [.iOS(.v15), .macOS(.v12)],
  products: [
    .library(name: "CamapKit", targets: ["CamapKit"]),
    .executable(name: "CamapMapKitCalibration", targets: ["CamapMapKitCalibration"]),
  ],
  targets: [
    .target(name: "CamapKit", path: "swift/Sources/CamapKit"),
    .executableTarget(name: "CamapMapKitCalibration", dependencies: ["CamapKit"],
      path: "tools/mapkit-calibration", exclude: ["build-macos.sh", "README.md"]),
    .testTarget(
      name: "CamapKitTests", dependencies: ["CamapKit"], path: "swift/Tests/CamapKitTests",
      resources: [.copy("Fixtures")]),
  ])
