[![Build](https://github.com/nicklockwood/SVGPath/actions/workflows/build.yml/badge.svg)](https://github.com/nicklockwood/SVGPath/actions/workflows/build.yml)
[![Codecov](https://codecov.io/gh/nicklockwood/SVGPath/graphs/badge.svg)](https://codecov.io/gh/nicklockwood/SVGPath)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20|%20Mac%20|%20tvOS%20|%20Linux%20|%20Wasm-lightgray.svg)]()
[![Swift 5.7](https://img.shields.io/badge/swift-5.7-red.svg?style=flat)](https://developer.apple.com/swift)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://opensource.org/licenses/MIT)
[![Mastodon](https://img.shields.io/badge/mastodon-@nicklockwood@mastodon.social-636dff.svg)](https://mastodon.social/@nicklockwood)

- [Introduction](#introduction)
- [Installation](#installation)
- [Usage](#usage)
- [CoreGraphics Integration](#coregraphics-integration)
- [SwiftUI Integration](#swiftui-integration)
- [Converting Paths to SVG](#converting-paths-to-svg)
- [Cross-Platform Usage](#cross-platform-usage)
- [Credits](#credits)


# Introduction

**SVGPath** is an open-source parser for the SVG path syntax, making it easy to parse, generate and programmatically manipulate paths in this popular format.


# Installation

SVGPath is packaged as a dynamic framework that you can import into your Xcode project. You can install this manually, or by using Swift Package Manager.

**Note:** SVGPath requires Xcode 16+ to build, and runs on iOS 11+ or macOS 10.15+.

To install using Swift Package Manager, add this to the `dependencies:` section in your Package.swift file:

```swift
.package(url: "https://github.com/nicklockwood/SVGPath.git", .upToNextMinor(from: "1.3.0")),
```


# Usage

You can create an instance of **SVGPath** as follows:

```swift
let svgPath = try SVGPath(string: "M150 0 L75 200 L225 200 Z")
```

The SVGPath initializer is a *throwing* function that will throw an `SVGError` if the supplied string is invalid or malformed.

By default, coordinates are stored with inverted Y coordinates internally to match the coordinate system used by Core Graphics on Apple platforms. You can control this behavior using the `options:` parameter:

```swift
let options = SVGPath.ParseOptions(invertYAxis: false)
let svgPath = try SVGPath(string: "M150 0 L75 200 L225 200 Z", options: options)
```


# CoreGraphics Integration

To convert an `SVGPath` to a `CGPath` for rendering with CoreGraphics or `CAShapeLayer`:

```swift
let cgPath = CGPath.from(svgPath)
```

You can also create a `CGPath` directly from an SVG path string:

```swift
let cgPath = try CGPath.from(svgPath: "M150 0 L75 200 L225 200 Z")
```

## Scaling to Fit a Rectangle

Use the optional `in rect` parameter to scale the path to fit within a specific rectangle while maintaining aspect ratio:

```swift
let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
let cgPath = try CGPath.from(svgPath: "M150 0 L75 200 L225 200 Z", in: bounds)
```

This is useful when you need the path to fit a specific size in your UI.


# SwiftUI Integration

To use SVG paths in SwiftUI, create a `Path` directly from an SVG string:

```swift
let path = try Path(svgPath: "M150 0 L75 200 L225 200 Z")
```

Or from an existing `SVGPath` instance:

```swift
let path = Path(svgPath)
```

## Creating Custom Shapes

The `in rect` parameter is particularly useful when implementing custom SwiftUI `Shape` types. The path will be automatically scaled to fit the shape's bounds:

```swift
struct Heart: Shape {
    func path(in rect: CGRect) -> Path {
        try! Path(svgPath: """
        M213.1,6.7c-32.4-14.4-73.7,0-88.1,30.6C110.6,4.9,67.5-9.5,36.9,6.7
        C2.8,22.9-13.4,62.4,13.5,110.9C33.3,145.1,67.5,170.3,125,217
        c59.3-46.7,93.5-71.9,111.5-106.1C263.4,64.2,247.2,22.9,213.1,6.7z
        """, in: rect)
    }
}

struct ContentView: View {
    var body: some View {
        Heart()
            .fill(Color.red)
            .frame(width: 200, height: 200)
    }
}
```

See the **SVGExample** project in this repository for a complete SwiftUI example app.


# Converting Paths to SVG

You can convert a `CGPath` or SwiftUI `Path` to an `SVGPath` as follows:

```swift
let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
let cgPath = CGPath(rect: rect, transform: nil)
let svgPath = SVGPath(cgPath)
```

To convert an `SVGPath` back into a string, use the `string(with:)` method:

```swift
let svgPath = SVGPath(cgPath)
let options = SVGPath.WriteOptions(prettyPrinted: true, wrapWidth: 80, invertYAxis: true)
let string = svgPath.string(with: options)
```


# Cross-Platform Usage

SVGPath runs on all Apple platforms, as well as Linux and WebAssembly/Wasm. CoreGraphics and SwiftUI are not available for Linux and Wasm, but you can still parse SVG paths and work with them directly by iterating over the raw path components using the `commands` property:

```swift
for command in svgPath.commands {
    switch command {
    case .moveTo(let point):
        // Handle move
    case .lineTo(let point):
        // Handle line
    case .quadratic(let control, let point):
        // Handle quadratic curve
    case .cubic(let control1, let control2, let point):
        // Handle cubic curve
    case .arc(let arc):
        // Handle arc
    case .end:
        // Handle close path
    }
}
```

Alternatively, use the `points(withDetail:)` method to convert the entire path to a flat array of points for use with any graphics API:

```swift
let detail = 10 // number of sample points for curved segments
let points = svgPath.points(withDetail: detail)
```


# Credits

The SVGPath library is primarily the work of [Nick Lockwood](https://github.com/nicklockwood).

([Full list of contributors](https://github.com/nicklockwood/SVGPath/graphs/contributors))

