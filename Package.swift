// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "ShapeScript",
    platforms: [
        .macOS(.v10_14),
        .iOS(.v11),
        .tvOS(.v11),
    ],
    products: [
        .library(name: "ShapeScript", targets: ["ShapeScript"]),
        .executable(name: "shapescript", targets: ["CLI"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/nicklockwood/Euclid.git",
            .upToNextMinor(from: "0.7.1")
        ),
        .package(
            url: "https://github.com/nicklockwood/LRUCache.git",
            .upToNextMinor(from: "1.0.4")
        ),
        .package(
            url: "https://github.com/nicklockwood/SVGPath.git",
            .upToNextMinor(from: "1.1.3")
        ),
    ],
    targets: [
        .target(
            name: "ShapeScript",
            dependencies: ["Euclid", "LRUCache", "SVGPath"],
            path: "ShapeScript"
        ),
        .target(
            name: "CLI",
            dependencies: ["ShapeScript"],
            path: "Viewer/CLI"
        ),
        .testTarget(
            name: "ShapeScriptTests",
            dependencies: ["ShapeScript"],
            path: "ShapeScriptTests"
        ),
    ]
)
