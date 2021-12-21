//
//  SVGPathTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 28/09/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

#if canImport(CoreGraphics)

import CoreGraphics
@testable import ShapeScript
import XCTest

private func XCTAssertEqual(
    _ lhs: @autoclosure () throws -> CGPath,
    _ rhs: @autoclosure () throws -> CGPath,
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertNoThrow(_ = try lhs(), file: file, line: line)
    XCTAssertNoThrow(_ = try rhs(), file: file, line: line)
    if let lhs = try? lhs(), let rhs = try? rhs() {
        XCTAssertEqual(lhs.paths(), rhs.paths())
    }
}

class SVGPathTests: XCTestCase {
    func testTriangle() throws {
        let svgPath = try SVGPath("M150 0 L75 200 L225 200 Z")
        let cgPath = CGMutablePath()
        cgPath.move(to: CGPoint(x: 150, y: 0))
        cgPath.addLine(to: CGPoint(x: 75, y: -200))
        cgPath.addLine(to: CGPoint(x: 225, y: -200))
        cgPath.closeSubpath()
        XCTAssertEqual(try .fromSVG(svgPath), cgPath)
    }

    func testCross() throws {
        let svgPath = try SVGPath("M2 1 h1 v1 h1 v1 h-1 v1 h-1 v-1 h-1 v-1 h1 z")
        let cgPath = CGMutablePath()
        cgPath.move(to: CGPoint(x: 2, y: -1))
        cgPath.addLine(to: CGPoint(x: 3, y: -1))
        cgPath.addLine(to: CGPoint(x: 3, y: -2))
        cgPath.addLine(to: CGPoint(x: 4, y: -2))
        cgPath.addLine(to: CGPoint(x: 4, y: -3))
        cgPath.addLine(to: CGPoint(x: 3, y: -3))
        cgPath.addLine(to: CGPoint(x: 3, y: -4))
        cgPath.addLine(to: CGPoint(x: 2, y: -4))
        cgPath.addLine(to: CGPoint(x: 2, y: -3))
        cgPath.addLine(to: CGPoint(x: 1, y: -3))
        cgPath.addLine(to: CGPoint(x: 1, y: -2))
        cgPath.addLine(to: CGPoint(x: 2, y: -2))
        cgPath.closeSubpath()
        XCTAssertEqual(try .fromSVG(svgPath), cgPath)
    }

    func testHeart() throws {
        XCTAssertNoThrow(try SVGPath("""
        M213.1,6.7c-32.4-14.4-73.7,0-88.1,30.6C110.6,4.9,67.5-9.5,36.9,6.7
        C2.8,22.9-13.4,62.4,13.5,110.9 C33.3,145.1,67.5,170.3,125,217
        c59.3-46.7,93.5-71.9,111.5-106.1C263.4,64.2,247.2,22.9,213.1,6.7z
        """))
    }

    func testNumbersWithoutSeparator() throws {
        let svgPath = try SVGPath("M0 0L-.57.13Z")
        let cgPath = CGMutablePath()
        cgPath.move(to: .zero)
        cgPath.addLine(to: CGPoint(x: -0.57, y: -0.13))
        cgPath.closeSubpath()
        XCTAssertEqual(try .fromSVG(svgPath), cgPath)
    }

    func testAbsoluteHorizontalRule() throws {
        let svgPath = try SVGPath("M0 0L10 10H0Z")
        let cgPath = CGMutablePath()
        cgPath.move(to: .zero)
        cgPath.addLine(to: CGPoint(x: 10, y: -10))
        cgPath.addLine(to: CGPoint(x: 0, y: -10))
        cgPath.closeSubpath()
        XCTAssertEqual(try .fromSVG(svgPath), cgPath)
    }

    func testTrailingNumber() throws {
        XCTAssertThrowsError(try SVGPath("M150 0 L75 200 L225 200 Z5")) { error in
            XCTAssertEqual(
                error as? SVGErrorType,
                .unexpectedArgument(for: "Z", expected: 0)
            )
        }
    }
}

#endif
