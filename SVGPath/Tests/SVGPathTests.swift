//
//  SVGPathTests.swift
//  SVGPathTests
//
//  Created by Nick Lockwood on 08/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import SVGPath
import XCTest

class SVGPathTests: XCTestCase {
    func testTriangle() throws {
        let svgPath = try SVGPath(string: "M150 0 L75 200 L225 200 Z")
        let expected = SVGPath(commands: [
            .moveTo(.init(x: 150, y: 0)),
            .lineTo(.init(x: 75, y: -200)),
            .lineTo(.init(x: 225, y: -200)),
            .end,
        ])
        XCTAssertEqual(svgPath, expected)
    }

    func testCross() throws {
        let svgPath =
            try SVGPath(string: "M2 1 h1 v1 h1 v1 h-1 v1 h-1 v-1 h-1 v-1 h1 z")
        let expected = SVGPath(commands: [
            .moveTo(.init(x: 2, y: -1)),
            .lineTo(.init(x: 3, y: -1)),
            .lineTo(.init(x: 3, y: -2)),
            .lineTo(.init(x: 4, y: -2)),
            .lineTo(.init(x: 4, y: -3)),
            .lineTo(.init(x: 3, y: -3)),
            .lineTo(.init(x: 3, y: -4)),
            .lineTo(.init(x: 2, y: -4)),
            .lineTo(.init(x: 2, y: -3)),
            .lineTo(.init(x: 1, y: -3)),
            .lineTo(.init(x: 1, y: -2)),
            .lineTo(.init(x: 2, y: -2)),
            .end,
        ])
        XCTAssertEqual(svgPath, expected)
    }

    func testHeart() throws {
        let heart = try SVGPath(string: """
        M213.1,6.7c-32.4-14.4-73.7,0-88.1,30.6C110.6,4.9,67.5-9.5,36.9,6.7
        C2.8,22.9-13.4,62.4,13.5,110.9 C33.3,145.1,67.5,170.3,125,217
        c59.3-46.7,93.5-71.9,111.5-106.1C263.4,64.2,247.2,22.9,213.1,6.7z
        """)
        var options = SVGPath.WriteOptions(wrapWidth: 72)
        XCTAssertEqual(heart.string(with: options), """
        M213.1 6.7 C180.7 -7.7 139.4 6.7 125 37.3 C110.6 4.9 67.5 -9.5 36.9 6.7
        C2.8 22.9 -13.4 62.4 13.5 110.9 C33.3 145.1 67.5 170.3 125 217 C184.3
        170.3 218.5 145.1 236.5 110.9 C263.4 64.2 247.2 22.9 213.1 6.7 Z
        """)
        options.prettyPrinted = false
        XCTAssertEqual(heart.string(with: options), """
        M213.1 6.7C180.7-7.7 139.4 6.7 125 37.3C110.6 4.9 67.5-9.5 36.9 6.7C2.8
        22.9-13.4 62.4 13.5 110.9C33.3 145.1 67.5 170.3 125 217C184.3 170.3
        218.5 145.1 236.5 110.9C263.4 64.2 247.2 22.9 213.1 6.7Z
        """)
    }

    func testPathRoundTrip() throws {
        let pathString = """
        M435 390.39A10 10 0 0 1 442.46 394.21L492.19 457.78A9.09 9.09 0 0 1
        492.3 469.09L442.46 532.81A8.29 8.29 0 0 1 435 536.39L153.15 536.39A9.2
        9.2 0 0 1 146 532.77L96.27 469.2A9.09 9.09 0 0 1 96.16 457.89L146 394.18
        C147.42 392.37 149.37 390.39 151.48 390.39L435 390.39M435 387.39L151.16
        387.39C148.59 387.52 146.16 389.13 143.64 392.32L93.8 456A12 12 0 0 0
        93.93 471L143.64 534.55A12.21 12.21 0 0 0 153.15 539.32L435 539.32A11.19
        11.19 0 0 0 444.82 534.58L494.66 470.87A12 12 0 0 0 494.53 455.87L444.82
        392.32A13.06 13.06 0 0 0 435 387.32Z
        """
        let path = try SVGPath(string: pathString)
        let options = SVGPath.WriteOptions(prettyPrinted: false, wrapWidth: 72)
        XCTAssertEqual(path.string(with: options), pathString)
    }

    func testNumbersWithoutSeparator() throws {
        let svgPath = try SVGPath(string: "M0 0L-.57.13Z")
        let expected = SVGPath(commands: [
            .moveTo(.zero),
            .lineTo(.init(x: -0.57, y: -0.13)),
            .end,
        ])
        XCTAssertEqual(svgPath, expected)
    }

    func testAbsoluteHorizontalRule() throws {
        let svgPath = try SVGPath(string: "M0 0L10 10H0Z")
        let expected = SVGPath(commands: [
            .moveTo(.zero),
            .lineTo(.init(x: 10, y: -10)),
            .lineTo(.init(x: 0, y: -10)),
            .end,
        ])
        XCTAssertEqual(svgPath, expected)
    }

    func testTrailingNumber() throws {
        XCTAssertThrowsError(try SVGPath(
            string: "M150 0 L75 200 L225 200 Z5"
        )) { error in
            XCTAssertEqual(
                error as? SVGError,
                .unexpectedArgument(for: "Z", expected: 0)
            )
        }
    }

    func testRepeatedParams() throws {
        let svgPath = try SVGPath(string: "M150 0 L75 200 225 200 Z")
        let expected = SVGPath(commands: [
            .moveTo(.init(x: 150, y: 0)),
            .lineTo(.init(x: 75, y: -200)),
            .lineTo(.init(x: 225, y: -200)),
            .end,
        ])
        XCTAssertEqual(svgPath, expected)
    }

    func testScientificNotationNumbers() throws {
        let svgPath = try SVGPath(string: "M150 0 L75 200e+0 225e-0 200 Z")
        let expected = SVGPath(commands: [
            .moveTo(.init(x: 150, y: 0)),
            .lineTo(.init(x: 75, y: -200)),
            .lineTo(.init(x: 225, y: -200)),
            .end,
        ])
        XCTAssertEqual(svgPath, expected)
    }

    func testImplicitLines() throws {
        let svgPath = try SVGPath(string: "M150 0 75 200 225 200 Z")
        let expected = SVGPath(commands: [
            .moveTo(.init(x: 150, y: 0)),
            .lineTo(.init(x: 75, y: -200)),
            .lineTo(.init(x: 225, y: -200)),
            .end,
        ])
        XCTAssertEqual(svgPath, expected)
    }
}
