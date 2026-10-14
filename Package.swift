// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "QuotaBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "QuotaBar", targets: ["QuotaBar"]),
        .executable(name: "QuotaBarChecks", targets: ["QuotaBarChecks"])
    ],
    targets: [
        .target(
            name: "QuotaBarCore",
            path: "Sources/QuotaBarCore"
        ),
        .executableTarget(
            name: "QuotaBar",
            dependencies: ["QuotaBarCore"],
            path: "Sources/QuotaBarApp"
        ),
        .executableTarget(
            name: "QuotaBarChecks",
            dependencies: ["QuotaBarCore"],
            path: "Sources/QuotaBarChecks"
        )
    ]
)
