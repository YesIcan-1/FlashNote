// swift-tools-version: 5.10
import PackageDescription

// Source snapshot of argmaxinc/argmax-oss-swift v1.1.0. Only the two targets
// required by WhisperKit are included, keeping app builds independent of the
// upstream command-line and server dependencies.
let package = Package(
    name: "ArgmaxWhisperKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "WhisperKit", targets: ["WhisperKit"])],
    targets: [
        .target(name: "ArgmaxCore"),
        .target(name: "WhisperKit", dependencies: ["ArgmaxCore"]),
    ]
)
