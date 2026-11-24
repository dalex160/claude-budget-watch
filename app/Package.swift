// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BudgetGuard",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BudgetGuardCore", targets: ["BudgetGuardCore"]),
        .executable(name: "BudgetGuardApp", targets: ["BudgetGuardApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "BudgetGuardCore"),
        .executableTarget(
            name: "BudgetGuardApp",
            dependencies: [
                "BudgetGuardCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(
            name: "BudgetGuardCoreTests",
            dependencies: ["BudgetGuardCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
