// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "SVGPath",
    products: [
        .library(name: "SVGPath", targets: ["SVGPath"]),
    ],
    targets: [
        .target(name: "SVGPath", path: "Sources"),
        .testTarget(name: "SVGPathTests", dependencies: ["SVGPath"], path: "Tests"),
    ]
)
