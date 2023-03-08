[![Build](https://github.com/nicklockwood/SVGPath/actions/workflows/build.yml/badge.svg)](https://github.com/nicklockwood/SVGPath/actions/workflows/build.yml)
[![Codecov](https://codecov.io/gh/nicklockwood/SVGPath/graphs/badge.svg)](https://codecov.io/gh/nicklockwood/SVGPath)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20|%20Mac%20|%20tvOS%20|%20Linux-lightgray.svg)]()
[![Swift 5.1](https://img.shields.io/badge/swift-5.1-red.svg?style=flat)](https://developer.apple.com/swift)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://opensource.org/licenses/MIT)
[![Mastodon](https://img.shields.io/badge/mastodon-@nicklockwood@mastodon.social-636dff.svg)](https://mastodon.social/@nicklockwood)

- [Introduction](#introduction)
- [Installation](#installation)
- [Usage](#usage)
- [Advanced Usage](#advanced-usage)
- [Credits](#credits)


# Introduction

**SVGPath** is an open-source parser for the SVG path syntax, making it easy to create `CGPaths` from this popular format.

SVGPath runs on all Apple platforms, and also Linux (although Linux does not support the CoreGraphics API, so if you need to draw the path you will need to provide your own implementation).


# Installation

SVGPath is packaged as a dynamic framework that you can import into your Xcode project. You can install this manually, or by using Swift Package Manager.

**Note:** SVGPath requires Xcode 10+ to build, and runs on iOS 10+ or macOS 10.12+.

To install using Swift Package Manage, add this to the `dependencies:` section in your Package.swift file:

```swift
.package(url: "https://github.com/nicklockwood/SVGPath.git", .upToNextMinor(from: "1.0.0")),
```


# Usage

You can create an instance of **SVGPath** as follows:

```swift
let svgPath = try SVGPath(string: "M150 0 L75 200 L225 200 Z")
```

Notice that the SVGPath constructor is a *throwing* function. It will throw an `SVGError` if the supplied string is invalid or malformed .

Once you have created an `SVGPath` object, in most cases you'll want to convert this to a `CGPath` for rendering on Apple platforms. To do that you can use:

```swift
let cgPath = CGPath.from(svgPath: svgPath)
```

As a shortcut, you can create the `CGPath` directly from an SVG path string:

```swift
let cgPath = try CGPath.from(svgPath: "M150 0 L75 200 L225 200 Z")
```

Once you have a `CGPath` you can render it on iOS or macOS using a CoreGraphics context or a `CAShapeLayer`.


# Advanced Usage

You can convert a `CGPath` to an `SVGPath` using the `init(cgPath:)` initializer:

```swift
let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
let cgPath = CGPath(rect: rect, transform: nil)
let svgPath = SVGPath(cgPath: cgPath)
```

To convert an `SVGPath` back into a `String`, use the `string(with:)` method. This can be useful for exporting a `CGPath` as an SVG string:

```swift
let svgPath = SVGPath(cgPath: ...)
let options = SVGPath.WriteOptions(prettyPrinted: true, wrapWidth: 80)
let string = svgPath.string(with: options)
```

It's also possible to use `SVGPath` without CoreGraphics. You can iterate over the raw path components using the `commands` property:

```swift
for command in svgPath.commands {
    switch command {
    case .moveTo(let point):
        ...
    case .lineTo(let point):
        ...
    default:
        ...   
    }   
}
```

Alternatively, you can use the `points()` or `getPoints()` methods to convert the entire path to a flar array of points at your preferred level of detail.

These can be used to render the path using simple straight line segments using any graphics API you choose:

```swift
let detail = 10 // number of sample points used to represent curved segments
let points = svgPath.points(withDetail: detail)
```

**NOTE:** coordinates are stored with inverted Y coordinates internally, to match the coordinate system used by Core Graphics on macOS/iOS.


# Credits

The SVGPath library is primarily the work of [Nick Lockwood](https://github.com/nicklockwood).

([Full list of contributors](https://github.com/nicklockwood/SVGPath/graphs/contributors))

