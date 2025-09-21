// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "ShapeScript",
    platforms: [
        .macOS(.v10_15),
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
            .upToNextMinor(from: "0.8.11")
        ),
        .package(
            url: "https://github.com/nicklockwood/LRUCache.git",
            .upToNextMinor(from: "1.1.2")
        ),
        .package(
            url: "https://github.com/nicklockwood/SVGPath.git",
            .upToNextMinor(from: "1.2.0")
        ),
    ],
    targets: [
        .target(
            name: "ShapeScript",
            dependencies: ["Euclid", "LRUCache", "SVGPath"],
            path: "ShapeScript",
            exclude: ["Info.plist", "ShapeScript.xctestplan"]
        ),
        .executableTarget(
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
