// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TutoringCore",
    defaultLocalization: "ru",
    // macOS указан только чтобы гонять тесты ядра из терминала без симулятора.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TutoringCore", targets: ["TutoringCore"])
    ],
    targets: [
        .target(name: "TutoringCore"),
        .testTarget(name: "TutoringCoreTests", dependencies: ["TutoringCore"]),
    ]
)
