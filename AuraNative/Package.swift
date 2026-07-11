// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuraNative",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "AuraAI", targets: ["AuraAI"])
    ],
    targets: [
        .executableTarget(
            name: "AuraAI",
            path: "Sources/AuraAI",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "AuraAITests",
            dependencies: ["AuraAI"],
            path: "Tests/AuraAITests"
        )
    ],
    swiftLanguageModes: [.v5]
)
