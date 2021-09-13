## [1.3.2](https://github.com/nicklockwood/ShapeScript/releases/tag/1.3.2) (2021-09-13)

- Added stack overflow detection, preventing crashes due to infinite recursion
- Added support for underscores in identifiers
- Empty and single-element tuples are now permitted (useful in loops and data structures)
- Looping over vector, size and color values is no longer permitted (only tuples and ranges)
- Geometry `Hashable` implementation is now based on value rather than reference
- Bumped Euclid to 0.5.12, which fixes the getters for `Rotation.pitch`/`yaw`/`roll`
- Shape position/orientation/size are now read/write properties instead of setters
- Wireframes are now rendered with polygons instead of lines on x86, for better quality
- Added open/create document prompt when opening app
- Improved Welcome view

## [1.3.1](https://github.com/nicklockwood/ShapeScript/releases/tag/1.3.1) (2021-09-07)

- Disabled axes by default and added instructions for enabling to help
- Added ordinal members for accessing arbitrary tuple elements
- Fixed rendering bug when using negative scale values
- Fixed bug where functions were able to access local variables of the caller
- Fixed dot operator (member lookup) chaining
- Added documentation for tuples and structured data access
- Bumped Euclid to 0.5.11, which includes several performance optimizations
- Fixed issue where console would not clear correctly when reloading
- Fixed hint message when missing closing brace
- Added `colour` and `grey` as aliases for `color` and `gray`
- Made stroke line width proportional to the scene size
- Improved logic for default camera zoom level
- Increase antialiasing quality in viewer
- Updated screenshots and fixed bugs in help examples

## [1.3.0](https://github.com/nicklockwood/ShapeScript/releases/tag/1.3.0) (2021-08-31)

- Added new standalone range expression with optional `step` value
- For loops can now be used with either range or tuple/vector values
- Added support for hex color literals
- Added standard color names as constants
- Inherited standard library symbols no longer override user-defined constants
- All ShapeScript value types now conform to `AnyHashable`
- Removed `CustomStringConvertible` conformance from `GeometryType` as it made debugging harder
- Renamed `StatementType.node` to `StatementType.block`, since the term was confusing
- Bumped Euclid to 0.5.10, which includes several bug fixes and features
- Fixed crash when trying to access vector or color members from a non-numeric tuple
- Fixed crash when trying to color members from a tuple with more than 4 elements
- Accessing vector members on a tuple with more than 3 elements now raises an error
- Made unchecked Color initializer private
- Removed SceneViewController.snapshot() method
- Added option to show axes in ShapeScript Viewer
- Wireframe view option in viewer is now rendered using lines instead of SceneKit Debug option
- Made wireframe view option persistent across app launches

## [1.2.4](https://github.com/nicklockwood/ShapeScript/releases/tag/1.2.4) (2021-08-25)

- Fixed a crash when logging large integer values
- Fixed bug where negative numbers would be logged as zero when using the print command
- Improved formatting of logged numeric values generally

## [1.2.3](https://github.com/nicklockwood/ShapeScript/releases/tag/1.2.3) (2021-08-24)

- Enabled parenthesized expressions to span multiple lines
- Improved error message when assigning multiple values to single type
- Fixed assigning color literal value to background without parens
- Added Color initializers
- Added SceneViewController.snapshot() method

## [1.2.2](https://github.com/nicklockwood/ShapeScript/releases/tag/1.2.2) (2021-08-24)

- Blocks that accept child values can now be called without braces around them
- Fixed confusing error messages caused by mesh commands being unavailable in certain scopes
- Made script evaluation cancellable in case of infinite iteration or recursion
- Fixed bug in Viewer app where view fails to refresh after loading geometry
- Improved and simplified error handling logic

## [1.2.1](https://github.com/nicklockwood/ShapeScript/releases/tag/1.2.1) (2021-08-19)

- Fixed crash when `for` loop end index < start index
- Improved `print` log output, especially for arrays/tuples and nested values
- Added `Loggable` protocol for stringifying values logged using the ShapeScript `print` command
- Replaced `TokenType.description` with `TokenType.errorDescription` to aid debugging
- Text now supports using \n for line-breaks (this was documented as working, but never implemented)
- Fixed confusing error message when first value of tuple matches expected type
- Fixed nonsensical error message when a command is used in an expression
- Bumped Euclid to 0.5.9, which includes fixes for extruded paths
- Extruding along a compound path now forms a union between the resultant shapes
- Fixed typos and improved help documentation
- Fixed member lookup precedence
- Improved test coverage

## [1.2.0](https://github.com/nicklockwood/ShapeScript/releases/tag/1.2.0) (2021-08-15)

- Improved progressive rendering logic, reducing wait before seeing first results in viewer
- Geometry cache is now limited to ~1GB per open document instead of being unbounded
- Cached geometry is now cleared when document is closed instead of persisting for app lifetime
- Invalid font names now produce an error instead of silently falling back to Helvetica
- Paths are now drawn in white when background is set to a dark color or texture
- Fixed an index out-of-bounds crash in the Levenshtein distance function
- Bumped Euclid to 0.5.8, which includes several bug fixes
- Renamed `GeometryType.none` to the more descriptive `GeometryType.group`
- Made `Geometry.mesh` and `Geometry.associatedData` properties thread-safe using `NSLock`
- Removed `Scene.deepCopy()` and `Geometry.deepCopy()` methods as instances are now thread-safe
- Moved selection logic out of `ShapeScriptLib` and into Viewer example application
- Fixed bug in Viewer where geometries would be deselected during progressive loading
- Added LRUCache dependency

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
