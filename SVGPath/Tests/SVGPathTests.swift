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
        XCTAssertNoThrow(try SVGPath(string: """
        M213.1,6.7c-32.4-14.4-73.7,0-88.1,30.6C110.6,4.9,67.5-9.5,36.9,6.7
        C2.8,22.9-13.4,62.4,13.5,110.9 C33.3,145.1,67.5,170.3,125,217
        c59.3-46.7,93.5-71.9,111.5-106.1C263.4,64.2,247.2,22.9,213.1,6.7z
        """))
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
