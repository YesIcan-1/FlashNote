// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FlashNoteCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FlashNoteCore", targets: ["FlashNoteCore"])
    ],
    targets: [
        .target(name: "FlashNoteCore"),
        .testTarget(name: "FlashNoteCoreTests", dependencies: ["FlashNoteCore"])
    ]
)
