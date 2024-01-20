## [1.1.4](https://github.com/nicklockwood/SVGPath/releases/tag/1.1.4) (2023-12-09)

- Fixed inverted arc rotation argument

## [1.1.3](https://github.com/nicklockwood/SVGPath/releases/tag/1.1.3) (2023-03-17)

- Fixed bug with parsing paths that use a leading `+` as a delimiter between numbers

## [1.1.2](https://github.com/nicklockwood/SVGPath/releases/tag/1.1.2) (2023-03-08)

- Fixed bug where relative coordinates were calculated incorrectly after an `end` command

## [1.1.1](https://github.com/nicklockwood/SVGPath/releases/tag/1.1.1) (2022-07-27)

- Fixed bug where coordinates were flipped vertically when serializing path to string

## [1.1.0](https://github.com/nicklockwood/SVGPath/releases/tag/1.1.0) (2022-07-24)

- Added `SVGPath(cgPath:)` initializer for converting `CGPath` to `SVGPath`
- Added `SVGPath.string(with:)` method for serializing an `SVGPath` object back to string form
- Added `SVGPath.points()` and `SVGPath.getPoints()` methods for extracting path data
- Fixed compiler warning on older Xcode versions
- Fixed warnings on latest Xcode

## [1.0.2](https://github.com/nicklockwood/SVGPath/releases/tag/1.0.2) (2022-04-15)

- Added `SVGArc.asBezierPath()` method for converting arcs to Bezier curves without Core Graphics

## [1.0.1](https://github.com/nicklockwood/SVGPath/releases/tag/1.0.1) (2022-04-04)

- Fixed parsing scientific numbers
- Added support for implicit `lineTo` commands

## [1.0.0](https://github.com/nicklockwood/SVGPath/releases/tag/1.0.0) (2022-01-08)

- First release
