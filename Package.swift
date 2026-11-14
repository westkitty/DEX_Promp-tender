// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DexPromptender",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DexPromptender", targets: ["DexPromptender"])
    ],
    targets: [
        .executableTarget(
            name: "DexPromptender",
            path: "DexPromptender",
            exclude: [
                "Info.plist",
                "Resources/Assets.xcassets"
            ],
            resources: [
                .process("Resources/DefaultTemplates.json"),
                .process("Resources/PromptingPlaybooks.md")
            ]
        )
    ]
)
