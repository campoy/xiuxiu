// swift-tools-version:5.9
import PackageDescription

// Wraps the prebuilt whisper.cpp XCFramework from the official GitHub release.
// v1.9.2 is the newest release that ships the XCFramework zip (v1.9.3+ are source-only).
let package = Package(
    name: "WhisperFramework",
    platforms: [.iOS(.v17)],
    products: [.library(name: "whisper", targets: ["whisper"])],
    targets: [
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.2/whisper-v1.9.2-xcframework.zip",
            checksum: "af74fed13ea7f2d5ca2a39d9f58ec177713fafd7cab63aef4e27b79f3ceca80b"
        )
    ]
)
