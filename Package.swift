// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ShapeScript",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v9),
        .visionOS("1.3"),
    ],
    products: [
        .library(name: "ShapeScript", targets: ["ShapeScript"]),
        .executable(name: "shapescript", targets: ["CLI"]),
        .executable(name: "helpbuilder", targets: ["HelpBuilder"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/nicklockwood/Euclid.git",
            .upToNextMinor(from: "0.10.0")
        ),
        .package(
            url: "https://github.com/nicklockwood/LRUCache.git",
            .upToNextMinor(from: "1.3.0")
        ),
        .package(
            url: "https://github.com/nicklockwood/SVGPath.git",
            .upToNextMinor(from: "1.3.1")
        ),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "ShapeScript",
            dependencies: ["Euclid", "LRUCache", "SVGPath"],
            path: "ShapeScript",
            exclude: ["ShapeScript.xctestplan"]
        ),
        .executableTarget(
            name: "CLI",
            dependencies: [
                "ShapeScript",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Viewer/CLI",
            exclude: ["install.sh"]
        ),
        .executableTarget(
            name: "HelpBuilder",
            dependencies: [
                "ShapeScript",
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "HelpBuilder"
        ),
        .testTarget(
            name: "ShapeScriptTests",
            dependencies: ["ShapeScript"],
            path: "ShapeScriptTests",
            exclude: ["TestShapes/", "Stars1.jpg", "EdgeOfTheGalaxyRegular-OVEa6.otf"]
        ),
    ]
)
