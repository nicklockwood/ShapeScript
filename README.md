[![Travis](https://travis-ci.org/nicklockwood/ShapeScript.svg)](https://travis-ci.org/nicklockwood/ShapeScript)
[![Platforms](https://img.shields.io/badge/platforms-macOS-lightgray.svg)]()
[![Swift 5](https://img.shields.io/badge/swift-5.0-red.svg?style=flat)](https://developer.apple.com/swift)
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://opensource.org/licenses/MIT)
[![Twitter](https://img.shields.io/badge/twitter-@nicklockwood-blue.svg)](http://twitter.com/nicklockwood)

![Screenshot](Screenshot.jpg?raw=true)

- [Introduction](#introduction)
- [Installation](#installation)
- [Usage](#usage)
- [Contributing](#contributing)
- [Credits](#credits)

# Introduction

ShapeScript is a hybrid scripting/markup language for creating and manipulating 3D geometry using techniques such as extruding or "lathing" 2D paths to create solid 3D shapes, and CSG (Constructive Solid Geometry) to combine or subtract those shapes from one another.

ShapeScript is implemented on top of [Euclid](https://github.com/nicklockwood/Euclid), a cross-platform 3D modeling library written in Swift. Anything you can construct using ShapeScript can be replicated programmatically in Swift using Euclid.

ShapeScript is also the scripting language used for the [ShapeScript App](https://apps.apple.com/app/id1441135869).

If you would like to support the development of Euclid and the ShapeScript language, please consider buying a copy of [ShapeScript](https://apps.apple.com/app/id1441135869) (the app itself is free, but there is an in-app purchase to unlock some features).

# Installation

ShapeScript is packaged as a dynamic framework for macOS, which itself depends on the [Euclid](https://github.com/nicklockwood/Euclid) framework, a copy of which is included in this repository.

To install the ShapeScript framework using CocoaPods, add the following to your Podfile:

```ruby
pod 'ShapeScript', '~> 1.0'
```

To install using Carthage, add this to your Cartfile:

```ogdl
github "nicklockwood/ShapeScript" ~> 1.0
```

To install using Swift Package Manager, add this to the `dependencies:` section in your Package.swift file:

```swift
.package(url: "https://github.com/nicklockwood/ShapeScript.git", .upToNextMinor(from: "1.0.0")),
```

The repository also includes the ShapeScript Viewer application, a cut-down version of the ShapeScript app available on the [Mac App Store](https://apps.apple.com/app/id1441135869). It is not currently possible to install or run this app using CocoaPods, Carthage or Swift Package Manager, however you can run it by opening the included Xcode project and selecting the `ShapeScript Viewer` scheme.

**Note:** ShapeScript requires Xcode 10+ to build, and runs on macOS 10.13+.

# Usage

The best way to try out ShapeScript is to run the ShapeScript Viewer app (see above).

Once you have opened the app, you can create a new ShapeScript document from the File menu, or open one of the example projects from the Help menu.

ShapeScript does not include a built-in editor. Instead, after opening a shape file in the ShapeScript Viewer, you can select Open in Editor (Cmd-E) from the Edit menu to open the source file in a text editor of your choice.

The ShapeScript Viewer will track changes to the source file and update in real-time as you edit it.

For more information, check out the [help section](Help/index.md).

# Contributing

Feel free to open an issue in Github if you have questions about how to use the library, or think you may have found a bug.

If you wish to contribute improvements to the documentation or the code itself, that's great! But please read the [CONTRIBUTING.md](CONTRIBUTING.md) file before submitting a pull request.

# Credits

The ShapeScript framework and viewer are primarily the work of [Nick Lockwood](https://github.com/nicklockwood).
