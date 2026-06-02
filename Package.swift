// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Picon",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "Picon", targets: ["Picon"]),
        .executable(name: "PiconCheck", targets: ["PiconCheck"]),
        .library(name: "PiconCore", targets: ["PiconCore"])
    ],
    targets: [
        .target(name: "PiconCore"),
        .executableTarget(
            name: "Picon",
            dependencies: ["PiconCore"]
        ),
        .executableTarget(
            name: "PiconCheck",
            dependencies: ["PiconCore"]
        )
    ]
)
