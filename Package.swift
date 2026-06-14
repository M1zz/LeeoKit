// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LeeoKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17)
    ],
    products: [
        .library(name: "LeeoKit", targets: ["LeeoKit"])
    ],
    targets: [
        .target(name: "LeeoKit"),
        .testTarget(name: "LeeoKitTests", dependencies: ["LeeoKit"])
    ]
)
