## [1.1.6](https://github.com/nicklockwood/ShapeScript/releases/tag/1.1.6) (2021-08-04)

- Paths are now drawn using polygons strips, which looks sharper and renders more consistently
- Made further improvements to cancelling in-progress rendering when reloading a file
- Bumped Euclid to 0.5.4, which includes several bug fixes and performance improvements
- Improved performance when rendering scenes with nested CSG operations or groups
- Fixed rendering and bounds calculation of non-planar extruded shapes

## [1.1.5](https://github.com/nicklockwood/ShapeScript/releases/tag/1.1.5) (2021-08-02)

- Info window in ShapeScript Viewer no longer includes imported models in texture count
- Fixed a regression in ShapeScript Viewer 1.1.4 where error message wouldn't refresh correctly on reload
- Improved error messaging for errors that occur in an imported file
- Reloading a partially-rendered scene should now terminate the rendering more quickly, freeing up CPU
- Rendering is now cancelled when document is closed (previously it continued in background)
- Improved responsiveness of incremental rendering for complex scenes
- Program `source` and `statements` properties are now public 

## [1.1.4](https://github.com/nicklockwood/ShapeScript/releases/tag/1.1.4) (2021-07-31)

- Increased time precision of document file monitoring in ShapeScript Viewer app
- Improved threading a progress logging in ShapeScript Viewer app
- Added Linux support for ShapeScriptLib (excluding rendering and text functions)
- Made static color constants immutable
- Bumped Euclid version to 0.5.3

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
