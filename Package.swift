// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GlowGoblinPackage",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GlowGoblin", targets: ["GlowGoblin"])
    ],
    targets: [
        .executableTarget(
            name: "GlowGoblin",
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
