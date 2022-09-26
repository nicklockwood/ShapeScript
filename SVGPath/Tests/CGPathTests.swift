//
//  CGPathTests.swift
//  SVGPathTests
//
//  Created by Nick Lockwood on 08/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

#if canImport(CoreGraphics)

import CoreGraphics
@testable import SVGPath
import XCTest

private extension CGPath {
    var elements: [CGPathElement] {
        var elements = [CGPathElement]()
        enumerate { elements.append($0) }
        return elements
    }
}

private func XCTAssertEqual(
    _ lhs: @autoclosure () throws -> [CGPathElement],
    _ rhs: @autoclosure () throws -> [CGPathElement],
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertNoThrow(_ = try lhs(), file: file, line: line)
    XCTAssertNoThrow(_ = try rhs(), file: file, line: line)
    if let lhs = try? lhs(), let rhs = try? rhs() {
        for (lhs, rhs) in zip(lhs, rhs) {
            XCTAssertEqual(
                lhs.type.rawValue,
                rhs.type.rawValue,
                file: file,
                line: line
            )
            guard lhs.type == rhs.type else {
                return
            }
            switch lhs.type {
            case .addCurveToPoint:
                XCTAssertEqual(
                    lhs.points[2],
                    rhs.points[2],
                    file: file,
                    line: line
                )
                fallthrough
            case .addQuadCurveToPoint:
                XCTAssertEqual(
                    lhs.points[1],
                    rhs.points[1],
                    file: file,
                    line: line
                )
                fallthrough
            case .moveToPoint, .addLineToPoint:
                XCTAssertEqual(
                    lhs.points[0],
                    rhs.points[0],
                    file: file,
                    line: line
                )
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
    }
}

private func XCTAssertEqual(
    _ lhs: @autoclosure () throws -> CGPath,
    _ rhs: @autoclosure () throws -> CGPath,
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertNoThrow(_ = try lhs(), file: file, line: line)
    XCTAssertNoThrow(_ = try rhs(), file: file, line: line)
    if let lhs = try? lhs(), let rhs = try? rhs() {
        XCTAssertEqual(lhs.elements, rhs.elements, file: file, line: line)
    }
}

class CGPathTests: XCTestCase {
    func testTriangle() throws {
        let svgPath = try SVGPath(string: "M150 0 L75 200 L225 200 Z")
        let cgPath = CGMutablePath()
        cgPath.move(to: CGPoint(x: 150, y: 0))
        cgPath.addLine(to: CGPoint(x: 75, y: -200))
        cgPath.addLine(to: CGPoint(x: 225, y: -200))
        cgPath.closeSubpath()
        XCTAssertEqual(.from(svgPath: svgPath), cgPath)
        XCTAssertEqual(SVGPath(cgPath: cgPath), svgPath)
    }

    func testTriangleString() {
        let svgPath = "M150 0 L75 200 L225 200 Z"
        let cgPath = CGMutablePath()
        cgPath.move(to: CGPoint(x: 150, y: 0))
        cgPath.addLine(to: CGPoint(x: 75, y: -200))
        cgPath.addLine(to: CGPoint(x: 225, y: -200))
        cgPath.closeSubpath()
        XCTAssertEqual(try CGPath.from(svgPath: svgPath), cgPath)
    }

    func testCross() throws {
        let svgPath =
            try SVGPath(string: "M2 1 h1 v1 h1 v1 h-1 v1 h-1 v-1 h-1 v-1 h1 z")
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
        XCTAssertEqual(.from(svgPath: svgPath), cgPath)
        XCTAssertEqual(SVGPath(cgPath: cgPath), svgPath)
    }

    func testHeart() throws {
        let svgPath = try SVGPath(string: """
        M213.1,6.7c-32.4-14.4-73.7,0-88.1,30.6C110.6,4.9,67.5-9.5,36.9,6.7
        C2.8,22.9-13.4,62.4,13.5,110.9 C33.3,145.1,67.5,170.3,125,217
        c59.3-46.7,93.5-71.9,111.5-106.1C263.4,64.2,247.2,22.9,213.1,6.7z
        """)
        let cgPath = CGPath.from(svgPath: svgPath)
        XCTAssertEqual(SVGPath(cgPath: cgPath), svgPath)
    }

    func testNumbersWithoutSeparator() throws {
        let svgPath = try SVGPath(string: "M0 0L-.57.13Z")
        let cgPath = CGMutablePath()
        cgPath.move(to: .zero)
        cgPath.addLine(to: CGPoint(x: -0.57, y: -0.13))
        cgPath.closeSubpath()
        XCTAssertEqual(.from(svgPath: svgPath), cgPath)
        XCTAssertEqual(SVGPath(cgPath: cgPath), svgPath)
    }

    func testAbsoluteHorizontalRule() throws {
        let svgPath = try SVGPath(string: "M0 0L10 10H0Z")
        let cgPath = CGMutablePath()
        cgPath.move(to: .zero)
        cgPath.addLine(to: CGPoint(x: 10, y: -10))
        cgPath.addLine(to: CGPoint(x: 0, y: -10))
        cgPath.closeSubpath()
        XCTAssertEqual(.from(svgPath: svgPath), cgPath)
        XCTAssertEqual(SVGPath(cgPath: cgPath), svgPath)
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
        let cgPath = CGMutablePath()
        cgPath.move(to: CGPoint(x: 150, y: 0))
        cgPath.addLine(to: CGPoint(x: 75, y: -200))
        cgPath.addLine(to: CGPoint(x: 225, y: -200))
        cgPath.closeSubpath()
        XCTAssertEqual(.from(svgPath: svgPath), cgPath)
        XCTAssertEqual(SVGPath(cgPath: cgPath), svgPath)
    }

    func testScientificNotationNumbers() throws {
        let svgPath = try SVGPath(string: "M150 0e0 L75 200e-0 225E+0 200E-0 Z")
        let cgPath = CGMutablePath()
        cgPath.move(to: CGPoint(x: 150, y: 0))
        cgPath.addLine(to: CGPoint(x: 75, y: -200))
        cgPath.addLine(to: CGPoint(x: 225, y: -200))
        cgPath.closeSubpath()
        XCTAssertEqual(.from(svgPath: svgPath), cgPath)
        XCTAssertEqual(SVGPath(cgPath: cgPath), svgPath)
    }

    func testImplicitLines() throws {
        let svgPath = try SVGPath(string: "M150 0 75 200 225 200 Z")
        let cgPath = CGMutablePath()
        cgPath.move(to: CGPoint(x: 150, y: 0))
        cgPath.addLine(to: CGPoint(x: 75, y: -200))
        cgPath.addLine(to: CGPoint(x: 225, y: -200))
        cgPath.closeSubpath()
        XCTAssertEqual(.from(svgPath: svgPath), cgPath)
        XCTAssertEqual(SVGPath(cgPath: cgPath), svgPath)
    }
}

#endif
