// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "NoticeDeleteAnimationCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "NoticeDeleteAnimationCore", targets: ["NoticeDeleteAnimationCore"])],
    targets: [
        .target(name: "NoticeDeleteAnimationCore", path: "Sources/Core"),
        .testTarget(name: "CoreTests", dependencies: ["NoticeDeleteAnimationCore"], path: "Tests/CoreTests")
    ],
    swiftLanguageVersions: [.v5]
)
