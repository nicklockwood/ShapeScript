// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ContextMenu",
    platforms: [
        .iOS(.v14),
        .macCatalyst(.v14),
    ],
    products: [
        .library(name: "ContextMenu", targets: ["ContextMenu"]),
    ],
    targets: [
        .target(name: "ContextMenu", path: "Sources"),
        .testTarget(
            name: "ContextMenuTests",
            dependencies: ["ContextMenu"],
            path: "Tests"
        ),
    ]
)
