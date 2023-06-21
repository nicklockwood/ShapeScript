# Change Log

## [1.6.11](https://github.com/nicklockwood/ShapeScript/releases/tag/1.6.11) (2023-06-21)

- Fixed bug where block options could clash with global functions of the same name

## [1.6.10](https://github.com/nicklockwood/ShapeScript/releases/tag/1.6.10) (2023-06-12)

- Removed Reddit community links
- Fixed precedence issue with `point`/`curve` commands (introduced in 1.6.9)
- Fixed broken importing of external model file formats (introduced in 1.6.8)
- Block options can now be set conditionally within `if` blocks
- Overrides to global constants and functions are now usable inside block invocations
- Fixed bug where local defines in a block invocation were mistaken for options
- The `point.color` member now returns an empty tuple instead of an error if unset
- Fixed occasional blank screen glitch when first opening a file
- Fixed iOS camera menu not updating after camera is moved
- Bumped Euclid to version 0.6.14

## [1.6.9](https://github.com/nicklockwood/ShapeScript/releases/tag/1.6.9) (2023-04-21)

- Fixed confusing function / operator precedence
- Improved scroll-to-cursor behavior in iOS source editor
- Bumped Euclid to version 0.6.13 (includes fix for cracking/holes issue)
- Added What's New in ShapeScript screen to iOS Viewer

## [1.6.8](https://github.com/nicklockwood/ShapeScript/releases/tag/1.6.8) (2023-04-16)

- Improved static type inference for import statements
- Fixed type error for constant transform overrides
- Removed OpenGL support for High Sierra
- Fixed range precision issue
- Added Linux CLI support

## [1.6.7](https://github.com/nicklockwood/ShapeScript/releases/tag/1.6.7) (2023-04-04)

- Added `arc` command
- Added vector algebra operators
- Setting unequal width/height no longer distorts corner radius for `roundrect` command
- Added `sign`, `dot`, `cross`, `length` and `normalize` functions
- Added implicit casting between vector and size values
- Select Shape menu is now disabled when empty
- Improved argument error messages
- Fixed bug where modulo operator sometimes returned negative values
- Fixed bug when mixing points and subpaths in a `path` command
- Fixed retain cycle in iOS file dialog
- Fixed potential crash in `selectCamera()` function
- Increased code sharing between Mac and iOS Viewer implementations
- Bumped Euclid to version 0.6.12

## [1.6.6](https://github.com/nicklockwood/ShapeScript/releases/tag/1.6.6) (2023-03-25)

- The position and transform of mesh and path values can now be set as if they were a block
- Setting name on a block that returns a path no longer makes the result unusable in a builder
- Constants and property symbols are no longer called "function" in error messages
- Removed unhelpful "did you mean" suggestions when a valid symbol is used in wrong context
- Improved error description for numeric list type
- Fixed various bugs in the iOS source editor
- Bumped SVGPath to version 1.1.3

## [1.6.5](https://github.com/nicklockwood/ShapeScript/releases/tag/1.6.5) (2023-03-02)

- Fixed performance regression in `GeometryType.bounds` when using lathe shapes
- Fixed line number display in iOS source editor
- Bumped Euclid to version 0.6.11

## [1.6.4](https://github.com/nicklockwood/ShapeScript/releases/tag/1.6.4) (2023-02-28)

- The `bounds` and `polygons` members now correctly take object transform into account
- ShapeScript Viewer for iPad now supports multiple viewer/editor windows
- Fixed some bugs and improved editing experience for source editor on iOS
- Fixed bug where iOS editor would sometimes close spontaneously while editing
- Added `shapescript:` URL scheme and improved URL handling
- Bumped Euclid to version 0.6.10

## [1.6.3](https://github.com/nicklockwood/ShapeScript/releases/tag/1.6.3) (2023-01-31)

- iOS Viewer now supports editing `.shape` files directly inside the app
- Added `Edit > Select Shape` and `Clear Selection` menus in macOS viewer
- Added selection hotkeys and VoiceOver support for macOS viewer
- Fixed selection being cleared whenever geometry is refreshed
- Fixed dynamic dark mode updates on iOS viewer
- Fixed iOS split view bounds crash
- Fixed bug where camera hotkeys failed after reload
- Fixed error overlay translucency
- Fixed various member type bugs

## [1.6.2](https://github.com/nicklockwood/ShapeScript/releases/tag/1.6.2) (2023-01-16)

- Improved info panel display
- Fixed twisted extrusion offset
- Fixed `roundrect` detail level (previously 4x higher than intended)
- Fixed incorrect output when intersecting groups of meshes
- Empty scenes are no longer hidden if they contain debug geometry
- Scene now conforms to Equatable protocol
- Fixed misleading error message for excess color arguments
- Fixed spurious forward declaration error for options that shadow global define
- Added automatic casting of hex strings to colors (useful for JSON data)
- Made `.polygon` members available on all geometries, not just manually-created meshes
- Excluded source location from Geometry equality comparisons
- Fixed vector member access on tuples containing string elements
- Fixed vector member access on nested numeric tuples
- Fixed color member access on tuples and strings
- Fixed polygon member lookup on meshes
- Fixed handling of blocks with optional children (e.g. `polygon`)
- Improved symbol lookup performance
- Bumped Euclid to version 0.6.8

## [1.6.1](https://github.com/nicklockwood/ShapeScript/releases/tag/1.6.1) (2023-01-02)

- Added `twist` option to `extrude` command
- Fixed inconsistent View menu options when switching between open documents
- Bumped Euclid to version 0.6.7

## [1.6.0](https://github.com/nicklockwood/ShapeScript/releases/tag/1.6.0) (2022-12-27)

- Added hull command for creating convex hulls from points, paths or other meshes
- Added mesh command for manually creating meshes from individual polygons
- Added `axisAligned` property for controlling extrusion along  paths
- Added support for importing plain text files as a string and JSON files as a tuple
- Added modulo operator for calculating remainder of division
- Significantly overhauled type system to support lists, unions and objects
- Improved static analysis, allowing type errors to be caught earlier
- Improved handling of background property scope
- The min and max functions are now variadic (accept any number of arguments)
- Added `split()`, `join()` and `trim()` functions for working with strings
- Added automatic conversion of strings to numbers or boolean values where applicable
- Added `string.lines`, `.words` and `.characters` members
- Added `tuple.count`, `.last`, `.allButFirst` and `.allButLast` members
- Fixed member lookup on numeric literals
- Fixed bug where material of imported shapes could not be overridden
- Background and texture can now be cleared by setting them to an empty string
- Logging geometry values to console now produces more useful output
- Added proper logging for bounds and point values
- Added `fileTimedOut` and `circularImport` errors
- Refactored and improved error handling
- Renamed `ImportError` to `ProgramError`
- Raised minimum Euclid version to 0.6.6
- Added Spirals example

## [1.5.14](https://github.com/nicklockwood/ShapeScript/releases/tag/1.5.14) (2022-12-18)

- Added support for C-style block comments using `/* ... */` syntax
- Fixed bug where source file could incorrectly be inferred as UTF-7, causing parsing errors
- Fixed issue where error messages would sometimes suggest the same identifier you already used
- Improved script execution performance by making source location lookup lazy
- Bumped Euclid to version 0.6.6

## [1.5.13](https://github.com/nicklockwood/ShapeScript/releases/tag/1.5.13) (2022-12-08)

- Fixed crash when importing external `.shape` files
- When error occurs in imported file, Cmd-E now opens that file instead of the main file
- Bumped Euclid to version 0.6.5
 
## [1.5.12](https://github.com/nicklockwood/ShapeScript/releases/tag/1.5.12) (2022-11-21)

- Bumped Euclid to version 0.6.4 (includes fixes for single-point path crash and path extrusions)
- Fixed parsing ambiguity in tuple expressions where identifier is followed by opening paren
- Improved bounds accuracy for circle-based shapes

## [1.5.11](https://github.com/nicklockwood/ShapeScript/releases/tag/1.5.11) (2022-11-06)

- Fixed source code view on iOS
- Fixed loading of external iCloud assets when file has not been downloaded
- ShapeScript now monitors changes to external textures, fonts and imports on iOS
- Original topology for imported models is now preserved, instead of being triangulated
- Improved error messaging for file imports
- Bumped Euclid to version 0.6.2

## [1.5.10](https://github.com/nicklockwood/ShapeScript/releases/tag/1.5.10) (2022-10-29)

- Improved documentation for strings and trigonometry functions
- Fixed empty bounds returned for `lathe`, `fill`, `extrude` and `loft` shapes
- Fixed runtime warning about postscript font names
- Fixed range bug in error formatting logic
- Fixed inconsistent handling of functions that return tuples
- Fixed inconsistent member lookup handling
- Bumped Euclid to version 0.6.0
- Fixed Linux build warnings

## [1.5.9](https://github.com/nicklockwood/ShapeScript/releases/tag/1.5.9) (2022-10-06)

- Fixed getting started link in Welcome modal
- Removed bad suggestions from editors list
- Added iOS target for ShapeScript Viewer

## [1.5.8](https://github.com/nicklockwood/ShapeScript/releases/tag/1.5.8) (2022-10-03)

- Added shared `SCNGeometry` cache, significantly improving performance for scenes with repeated objects
- Significantly reduced time to calculate mesh stats (as displayed in object info window)
- Optimized source line lookup that affected script execution performance

## [1.5.7](https://github.com/nicklockwood/ShapeScript/releases/tag/1.5.7) (2022-09-26)

- Fixed bug where a `define` inside a block couldn't refer to `option` value
- Fixed bug when parsing expressions ending in a `not` identifier
- Fixed bug where view unexpectedly jumped to custom camera after reload
- Bumped Euclid to version 0.5.30
- Bumped LRUCache to version 1.0.3
- Bumped SVGPath to version 1.1.1
- Added iOS help pages

## [1.5.6](https://github.com/nicklockwood/ShapeScript/releases/tag/1.5.6) (2022-09-06)

- Added ability to copy the current camera configuration for easy creation of custom cameras
- Improved logic for when camera position is reset after document update or window resize
- Fixed bug where custom cameras did not correctly inherit the document background
- Fixed bug where scale was doubled for custom orthographic cameras
- Fixed live updating of document background when switching between light and dark mode
- Fixed race condition in view rendering sometimes resulting in a blank scene
- Fixed member suggestions for empty tuple
- Renamed `Geometry(scnNode:)` initializer for consistency
- Deprecated `Geometry.cameras` accessor
- Bumped Euclid to version 0.5.29

## [1.5.5](https://github.com/nicklockwood/ShapeScript/releases/tag/1.5.5) (2022-08-11)

- Significantly improved performance for bulk fill/extrude operations (e.g. text)
- Fixed camera position continuously being reset in ShapeScript Viewer while loading
- Added indicator to Camera menu when camera has been moved
- Bumped Euclid to version 0.5.28

## [1.5.4](https://github.com/nicklockwood/ShapeScript/releases/tag/1.5.4) (2022-07-25)

- Fixed setting font inside a `text` command
- Improved error messages for missing block arguments
- Multiple arguments passed to `text` command are now treated as single coalesced string
- Extruding along a path now more reliably produces watertight output
- Fixed parsing of tuple statements starting with constant
- Fixed parsing of a prefix minus immediately followed by decimal point
- Increased detail multiplier for `svgpath` command to match path
- Fixed `svgpath` crash when missing `M` command after `Z`
- Fixed camera clipping issue when resizing objects
- Bumped Euclid to version 0.5.26

## [1.5.3](https://github.com/nicklockwood/ShapeScript/releases/tag/1.5.3) (2022-07-03)

- The `loft` command now supports joining shapes with unequal numbers of sides or points
- The `fill`, `lathe` and `extrude` commands now more reliably produce watertight output
- Fixed incorrect polygon/triangle counts in model info
- Fixed line numbers in selected object info
- Bumped Euclid to version 0.5.25
- Fixed some flaky tests

## [1.5.2](https://github.com/nicklockwood/ShapeScript/releases/tag/1.5.2) (2022-05-28)

- Fixed bug where path lines were drawn too thin for large models
- Improved error messaging for invalid use of option
- Fixed suggestions for misspelled commands
- Bumped Euclid to version 0.5.21

## [1.5.1](https://github.com/nicklockwood/ShapeScript/releases/tag/1.5.1) (2022-05-07)

- Add implicit `detail/smoothing`, `color/texture`, `position/orientation/size` and `font` options to custom blocks 
- Logical `and/or` expressions now short circuit (don't evaluate their second parameter unless needed)
- Added support for creating `MaterialProperty` from `SCNMaterials` using `NS/UIImage`
- Fixed setting camera position on locked documents (such as the Example projects)
- Added slightly stronger type safety when calling commands
- Fixed axes contrast when using per-camera backgrounds
- Fixed font inheritance for user-defined blocks
- Added custom fonts to model info display
- Added USDZ to list of supported export types
- Improved iOS compatibility

## [1.5.0](https://github.com/nicklockwood/ShapeScript/releases/tag/1.5.0) (2022-04-29)

- Added support for custom light sources using the `light` command
- Added user-defined functions/commands (previously only blocks could be defined)
- The width and/or height for exported images can now be set on a per-camera basis
- Added `polygon` command for more easily creating regular polygon paths
- The scene background can now be set individually for each camera
- Using `position`, `orientation` and `size` inside a `path` now works again (broken since 1.4.4)
- Using `rnd` command in option default expressions no longer has a knock-on effect on the sequence
- Options can now reference local constants in their default values
- Material brightness logic used in Viewer app is now part of the ShapeScript core
- Using `wrapwidth` or `linespacing` text commands inside an `svgpath` block now raises an error
- Fixed blank screen when scene contains empty `camera` node
- Removed `StatementType.block` case in favor of expression form
- Fixed some bugs in path generation relating to point colors
- The `OSColor` typealias is now private
- Added SVGPath dependency

## [1.4.7](https://github.com/nicklockwood/ShapeScript/releases/tag/1.4.7) (2022-04-14)

- Camera is no longer reset on every reload
- Fixed camera snapback if moved during initial model load
- Added `smoothing` command for controlling surface normal generation
- Disallowed used of `detail` and `font` commands in scopes where they have no effect
- The `svgpath` command now works on Linux
- Bumped Euclid to version 0.5.20

## [1.4.6](https://github.com/nicklockwood/ShapeScript/releases/tag/1.4.6) (2022-04-08)

- Fixed `svgpath` command (broken in 1.4.5)
- Fixed bug where axes were rendered in the wrong color
- Watertight status is now displayed in object info panel
- The `roundrect` command now works on Linux
- Bumped LRUCache to version 1.0.3
- Bumped Euclid to version 0.5.18

## [1.4.5](https://github.com/nicklockwood/ShapeScript/releases/tag/1.4.5) (2022-03-07)

- Added support for setting per-vertex colors in a path
- Font, text color and linespacing can now be specified per-line within a text block
- Fixed underestimated bounds calculation for extrusion along a path
- Made logic for child count calculation more consistent
- Bumped Euclid to version 0.5.17

## [1.4.4](https://github.com/nicklockwood/ShapeScript/releases/tag/1.4.4) (2022-01-21)

- Fixed infinite recursion crash when a shape file tries to import itself
- Improved error message when imported model file is not readable
- Fixed assertion failure when evaluating imported block due to source confusion
- Added stricter symbol checking in stdlib so, e.g. name can't be used inside a path
- Fixed bug in viewer where examples always open in orthographic mode
- Imported gifs are now counted as textures rather than models in info panel
- Model type is now displayed correctly in info panel
- Fixed some iOS compatibility issues

## [1.4.3](https://github.com/nicklockwood/ShapeScript/releases/tag/1.4.3) (2021-12-25)

- ShapeScript will now attempt to ensure generated meshes are watertight by default
- Fixed unintended behavior change with blocks returning multiple shapes (introduced in 1.3.7)
- Fixed precondition failure when calling a block from inside a `path` command
- Camera nodes are no longer included in object count in model info
- Handle repeated parameter lists without command tokens in `svgpath`
- Added additional `svgpath` error handling
- Bumped Euclid to version 0.5.15

## [1.4.2](https://github.com/nicklockwood/ShapeScript/releases/tag/1.4.2) (2021-12-10)

- The `svgpath` command now supports arc instructions ('A' and 'a')
- Fixed bug in `svgpath` affecting absolute horizontal ('H') and vertical ('V') lines
- Save panel in viewer now adds `.shape` extension to file name if not present
- Made online documentation link logic more robust

## [1.4.1](https://github.com/nicklockwood/ShapeScript/releases/tag/1.4.1) (2021-11-22)

- Fixed bug where `along` property was ignored in `extrude` command
- Fixed wireframe rendering mode in viewer

## [1.4.0](https://github.com/nicklockwood/ShapeScript/releases/tag/1.4.0) (2021-11-03)

- Added user-defined cameras
- Added boolean constants and operators
- Added comparison operators (greater than, equals, etc)
- Added `if`/`else` statements
- Added `assert` command
- Improved suggestions for mistyped operators
- Replaced range expression with separate `to` and `step` operators
- Failure to load an external model now displays an error instead of failing silently
- Added distinct error type for invalid text escape sequences
- Simplified identifier expression representation
- Converted `option` keyword to contextual keyword
- Added `Geometry.worldTransform` property

## [1.3.10](https://github.com/nicklockwood/ShapeScript/releases/tag/1.3.10) (2021-11-01)

- DAE files containing triangle strips or non-triangular polygons are now loaded correctly
- Fixed empty Geometry names not being set to nil
- Fixed broken footer links in help pages
- Bumped Euclid to version 0.5.14

## [1.3.9](https://github.com/nicklockwood/ShapeScript/releases/tag/1.3.9) (2021-10-22)

- Added multiple camera options
- Added orthographic view option
- Reorganized camera menu and keyboard shortcuts
- View settings are now saved per-document instead of globally
- Fixed bug where camera would reset when toggling wireframe mode
- Documents now open in tabs automatically when tab bar is shown

## [1.3.8](https://github.com/nicklockwood/ShapeScript/releases/tag/1.3.8) (2021-10-10)

- Added `svgpath` command for creating paths using SVG-compatible syntax
- Added `bounds` member property for calculating dimensions of complex shapes
- Added `wrapwidth` and `linespacing` options for text
- Improved debug command behavior for children of CSG containers
- Fixed bug when setting `background` color with a single number (e.g. `0` for black)
- Fixed bug where only first expression argument was highlighted in a type-mismatch error

## [1.3.7](https://github.com/nicklockwood/ShapeScript/releases/tag/1.3.7) (2021-09-26)

- Added debug command for highlighting invisible geometry
- Custom blocks can now return any value type, not just meshes or paths
- Infix expressions are now handled correctly when used in a statement position
- Improved type mismatch error messages for block parameters
- String values are no longer nullable and empty strings are handled more correctly
- Nested command calls without parentheses are now handled correctly
- Improved type reporting for single-value tuples in error messages
- Updated print behavior to better match text interpolation

## [1.3.6](https://github.com/nicklockwood/ShapeScript/releases/tag/1.3.6) (2021-09-21)

- Added text interpolation, allowing text strings to be constructed dynamically
- Import and textures file paths can now be constructed dynamically
- Alpha component of colors can now be overridden with a convenient syntax
- Removed confusing references to "string" and "identifier" from error messages
- Added ability to load text fonts from a file name or path
- Fixed bug where font getter returned texture instead
- Improved help documentation

## [1.3.5](https://github.com/nicklockwood/ShapeScript/releases/tag/1.3.5) (2021-09-19)

- Numbers can now be used in text blocks
- Fixed bug with times/divide operator associativity
- Fixed default zoom level in viewer when axes are shown
- Fixed bug in scene bounds calculation when children have a transform applied
- Improved error message for missing files specified by full path
- Limited maximum lineWidth when rendering paths

## [1.3.4](https://github.com/nicklockwood/ShapeScript/releases/tag/1.3.4) (2021-09-17)

- The position/size/orientation options can now be used inside `text` blocks
- Fixed parsing error when using inline expressions in loop range
- Unsupported string escape sequences are now treated as an error
- Command parameters are now included in assertion failure error highlighting
- Fixed bug with sequential escape sequences in text

## [1.3.3](https://github.com/nicklockwood/ShapeScript/releases/tag/1.3.3) (2021-09-14)

- Fixed crash when font is set to an empty string
- Fixed incorrect suggestion of `option` for typos in contexts where it isn't available
- Print logging in a long/infinite loop no longer freezes UI
- Help index is now generated automatically
- Improved help for colors and text

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

- Fixed assertion failure if a parsing error occurs at the last character in the `.shape` file
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
