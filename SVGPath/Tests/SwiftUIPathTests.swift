//
//  SwiftUIPathTests.swift
//  SVGPathTests
//
//  Created by Nick Lockwood on 25/12/2025.
//  Copyright © 2025 Nick Lockwood. All rights reserved.
//

#if canImport(SwiftUI)

@testable import SVGPath
import SwiftUI
import XCTest

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
final class SwiftUIPathTests: XCTestCase {
    func testTriangleFromSVGPath() throws {
        let svgPath = try SVGPath(string: "M150 0 L75 200 L225 200 Z", with: .init(invertYAxis: false))
        let path = Path(svgPath)

        var expectedPath = Path()
        expectedPath.move(to: CGPoint(x: 150, y: 0))
        expectedPath.addLine(to: CGPoint(x: 75, y: 200))
        expectedPath.addLine(to: CGPoint(x: 225, y: 200))
        expectedPath.closeSubpath()

        XCTAssertEqual(path, expectedPath)
    }

    func testTriangleFromString() throws {
        let path = try Path(svgPath: "M150 0 L75 200 L225 200 Z")

        var expectedPath = Path()
        expectedPath.move(to: CGPoint(x: 150, y: 0))
        expectedPath.addLine(to: CGPoint(x: 75, y: 200))
        expectedPath.addLine(to: CGPoint(x: 225, y: 200))
        expectedPath.closeSubpath()

        XCTAssertEqual(path, expectedPath)
    }

    func testInvalidPathThrows() {
        XCTAssertThrowsError(try Path(svgPath: "M150 0 X75 200 Z")) { error in
            XCTAssertTrue(error is SVGError)
        }
    }

    func testPathScaledToRect() throws {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = try Path(svgPath: "M0 0 L200 0 L200 200 L0 200 Z", in: rect)
        let bounds = path.boundingRect

        XCTAssertEqual(bounds.width, 100, accuracy: 0.001)
        XCTAssertEqual(bounds.height, 100, accuracy: 0.001)
    }

    func testPathScaledToRectMaintainsAspectRatio() throws {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 200)
        let path = try Path(svgPath: "M0 0 L100 0 L100 100 L0 100 Z", in: rect)
        let bounds = path.boundingRect

        // Square path scaled to fit in 100x200 rect should be 100x100
        XCTAssertEqual(bounds.width, 100, accuracy: 0.001)
        XCTAssertEqual(bounds.height, 100, accuracy: 0.001)
    }

    func testPathScaledToRectCentered() throws {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = try Path(svgPath: "M0 0 L100 0 L100 100 L0 100 Z", in: rect)
        let bounds = path.boundingRect

        // Square path scaled to fit in 200x100 rect should be centered horizontally
        XCTAssertEqual(bounds.width, 100, accuracy: 0.001)
        XCTAssertEqual(bounds.height, 100, accuracy: 0.001)
        XCTAssertEqual(bounds.midX, 100, accuracy: 0.001)
    }

    func testConvertPathToSVGPath() throws {
        let originalPath = try Path(svgPath: "M10 10 L20 10 L20 20 L10 20 Z")
        let svgPath = SVGPath(originalPath)

        XCTAssertEqual(svgPath.commands.count, 5)
        if case let .moveTo(point) = svgPath.commands[0] {
            XCTAssertEqual(point.x, 10, accuracy: 0.001)
            XCTAssertEqual(point.y, 10, accuracy: 0.001)
        } else {
            XCTFail("Expected moveTo command")
        }
    }

    func testRoundTripConversion() throws {
        let originalString = "M10 10 L20 10 L20 20 L10 20 Z"
        let path = try Path(svgPath: originalString)
        let svgPath = SVGPath(path)
        let recreatedPath = Path(svgPath, in: nil)

        XCTAssertEqual(
            path.boundingRect.width,
            recreatedPath.boundingRect.width,
            accuracy: 0.001
        )
        XCTAssertEqual(
            path.boundingRect.height,
            recreatedPath.boundingRect.height,
            accuracy: 0.001
        )
    }

    func testHeart() throws {
        let path = try Path(svgPath: """
        M213.1,6.7c-32.4-14.4-73.7,0-88.1,30.6C110.6,4.9,67.5-9.5,36.9,6.7
        C2.8,22.9-13.4,62.4,13.5,110.9C33.3,145.1,67.5,170.3,125,217
        c59.3-46.7,93.5-71.9,111.5-106.1C263.4,64.2,247.2,22.9,213.1,6.7z
        """)

        let bounds = path.boundingRect
        XCTAssertGreaterThan(bounds.width, 0)
        XCTAssertGreaterThan(bounds.height, 0)
    }

    func testHeartScaledToRect() throws {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 100)
        let unscaledPath = try Path(svgPath: """
        M213.1,6.7c-32.4-14.4-73.7,0-88.1,30.6C110.6,4.9,67.5-9.5,36.9,6.7
        C2.8,22.9-13.4,62.4,13.5,110.9C33.3,145.1,67.5,170.3,125,217
        c59.3-46.7,93.5-71.9,111.5-106.1C263.4,64.2,247.2,22.9,213.1,6.7z
        """)
        let scaledPath = try Path(svgPath: """
        M213.1,6.7c-32.4-14.4-73.7,0-88.1,30.6C110.6,4.9,67.5-9.5,36.9,6.7
        C2.8,22.9-13.4,62.4,13.5,110.9C33.3,145.1,67.5,170.3,125,217
        c59.3-46.7,93.5-71.9,111.5-106.1C263.4,64.2,247.2,22.9,213.1,6.7z
        """, in: rect)

        // Verify the scaled path is smaller than the unscaled path
        XCTAssertLessThan(scaledPath.boundingRect.width, unscaledPath.boundingRect.width)
        XCTAssertLessThan(scaledPath.boundingRect.height, unscaledPath.boundingRect.height)

        // Verify the path fits within or near the target rect
        XCTAssertGreaterThanOrEqual(scaledPath.boundingRect.minX, rect.minX - 10)
        XCTAssertGreaterThanOrEqual(scaledPath.boundingRect.minY, rect.minY - 10)
    }

    func testEmptyPath() throws {
        let svgPath = try SVGPath(string: "")
        XCTAssertTrue(svgPath.commands.isEmpty)
    }

    func testQuadraticCurve() throws {
        let path = try Path(svgPath: "M0 0 Q50 100 100 0")

        var expectedPath = Path()
        expectedPath.move(to: CGPoint(x: 0, y: 0))
        expectedPath.addQuadCurve(to: CGPoint(x: 100, y: 0), control: CGPoint(x: 50, y: 100))

        XCTAssertEqual(path, expectedPath)
    }

    func testCubicCurve() throws {
        let path = try Path(svgPath: "M0 0 C25 100 75 100 100 0")

        var expectedPath = Path()
        expectedPath.move(to: CGPoint(x: 0, y: 0))
        expectedPath.addCurve(
            to: CGPoint(x: 100, y: 0),
            control1: CGPoint(x: 25, y: 100),
            control2: CGPoint(x: 75, y: 100)
        )

        XCTAssertEqual(path, expectedPath)
    }
}

#endif
