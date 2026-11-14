// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DexPromptender",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "PromptenderKit", targets: ["PromptenderKit"]),
        .executable(name: "DexPromptender", targets: ["DexPromptender"])
    ],
    targets: [
        .target(
            name: "PromptenderKit",
            path: "DexPromptender",
            exclude: [
                "Info.plist",
                "Resources/Assets.xcassets"
            ],
            resources: [
                .process("Resources/DefaultTemplates.json"),
                .process("Resources/PromptingPlaybooks.md"),
                .copy("Resources/Wildcards")
            ]
        ),
        .executableTarget(
            name: "DexPromptender",
            dependencies: ["PromptenderKit"],
            path: "DexPromptenderEntry"
        ),
        .testTarget(
            name: "PromptenderTests",
            dependencies: ["PromptenderKit"],
            path: "Tests/PromptenderTests"
        )
    ]
)
