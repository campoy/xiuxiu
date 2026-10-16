// swift-tools-version:5.9
import PackageDescription

// Wraps the prebuilt whisper.cpp XCFramework, vendored in this repo so a clone
// builds with no network access.
//
// Provenance: build-apple/whisper.xcframework from
// https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.2/whisper-v1.9.2-xcframework.zip
// (sha256 af74fed13ea7f2d5ca2a39d9f58ec177713fafd7cab63aef4e27b79f3ceca80b).
// v1.9.2 is the newest release that ships the XCFramework zip (v1.9.3+ are source-only).
let package = Package(
    name: "WhisperFramework",
    platforms: [.iOS(.v17)],
    products: [.library(name: "whisper", targets: ["whisper"])],
    targets: [
        .binaryTarget(
            name: "whisper",
            path: "whisper.xcframework"
        )
    ]
)
