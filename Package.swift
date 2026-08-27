// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "NetSpeed",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(
            name: "NetSpeed",
            dependencies: [],
            exclude: ["SF-Compact-Display-Medium.otf"]
        )
    ]
)
