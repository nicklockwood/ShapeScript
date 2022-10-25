// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "ShapeScript",
    platforms: [
        .macOS(.v10_13),
        .iOS(.v11),
        .tvOS(.v11),
    ],
    products: [
        .library(name: "ShapeScript", targets: ["ShapeScript"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/nicklockwood/Euclid.git",
            .upToNextMajor(from: "0.5.30")
        ),
        .package(
            url: "https://github.com/nicklockwood/LRUCache.git",
            .upToNextMinor(from: "1.0.4")
        ),
        .package(
            url: "https://github.com/nicklockwood/SVGPath.git",
            .upToNextMinor(from: "1.1.1")
        ),
    ],
    targets: [
        .target(
            name: "ShapeScript",
            dependencies: ["Euclid", "LRUCache", "SVGPath"],
            path: "ShapeScript"
        ),
        .testTarget(
            name: "ShapeScriptTests",
            dependencies: ["ShapeScript"],
            path: "ShapeScriptTests"
        ),
    ]
)
