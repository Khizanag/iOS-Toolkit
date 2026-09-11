// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Sample",
    dependencies: [
        .package(url: "https://github.com/example/sample", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "Sample",
            dependencies: [
                .product(name: "Sample", package: "sample"),
            ],
        ),
    ],
)
