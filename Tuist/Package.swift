// swift-tools-version: 5.9
import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: [:]
)
#endif

let package = Package(
    name: "ShapeScript",
    dependencies: [
        .package(path: "../Euclid"),
        .package(path: "../LRUCache"),
        .package(path: "../SVGPath"),
    ]
)
