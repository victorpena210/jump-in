// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JumpInAudio",
    platforms: [.macOS(.v14)],
    products: [.library(name: "JumpInAudio", targets: ["JumpInAudio"])],
    targets: [
        .target(name: "JumpInAudio", path: "JumpIn/Audio"),
        .testTarget(name: "JumpInAudioTests", dependencies: ["JumpInAudio"], path: "Tests/JumpInAudioTests")
    ]
)
