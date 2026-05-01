// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RollHDR",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "RollHDR", targets: ["RollHDR"])
    ],
    targets: [
        .executableTarget(
            name: "RollHDR",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
