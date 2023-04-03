[![Build](https://github.com/nicklockwood/ShapeScript/actions/workflows/build.yml/badge.svg)](https://github.com/nicklockwood/ShapeScript/actions/workflows/build.yml)
[![Codecov](https://codecov.io/gh/nicklockwood/ShapeScript/graphs/badge.svg)](https://codecov.io/gh/nicklockwood/ShapeScript)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20|%20Mac%20|%20tvOS%20|%20Linux-lightgray.svg)]()
[![Swift 5.1](https://img.shields.io/badge/swift-5.1-red.svg?style=flat)](https://developer.apple.com/swift)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://opensource.org/licenses/MIT)
[![Mastodon](https://img.shields.io/badge/mastodon-@nicklockwood@mastodon.social-636dff.svg)](https://mastodon.social/@nicklockwood)

![Screenshot](images/Screenshot.jpg?raw=true)

- [Introduction](#introduction)
- [Installation](#installation)
- [Usage](#usage)
- [Contributing](#contributing)
- [Credits](#credits)

# Introduction

ShapeScript is a hybrid scripting/markup language for creating and manipulating 3D geometry using techniques such as extruding or "lathing" 2D paths to create solid 3D shapes, and CSG (Constructive Solid Geometry) to combine or subtract those shapes from one another.

ShapeScript is also the scripting language used for the ShapeScript [Mac](https://apps.apple.com/app/id1441135869) and [iOS](https://apps.apple.com/app/id1606439346) apps.

ShapeScript is implemented on top of [Euclid](https://github.com/nicklockwood/Euclid), a cross-platform 3D modeling library written in Swift. Anything you can construct using ShapeScript can be replicated programmatically in Swift using Euclid.

If you would like to support the development of Euclid and the ShapeScript language, please consider buying a copy of ShapeScript for Mac or iOS (the apps themselves are free, but there is an in-app purchase to unlock some features).

[<img alt="Mac App Store" height="115" src="images/mac-app-store-badge.png?raw=true"/>](https://apps.apple.com/app/id1441135869)
[<img alt="App Store" height="115" src="images/app-store-badge.png?raw=true"/>](https://apps.apple.com/app/id1606439346)

# Installation

ShapeScript is packaged as a Swift framework, which itself depends on the [Euclid](https://github.com/nicklockwood/Euclid) framework, a copy of which is included in this repository.

To install the ShapeScript framework using CocoaPods, add the following to your Podfile:

```ruby
pod 'ShapeScript', '~> 1.6'
```

To install using Carthage, add this to your Cartfile:

```ogdl
github "nicklockwood/ShapeScript" ~> 1.6
```

To install using Swift Package Manager, add this to the `dependencies:` section in your Package.swift file:

```swift
.package(url: "https://github.com/nicklockwood/ShapeScript.git", .upToNextMinor(from: "1.6.0")),
```

The repository also includes ShapeScript Viewer apps for iOS and macOS, a cut-down version of the full ShapeScript apps available on the [Mac](https://apps.apple.com/app/id1441135869) and [iOS](https://apps.apple.com/app/id1606439346) app stores. It is not currently possible to install or run these apps using CocoaPods, Carthage or Swift Package Manager but you can run them by opening the included Xcode project and selecting the `Viewer (Mac)` or `Viewer (iOS)` schemes.

**Note:** ShapeScript Viewer requires Xcode 11+ to build, and runs on macOS 10.13+ or iOS 14+.

# Usage

The best way to try out ShapeScript is to run the ShapeScript Viewer app (see above).

Once you have opened the app, you can create a new ShapeScript document from the File menu, or open one of the example projects from the Help menu.

ShapeScript does not include a built-in editor. Instead, after opening a shape file in the ShapeScript Viewer, you can select Open in Editor (Cmd-E) from the Edit menu to open the source file in a text editor of your choice.

The ShapeScript Viewer will track changes to the source file and update in real-time as you edit it.

For more information, check out the [help section](docs/index.md).

# Contributing

Feel free to open an issue in Github if you have questions about how to use the library, or think you may have found a bug.

If you wish to contribute improvements to the documentation or the code itself, that's great! But please read the [CONTRIBUTING.md](CONTRIBUTING.md) file before submitting a pull request.

# Credits

The ShapeScript framework and viewer are primarily the work of [Nick Lockwood](https://github.com/nicklockwood).
