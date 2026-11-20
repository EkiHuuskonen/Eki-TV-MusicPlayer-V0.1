// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ArkistoSoitin",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ArkistoSoitin", path: "Sources/ArkistoSoitin")
    ]
)
