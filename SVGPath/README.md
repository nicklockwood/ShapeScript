[![Build](https://github.com/nicklockwood/SVGPath/actions/workflows/build.yml/badge.svg)](https://github.com/nicklockwood/SVGPath/actions/workflows/build.yml)
[![Codecov](https://codecov.io/gh/nicklockwood/SVGPath/graphs/badge.svg)](https://codecov.io/gh/nicklockwood/SVGPath)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20|%20Mac%20|%20tvOS%20|%20Linux-lightgray.svg)]()
[![Swift 5.1](https://img.shields.io/badge/swift-5.1-red.svg?style=flat)](https://developer.apple.com/swift)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://opensource.org/licenses/MIT)
[![Twitter](https://img.shields.io/badge/twitter-@nicklockwood-blue.svg)](http://twitter.com/nicklockwood)

- [Introduction](#introduction)
- [Installation](#installation)
- [Usage](#usage)
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


# Credits

The SVGPath library is primarily the work of [Nick Lockwood](https://github.com/nicklockwood).

([Full list of contributors](https://github.com/nicklockwood/SVGPath/graphs/contributors))

