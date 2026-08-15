// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BotikinKit",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "BotikinKit", targets: ["BotikinKit"])
    ],
    targets: [
        .target(name: "BotikinKit"),
        .testTarget(name: "BotikinKitTests", dependencies: ["BotikinKit"])
    ]
)
