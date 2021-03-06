## [1.1.3](https://github.com/nicklockwood/ShapeScript/releases/tag/1.1.3) (2021-07-10)

- Fixed assertion failure if a parsing error occurs at the last character in the .shape file
- Fixed bug in Path plane calculation that could result in corrupted extrusion shapes
- Fixed a tessellation bug affecting anti-clockwise polygons

## [1.1.2](https://github.com/nicklockwood/ShapeScript/releases/tag/1.1.2) (2021-07-03)

- Fixed bug where CRLF was treated as two separate linebreaks, resulting in a crash
- Error column indicator is now better aligned when code contains wide characters (e.g. emoji)
- Fixed inverted black/white squares on chessboard example

## [1.1.1](https://github.com/nicklockwood/ShapeScript/releases/tag/1.1.1) (2021-06-26)

- Fixed operator associativity (addition/subtraction were previously right-associative)
- Performing CSG operations on complex geometry no longer causes a stack overflow
- Bumped Euclid version to 0.4.5

## [1.1.0](https://github.com/nicklockwood/ShapeScript/releases/tag/1.1.0) (2021-04-08)

- Added support for background colors and images
- Added debug console
- Improved ShapeScript error handling
- Object names are now included in info popup
- Upgraded project to Swift 5.1
- Bumped Euclid version to 0.4.0
- Fixed Xcode warnings

## [1.0.1](https://github.com/nicklockwood/ShapeScript/releases/tag/1.0.1) (2020-09-03)

- Added iOS and tvOS support to ShapeScript framework (Viewer app is still macOS only)
- Bumped Euclid version to 0.3.5

## [1.0.0](https://github.com/nicklockwood/ShapeScript/releases/tag/1.0.0) (2020-09-02)

- First release
