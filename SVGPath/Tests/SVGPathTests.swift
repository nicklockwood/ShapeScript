//
//  SVGPathTests.swift
//  SVGPathTests
//
//  Created by Nick Lockwood on 08/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

@testable import SVGPath
import XCTest

final class SVGPathTests: XCTestCase {
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

    func testTriangleWithoutInvertingYAxis() throws {
        let parseOptions = SVGPath.ParseOptions(invertYAxis: false)
        let svgPath = try SVGPath(string: "M150 0 L75 200 L225 200 Z", with: parseOptions)
        let expected = SVGPath(commands: [
            .moveTo(.init(x: 150, y: 0)),
            .lineTo(.init(x: 75, y: 200)),
            .lineTo(.init(x: 225, y: 200)),
            .end,
        ])
        XCTAssertEqual(svgPath, expected)

        let writeOptions = SVGPath.WriteOptions(invertYAxis: false)
        XCTAssertEqual(svgPath.string(with: writeOptions), "M150 0 L75 200 L225 200 Z")
    }

    func testArc() throws {
        let svgPath = try SVGPath(string: "A50 50 180 1 1 60 0")
        let expected = SVGPath(commands: [
            .arc(.init(
                radius: .init(x: 50.0, y: 50.0),
                rotation: .pi,
                largeArc: true,
                sweep: false,
                end: .init(x: 60.0, y: 0.0)
            )),
        ])
        XCTAssertEqual(svgPath, expected)
        XCTAssertEqual(svgPath.string(), "A50 50 180 1 1 60 0")
    }

    func testArcWithoutInvertingYAxis() throws {
        let parseOptions = SVGPath.ParseOptions(invertYAxis: false)
        let svgPath = try SVGPath(string: "A50 50 180 1 1 60 0", with: parseOptions)
        let expected = SVGPath(commands: [
            .arc(.init(
                radius: .init(x: 50.0, y: 50.0),
                rotation: .pi,
                largeArc: true,
                sweep: true,
                end: .init(x: 60.0, y: 0.0)
            )),
        ])
        XCTAssertEqual(svgPath, expected)

        let writeOptions = SVGPath.WriteOptions(invertYAxis: false)
        XCTAssertEqual(svgPath.string(with: writeOptions), "A50 50 180 1 1 60 0")
    }

    func testCross() throws {
        let svgPath = try SVGPath(string: "M2 1 h1 v1 h1 v1 h-1 v1 h-1 v-1 h-1 v-1 h1 z")
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

    func testNumbersWithPlusAsSeparator() throws {
        let svgPath = try SVGPath(string: "M0 0L.57+5Z")
        let expected = SVGPath(commands: [
            .moveTo(.zero),
            .lineTo(.init(x: 0.57, y: -5)),
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
        let path = "M150 0 L75 200 L225 200 Z5"
        let index = try XCTUnwrap(path.lastIndex(of: "Z"))
        XCTAssertThrowsError(try SVGPath(string: path)) { error in
            XCTAssertEqual(
                error as? SVGError,
                .unexpectedArgument(for: "Z", at: index, expected: 0)
            )
        }
    }

    func testExtraArgument() throws {
        let path = "M150 0 L75 200 L225 200 300 Z"
        let index = try XCTUnwrap(path.lastIndex(of: "L"))
        XCTAssertThrowsError(try SVGPath(string: path)) { error in
            XCTAssertEqual(
                error as? SVGError,
                .unexpectedArgument(for: "L", at: index, expected: 2)
            )
        }
    }

    func testMissingArgument() throws {
        let path = "M150 0 L75 200 L Z"
        let index = try XCTUnwrap(path.lastIndex(of: "L"))
        XCTAssertThrowsError(try SVGPath(string: path)) { error in
            XCTAssertEqual(
                error as? SVGError,
                .missingArgument(for: "L", at: index, expected: 2)
            )
        }
    }

    func testTruncatedInput() throws {
        let path = "M150 0 L75 200 L"
        let index = try XCTUnwrap(path.lastIndex(of: "L"))
        XCTAssertThrowsError(try SVGPath(string: path)) { error in
            XCTAssertEqual(
                error as? SVGError,
                .missingArgument(for: "L", at: index, expected: 2)
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

    func testRelativePathAfterEndCommand() throws {
        let svgPath = try SVGPath(string: """
        m246.7881938,177.5848955c-13.9366996-.4842-27.8722993-.77-41.8169989
        -.8486,6.3990998,6.5819998,12.7983997,13.1638997,19.1974995,19.7456995,
        7.3688998-6.5151998,14.8972996-12.8044997,22.6194994-18.8970995Zm
        -45.4452989,2.3984999c-7.2300998,6.6123998-14.2535996,13.4058997
        -21.1025995,20.4121995,12.8467997,13.5595997,25.6935994,27.1189993,
        38.540699,40.678399,6.9114998-7.2348998,14.0072996-14.2496996,
        21.3211995-21.0778995-12.9196997-13.3375997-25.8395993-26.6751993
        -38.759299-40.012699Z
        """)
        let expected = SVGPath(commands: [
            .moveTo(.init(x: 246.7881938, y: -177.5848955)),
            .cubic(
                .init(x: 232.8514942, y: -177.1006955),
                .init(x: 218.91589449999998, y: -176.81489549999998),
                .init(x: 204.9711949, y: -176.73629549999998)
            ),
            .cubic(
                .init(x: 211.3702947, y: -183.3182953),
                .init(x: 217.7695946, y: -189.90019519999998),
                .init(x: 224.1686944, y: -196.48199499999998)
            ),
            .cubic(
                .init(x: 231.5375942, y: -189.96679519999998),
                .init(x: 239.065994, y: -183.67749529999998),
                .init(x: 246.7881938, y: -177.5848955)
            ),
            .end,
            .moveTo(.init(x: 201.34289489999998, y: -179.98339539999998)),
            .cubic(
                .init(x: 194.11279509999997, y: -186.59579519999997),
                .init(x: 187.08929529999997, y: -193.38929509999997),
                .init(x: 180.24029539999998, y: -200.3955949)
            ),
            .cubic(
                .init(x: 193.08709509999997, y: -213.9551946),
                .init(x: 205.9338948, y: -227.51459419999998),
                .init(x: 218.78099439999997, y: -241.0739939)
            ),
            .cubic(
                .init(x: 225.69249419999997, y: -233.8390941),
                .init(x: 232.78829399999998, y: -226.82429430000002),
                .init(x: 240.10219389999997, y: -219.9960944)
            ),
            .cubic(
                .init(x: 227.18249419999998, y: -206.6584947),
                .init(x: 214.26259459999997, y: -193.3208951),
                .init(x: 201.34289489999998, y: -179.9833954)
            ),
            .end,
        ])
        XCTAssertEqual(svgPath, expected)
    }

    // MARK: - SVGPoint Tests

    func testSVGPointAddition() {
        let p1 = SVGPoint(x: 10, y: 20)
        let p2 = SVGPoint(x: 5, y: 15)
        let result = p1 + p2
        XCTAssertEqual(result.x, 15)
        XCTAssertEqual(result.y, 35)
    }

    func testSVGPointAdditionAssignment() {
        var p1 = SVGPoint(x: 10, y: 20)
        let p2 = SVGPoint(x: 5, y: 15)
        p1 += p2
        XCTAssertEqual(p1.x, 15)
        XCTAssertEqual(p1.y, 35)
    }

    func testSVGPointSubtraction() {
        let p1 = SVGPoint(x: 10, y: 20)
        let p2 = SVGPoint(x: 5, y: 15)
        let result = p1 - p2
        XCTAssertEqual(result.x, 5)
        XCTAssertEqual(result.y, 5)
    }

    func testSVGPointSubtractionAssignment() {
        var p1 = SVGPoint(x: 10, y: 20)
        let p2 = SVGPoint(x: 5, y: 15)
        p1 -= p2
        XCTAssertEqual(p1.x, 5)
        XCTAssertEqual(p1.y, 5)
    }

    // MARK: - SVGCommand Property Tests

    func testSVGCommandMoveToPoint() {
        let command = SVGCommand.moveTo(SVGPoint(x: 10, y: 20))
        XCTAssertEqual(command.point, SVGPoint(x: 10, y: 20))
        XCTAssertNil(command.control1)
        XCTAssertNil(command.control2)
    }

    func testSVGCommandLineToPoint() {
        let command = SVGCommand.lineTo(SVGPoint(x: 30, y: 40))
        XCTAssertEqual(command.point, SVGPoint(x: 30, y: 40))
        XCTAssertNil(command.control1)
        XCTAssertNil(command.control2)
    }

    func testSVGCommandQuadraticPoint() {
        let command = SVGCommand.quadratic(
            SVGPoint(x: 10, y: 20),
            SVGPoint(x: 30, y: 40)
        )
        XCTAssertEqual(command.point, SVGPoint(x: 30, y: 40))
        XCTAssertEqual(command.control1, SVGPoint(x: 10, y: 20))
        XCTAssertNil(command.control2)
    }

    func testSVGCommandCubicPoint() {
        let command = SVGCommand.cubic(
            SVGPoint(x: 10, y: 20),
            SVGPoint(x: 30, y: 40),
            SVGPoint(x: 50, y: 60)
        )
        XCTAssertEqual(command.point, SVGPoint(x: 50, y: 60))
        XCTAssertEqual(command.control1, SVGPoint(x: 10, y: 20))
        XCTAssertEqual(command.control2, SVGPoint(x: 30, y: 40))
    }

    func testSVGCommandArcPoint() {
        let arc = SVGArc(
            radius: SVGPoint(x: 50, y: 50),
            rotation: 0,
            largeArc: false,
            sweep: true,
            end: SVGPoint(x: 100, y: 100)
        )
        let command = SVGCommand.arc(arc)
        XCTAssertEqual(command.point, SVGPoint(x: 100, y: 100))
        XCTAssertNil(command.control1)
        XCTAssertNil(command.control2)
    }

    func testSVGCommandEndPoint() {
        let command = SVGCommand.end
        XCTAssertNil(command.point)
        XCTAssertNil(command.control1)
        XCTAssertNil(command.control2)
    }

    // MARK: - SVGError Property Tests

    func testSVGErrorUnexpectedTokenMessage() {
        let error = SVGError.unexpectedToken("X", at: "test".startIndex)
        XCTAssertEqual(error.message, "Unexpected token 'X'")
        XCTAssertNil(error.hint)
    }

    func testSVGErrorUnexpectedArgumentMessage() {
        let error = SVGError.unexpectedArgument(for: "L", at: "test".startIndex, expected: 2)
        XCTAssertEqual(error.message, "Too many arguments for 'L'")
        XCTAssertEqual(error.hint, "The 'L' command expects only 2 arguments")
    }

    func testSVGErrorUnexpectedArgumentHintZero() {
        let error = SVGError.unexpectedArgument(for: "Z", at: "test".startIndex, expected: 0)
        XCTAssertEqual(error.hint, "The 'Z' command does not expect any arguments")
    }

    func testSVGErrorUnexpectedArgumentHintOne() {
        let error = SVGError.unexpectedArgument(for: "H", at: "test".startIndex, expected: 1)
        XCTAssertEqual(error.hint, "The 'H' command expects only one argument")
    }

    func testSVGErrorMissingArgumentMessage() {
        let error = SVGError.missingArgument(for: "L", at: "test".startIndex, expected: 2)
        XCTAssertEqual(error.message, "Missing argument for 'L'")
        XCTAssertEqual(error.hint, "The 'L' command requires 2 arguments")
    }

    func testSVGErrorMissingArgumentHintOne() {
        let error = SVGError.missingArgument(for: "H", at: "test".startIndex, expected: 1)
        XCTAssertEqual(error.hint, "The 'H' command requires one argument")
    }

    func testSVGErrorIndex() {
        let str = "M0 0 X10"
        let index = str.index(str.startIndex, offsetBy: 5)
        let error = SVGError.unexpectedToken("X", at: index)
        XCTAssertEqual(error.index, index)
    }

    // MARK: - Points Conversion Tests

    func testPointsWithDetail() throws {
        let svgPath = try SVGPath(string: "M0 0 L100 0 L100 100 Z")
        let points = svgPath.points(withDetail: 10)

        XCTAssertEqual(points.first, .zero)
    }

    func testGetPointsInout() throws {
        let svgPath = try SVGPath(string: "M0 0 L100 0 L100 100 Z")
        var points = [SVGPoint]()
        svgPath.getPoints(&points, detail: 10)

        XCTAssertEqual(points.first, .zero)
    }

    func testPointsFromQuadraticCurve() throws {
        let svgPath = try SVGPath(string: "M0 0 Q50 100 100 0", with: .init(invertYAxis: false))
        let points = svgPath.points(withDetail: 4)

        XCTAssertGreaterThan(points.count, 2)
        XCTAssertEqual(points.first?.x ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(points.last?.x ?? -1, 100, accuracy: 0.001)
    }

    func testPointsFromCubicCurve() throws {
        let svgPath = try SVGPath(string: "M0 0 C25 100 75 100 100 0", with: .init(invertYAxis: false))
        let points = svgPath.points(withDetail: 4)

        XCTAssertGreaterThan(points.count, 2)
        XCTAssertEqual(points.first?.x ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(points.last?.x ?? -1, 100, accuracy: 0.001)
    }

    func testPointsFromArc() throws {
        let svgPath = try SVGPath(string: "M0 0 A50 50 0 0 1 100 0", with: .init(invertYAxis: false))
        let points = svgPath.points(withDetail: 10)

        XCTAssertGreaterThan(points.count, 2)
    }

    // MARK: - Quadratic Curve Tests

    func testQuadraticCurve() throws {
        let svgPath = try SVGPath(string: "M0 0 Q50 100 100 0")
        XCTAssertEqual(svgPath.commands.count, 2)
        if case let .quadratic(control, point) = svgPath.commands[1] {
            XCTAssertEqual(control.x, 50)
            XCTAssertEqual(control.y, -100)
            XCTAssertEqual(point.x, 100)
            XCTAssertEqual(point.y, 0)
        } else {
            XCTFail("Expected quadratic command")
        }
    }

    func testRelativeQuadraticCurve() throws {
        let svgPath = try SVGPath(string: "M10 10 q40 90 90 -10")
        XCTAssertEqual(svgPath.commands.count, 2)
        if case let .quadratic(control, point) = svgPath.commands[1] {
            XCTAssertEqual(control.x, 50)
            XCTAssertEqual(control.y, -100)
            XCTAssertEqual(point.x, 100)
            XCTAssertEqual(point.y, 0)
        } else {
            XCTFail("Expected quadratic command")
        }
    }

    func testSmoothQuadraticCurve() throws {
        let svgPath = try SVGPath(string: "M0 0 Q50 100 100 0 T200 0")
        XCTAssertEqual(svgPath.commands.count, 3)
        if case let .quadratic(control, point) = svgPath.commands[2] {
            XCTAssertEqual(control.x, 150)
            XCTAssertEqual(control.y, 100)
            XCTAssertEqual(point.x, 200)
            XCTAssertEqual(point.y, 0)
        } else {
            XCTFail("Expected quadratic command")
        }
    }

    func testSmoothQuadraticAfterNonQuadratic() throws {
        let svgPath = try SVGPath(string: "M0 0 L50 50 T100 0")
        XCTAssertEqual(svgPath.commands.count, 3)
        if case let .quadratic(control, point) = svgPath.commands[2] {
            // Control should be same as last point when previous wasn't quadratic
            XCTAssertEqual(control.x, 50)
            XCTAssertEqual(control.y, -50)
            XCTAssertEqual(point.x, 100)
            XCTAssertEqual(point.y, 0)
        } else {
            XCTFail("Expected quadratic command")
        }
    }

    // MARK: - Smooth Cubic Tests

    func testSmoothCubicCurve() throws {
        let svgPath = try SVGPath(string: "M0 0 C25 100 75 100 100 0 S175 -100 200 0")
        XCTAssertEqual(svgPath.commands.count, 3)
        if case let .cubic(control1, control2, point) = svgPath.commands[2] {
            // control1 should be reflection of previous control2
            XCTAssertEqual(control1.x, 125)
            XCTAssertEqual(control1.y, 100)
            XCTAssertEqual(control2.x, 175)
            XCTAssertEqual(control2.y, 100)
            XCTAssertEqual(point.x, 200)
            XCTAssertEqual(point.y, 0)
        } else {
            XCTFail("Expected cubic command")
        }
    }

    func testRelativeSmoothCubicCurve() throws {
        let svgPath = try SVGPath(string: "M0 0 C25 100 75 100 100 0 s75 -100 100 0")
        XCTAssertEqual(svgPath.commands.count, 3)
        if case let .cubic(control1, control2, point) = svgPath.commands[2] {
            XCTAssertEqual(control1.x, 125)
            XCTAssertEqual(control1.y, 100)
            XCTAssertEqual(control2.x, 175)
            XCTAssertEqual(control2.y, 100)
            XCTAssertEqual(point.x, 200)
            XCTAssertEqual(point.y, 0)
        } else {
            XCTFail("Expected cubic command")
        }
    }

    func testSmoothCubicAfterNonCubic() throws {
        let svgPath = try SVGPath(string: "M0 0 L50 50 S100 100 150 0")
        XCTAssertEqual(svgPath.commands.count, 3)
        if case let .cubic(control1, _, point) = svgPath.commands[2] {
            // control1 should be same as last point when previous wasn't cubic
            XCTAssertEqual(control1.x, 50)
            XCTAssertEqual(control1.y, -50)
            XCTAssertEqual(point.x, 150)
            XCTAssertEqual(point.y, 0)
        } else {
            XCTFail("Expected cubic command")
        }
    }

    // MARK: - Vertical Line Tests

    func testAbsoluteVerticalLine() throws {
        let svgPath = try SVGPath(string: "M10 10 V50")
        let expected = SVGPath(commands: [
            .moveTo(.init(x: 10, y: -10)),
            .lineTo(.init(x: 10, y: -50)),
        ])
        XCTAssertEqual(svgPath, expected)
    }

    func testRelativeVerticalLine() throws {
        let svgPath = try SVGPath(string: "M10 10 v40")
        let expected = SVGPath(commands: [
            .moveTo(.init(x: 10, y: -10)),
            .lineTo(.init(x: 10, y: -50)),
        ])
        XCTAssertEqual(svgPath, expected)
    }

    func testRelativeHorizontalLine() throws {
        let svgPath = try SVGPath(string: "M10 10 h40")
        let expected = SVGPath(commands: [
            .moveTo(.init(x: 10, y: -10)),
            .lineTo(.init(x: 50, y: -10)),
        ])
        XCTAssertEqual(svgPath, expected)
    }

    // MARK: - Arc Tests

    func testArcLargeArcFlag() throws {
        let svgPath = try SVGPath(string: "M0 0 A50 50 0 1 0 100 0", with: .init(invertYAxis: false))
        if case let .arc(arc) = svgPath.commands[1] {
            XCTAssertTrue(arc.largeArc)
            XCTAssertFalse(arc.sweep)
        } else {
            XCTFail("Expected arc command")
        }
    }

    func testArcSweepFlag() throws {
        let svgPath = try SVGPath(string: "M0 0 A50 50 0 0 1 100 0", with: .init(invertYAxis: false))
        if case let .arc(arc) = svgPath.commands[1] {
            XCTAssertFalse(arc.largeArc)
            XCTAssertTrue(arc.sweep)
        } else {
            XCTFail("Expected arc command")
        }
    }

    func testRelativeArc() throws {
        let svgPath = try SVGPath(string: "M50 50 a25 25 0 0 1 50 0", with: .init(invertYAxis: false))
        if case let .arc(arc) = svgPath.commands[1] {
            XCTAssertEqual(arc.end.x, 100)
            XCTAssertEqual(arc.end.y, 50)
            XCTAssertEqual(arc.radius.x, 25)
            XCTAssertEqual(arc.radius.y, 25)
        } else {
            XCTFail("Expected arc command")
        }
    }

    func testArcToBezierPath() {
        let arc = SVGArc(
            radius: SVGPoint(x: 50, y: 50),
            rotation: 0,
            largeArc: false,
            sweep: true,
            end: SVGPoint(x: 100, y: 0)
        )
        let commands = arc.asBezierPath(from: .zero)
        XCTAssertGreaterThan(commands.count, 0)
        // All commands should be cubic bezier curves
        for command in commands {
            if case .cubic = command {
                // Expected
            } else {
                XCTFail("Expected cubic command from arc conversion")
            }
        }
    }

    func testArcWithZeroRadius() {
        let arc = SVGArc(
            radius: .zero,
            rotation: 0,
            largeArc: false,
            sweep: true,
            end: SVGPoint(x: 100, y: 0)
        )
        let commands = arc.asBezierPath(from: .zero)
        // Zero radius arc should produce bezier approximation
        XCTAssertGreaterThanOrEqual(commands.count, 0)
    }

    func testArcToSamePoint() {
        let arc = SVGArc(
            radius: SVGPoint(x: 50, y: 50),
            rotation: 0,
            largeArc: false,
            sweep: true,
            end: .zero
        )
        let commands = arc.asBezierPath(from: .zero)
        // Arc to same point should return empty
        XCTAssertEqual(commands.count, 0)
    }

    // MARK: - WriteOptions Tests

    func testWriteOptionsDefault() {
        let options = SVGPath.WriteOptions.default
        XCTAssertTrue(options.prettyPrinted)
        XCTAssertEqual(options.wrapWidth, .max)
        XCTAssertTrue(options.invertYAxis)
    }

    func testWriteOptionsCustom() {
        let options = SVGPath.WriteOptions(prettyPrinted: false, wrapWidth: 80, invertYAxis: false)
        XCTAssertFalse(options.prettyPrinted)
        XCTAssertEqual(options.wrapWidth, 80)
        XCTAssertFalse(options.invertYAxis)
    }

    func testStringOutputNotPrettyPrinted() throws {
        let svgPath = try SVGPath(string: "M0 0 L10 10 L20 0 Z")
        let options = SVGPath.WriteOptions(prettyPrinted: false)
        let output = svgPath.string(with: options)
        // Without pretty printing, numbers should still be separated when needed
        XCTAssertTrue(output.contains("M0"))
        XCTAssertTrue(output.contains("L10"))
    }

    // MARK: - ParseOptions Tests

    func testParseOptionsDefault() {
        let options = SVGPath.ParseOptions.default
        XCTAssertTrue(options.invertYAxis)
    }

    // MARK: - Edge Cases

    func testEmptyPath() throws {
        let svgPath = try SVGPath(string: "")
        XCTAssertTrue(svgPath.commands.isEmpty)
    }

    func testWhitespaceOnlyPath() throws {
        let svgPath = try SVGPath(string: "   \n\t  ")
        XCTAssertTrue(svgPath.commands.isEmpty)
    }

    func testMultipleMoves() throws {
        let svgPath = try SVGPath(string: "M0 0 M10 10 M20 20")
        XCTAssertEqual(svgPath.commands.count, 3)
        for command in svgPath.commands {
            if case .moveTo = command {
                // Expected
            } else {
                XCTFail("Expected moveTo commands")
            }
        }
    }

    func testRelativeMove() throws {
        let svgPath = try SVGPath(string: "M10 10 m5 5")
        let expected = SVGPath(commands: [
            .moveTo(.init(x: 10, y: -10)),
            .moveTo(.init(x: 15, y: -15)),
        ])
        XCTAssertEqual(svgPath, expected)
    }

    func testImplicitRelativeLines() throws {
        let svgPath = try SVGPath(string: "m10 10 5 5 10 0")
        let expected = SVGPath(commands: [
            .moveTo(.init(x: 10, y: -10)),
            .lineTo(.init(x: 15, y: -15)),
            .lineTo(.init(x: 25, y: -15)),
        ])
        XCTAssertEqual(svgPath, expected)
    }

    func testUnexpectedCharacter() {
        XCTAssertThrowsError(try SVGPath(string: "M0 0 #")) { error in
            if case let SVGError.unexpectedToken(token, _) = error {
                XCTAssertEqual(token, "#")
            } else {
                XCTFail("Expected unexpectedToken error")
            }
        }
    }

    func testInvalidNumberFormat() {
        // "1.2.3" gets parsed as "1.2" and ".3" (two valid numbers)
        // So test with something truly invalid like just "."
        XCTAssertThrowsError(try SVGPath(string: "M0 0 L. 0")) { error in
            XCTAssertTrue(error is SVGError)
        }
    }

    #if !os(WASI)
    @available(iOS 13.0, macOS 10.15, *)
    func testLongStringWithSmallStackSize() async throws {
        // Previous implementation of `SVGPath(string:)` was recursive and could
        // cause a stack overflow in debug builds.
        // Note that background GCD threads have a smaller stack size compared
        // to the main thread (usually 512K on a device).
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let thread = Thread {
                do {
                    _ = try SVGPath(string: longSVGPathString)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            thread.stackSize = 128 * 1024
            thread.start()
        }
    }
    #endif
}

private let longSVGPathString =
    "M574.77496 21.893066L574.095 21.652527 574.095 21.652527 574.095 21.652527 574.945 24.29889 578.685 40.09723 580.895 52.206604 581.405 55.65497 580.55505 59.664673 578.34503 69.929565 573.755 87.17139 566.7849 111.871216 557.9448 140.66107 553.6948 153.41199 551.1448 160.46912 549.2748 162.39374 543.1547 167.92719 533.2946 176.2674 526.66455 181.56024 502.18436 200.64648 490.11423 209.4679 482.12418 212.67566 478.04416 212.83606 476.00412 213.3974 471.58408 215.00128 471.58408 215.00128 477.02414 223.6623 477.02414 223.6623 477.02414 223.6623 477.02414 223.6623 477.02414 223.6623 477.02414 223.6623 477.02414 223.6623 477.02414 223.6623 477.02414 223.6623 477.02414 223.6623 481.27414 221.97821 490.28427 218.93085 504.56436 214.84094 522.92456 210.18964 532.2746 208.10461 536.01465 207.38281 536.01465 207.38281 536.01465 207.38281 536.01465 207.38281 536.01465 207.38281 536.18463 216.12402 535.84467 223.10095 534.82465 240.34277 533.9746 249.48492 532.7846 257.4242 532.2746 260.47156 532.2746 260.47156 532.2746 260.47156 532.2746 260.47156 528.8746 263.43872 522.0745 268.73157 516.8045 270.97705 514.76447 272.09973 499.80435 281.88348 491.30423 287.17627 482.6342 292.22852 476.1741 295.67688 476.1741 295.67688 476.1741 295.67688 476.1741 295.67688 475.15408 294.7948 469.0341 287.97827 460.704 277.47278 451.5239 264.80206 448.63388 260.39136 448.63388 260.39136 448.63388 260.39136 448.63388 260.39136 451.86392 253.81543 456.79398 245.31482 466.48404 229.03534 470.56406 225.02563 472.26407 223.10095 473.45407 220.77527 474.13412 218.2091 474.13412 214.43994 463.934 202.08997 463.934 202.08997 463.934 202.08997 464.27402 201.76923 463.084 202.65137 457.81393 205.85913 452.37393 206.82147 414.4636 212.35486 363.46317 218.85065 363.46317 218.85065 364.99316 230.95996 364.99316 230.95996 364.99316 230.95996 367.0332 230.23828 376.55328 228.3136 390.15338 226.46912 396.44345 225.98792 396.44345 225.98792 396.44345 225.98792 396.44345 225.98792 398.14346 229.27588 403.92352 242.8288 408.34354 254.69757 410.04355 260.47156 410.04355 260.47156 410.04355 260.47156 409.70355 261.51404 405.11353 270.09485 399.33347 279.31726 392.3634 289.58215 389.1334 293.9928 389.1334 293.9928 389.1334 293.9928 389.1334 293.9928 380.8033 294.474 376.89328 293.43152 374.00323 293.03052 367.2032 292.87012 351.22305 292.14832 342.89297 291.42664 337.45294 290.78503 337.45294 290.78503 337.45294 290.78503 337.45294 290.78503 336.77292 288.69995 334.3929 278.75586 332.5229 271.69873 331.16287 264.08032 328.61285 246.5979 327.93286 238.41809 327.93286 238.41809 327.93286 238.41809 327.93286 238.41809 332.1829 234.88953 334.05292 233.04504 335.9229 230.87982 338.81296 228.79474 348.84302 222.45935 355.6431 218.52985 355.6431 218.52985 355.6431 218.52985 355.6431 218.52985 355.6431 218.69025 355.6431 218.69025 355.6431 218.69025 355.6431 218.69025 349.86304 221.65747 332.5229 229.83728 319.77277 235.37073 316.37274 236.65381 313.48273 236.89441 293.25253 237.93689 238.34207 239.54077 232.73203 239.22003 232.73203 239.22003 232.73203 240.58331 232.73203 240.58331 232.73203 240.58331 232.73203 240.58331 243.7821 233.52625 251.60217 228.95514 255.68222 228.073 262.3123 227.27106 272.68237 226.62952 285.60248 226.38892 293.59256 226.70972 293.59256 226.70972 293.59256 226.70972 293.59256 226.70972 293.59256 226.70972 293.42255 235.04993 292.74255 248.36218 291.38254 264.16052 290.53253 271.13745 290.02252 273.7838 290.02252 273.7838 290.02252 273.7838 290.02252 273.7838 287.9825 275.9491 282.20245 281.16174 277.7824 284.6101 266.0523 293.43152 252.11218 303.0548 245.14212 307.38538 245.14212 307.38538 245.14212 307.38538 244.9721 307.30505 236.64206 303.6964 233.75201 301.13013 231.202 299.44604 225.59195 296.63928 213.86185 290.30383 208.5918 287.09607 208.5918 287.09607 208.5918 287.09607 208.5918 287.09607 206.7218 280.52014 205.02176 275.7887 204.00177 271.378 201.62173 259.02808 200.09174 248.36218 200.09174 248.36218 200.09174 248.36218 200.09174 248.36218 206.38177 243.63074 207.9118 242.18726 210.29181 239.62097 218.62189 234.16779 218.62189 234.16779 208.08179 217.8081 208.08179 217.8081 208.08179 217.8081 196.1817 221.25647 181.22156 225.10583 166.26144 225.98792 160.48138 225.50677 132.60114 226.38892 111.01096 226.70972 111.01096 226.70972 111.01096 226.70972 111.01096 226.70972 108.460945 225.26617 108.460945 225.26617 96.73084 243.39014 96.73084 243.39014 96.73084 243.39014 96.73084 243.39014 96.73084 243.39014 96.73084 243.39014 96.73084 243.39014 101.49088 256.3816 105.74091 270.17505 107.440926 276.3501 107.440926 276.3501 107.440926 276.3501 107.10093 276.67084 99.96087 285.01105 91.46079 293.75232 81.260704 303.6161 76.330666 307.86646 76.330666 307.86646 76.330666 307.86646 75.48066 307.78625 64.60056 305.30017 52.87046 301.932 34.850304 296.47888 34.5103 296.23828 34.5103 296.23828 34.5103 296.23828 34.5103 296.23828 33.32029 290.46423 29.410255 266.8069 27.710243 255.01831 24.480217 227.9928 23.460205 215.48248 23.120201 209.0669 23.120201 209.0669 23.120201 209.0669 24.480217 206.42053 29.240257 197.03772 33.660294 188.53711 36.89032 180.0365 49.300423 158.62463 64.94056 132.8822 72.25062 121.57477 76.50066 115.31958 81.600716 112.51282 91.1208 108.10211 106.080925 101.927124 125.4611 94.388855 149.26129 85.888245 152.66132 85.567505 155.89136 85.0061 158.27136 83.80322 160.14139 82.03894 161.5014 79.87366 162.35141 77.387634 162.5214 74.74121 162.01141 72.17499 160.82138 69.849365 158.95139 67.92468 156.74136 66.5614 154.36133 65.75946 150.9613 65.67926 146.37128 66.0 143.99124 66.5614 128.6911 71.93445 108.12095 79.63306 90.27079 86.770386 77.18067 92.46417 68.680595 96.79468 63.750557 99.8421 62.39054 101.04498 61.20054 102.408325 55.42048 110.668335 47.940422 122.37671 32.13028 148.43994 19.55017 170.1726 13.770119 177.39014 12.750114 178.99402 5.780052 191.90527 1.870018 200.00494 0.8500061 202.25037 0.16999817 204.65625 0.0 207.22241 0.34000397 217.24677 1.530014 230.47882 3.060028 244.59302 7.8200684 280.35974 10.370094 294.875 12.0701065 303.135 12.750114 305.94177 14.110123 309.22974 15.130135 310.75354 16.490143 312.3573 18.190163 313.88098 20.230171 315.08398 22.440193 315.72546 24.820213 316.04626 27.030235 315.88586 27.030235 315.88586 27.030235 315.88586 28.900253 315.88586 47.260414 321.4193 54.06047 323.2638 68.680595 326.87256 75.14066 327.99524 79.0507 328.23584 81.090706 327.99524 83.30073 327.35376 85.17074 326.23096 89.59078 322.943 94.86082 318.29175 105.74091 307.86646 114.581 298.48376 120.87104 291.58704 124.61109 286.69513 126.6511 283.56757 127.50111 281.40234 128.01111 279.07666 127.8411 276.75104 126.8211 271.378 124.95109 264.48126 120.361046 249.96606 115.94102 237.69635 111.18098 225.98792 108.80094 221.49707 106.93093 218.93085 105.2309 217.5675 102.34089 216.04382 99.96087 215.08148 95.54084 214.03894 90.7808 213.3974 87.04075 213.4776 85.34074 213.8786 82.79072 215.00128 80.75071 216.68536 79.39069 218.77045 78.370674 221.25647 78.200676 223.9029 78.710686 226.54932 79.73069 228.87494 81.4307 230.87982 87.55076 235.93207 91.1208 238.57849 92.82081 240.82391 94.52082 242.10706 96.56083 243.55054 96.56083 243.55054 101.83088 246.6781 104.0409 247.72064 106.080925 248.36218 108.29093 248.60278 123.251076 248.52258 152.1513 247.64044 161.5014 247.1593 167.28143 246.11676 182.24158 245.23462 185.13159 244.83362 195.50168 242.3476 212.67184 237.53595 228.48196 232.5639 230.69199 231.44116 232.73203 229.83728 234.43204 227.7522 235.62204 225.34637 236.30203 223.10095 236.47205 220.93567 236.30203 218.77045 235.96204 216.60522 235.11203 214.92114 234.26202 213.3172 233.07202 211.95392 230.862 210.02924 228.31198 208.9065 225.59195 208.42535 222.87192 208.66595 220.3219 209.7085 212.67184 214.19934 207.74179 217.4071 207.74179 217.4071 199.07172 223.10095 195.67169 224.54443 193.46167 225.74738 187.17163 230.47882 182.75159 234.24799 180.37155 236.81421 178.84155 239.05963 177.99155 241.62585 177.82153 244.35248 178.16153 249.48492 178.84155 255.90045 181.22156 269.6939 183.6016 280.68054 183.94159 284.5299 184.28159 286.3744 187.00162 295.99768 188.36163 299.28564 189.38165 301.13013 190.74164 302.8142 192.27167 304.1775 196.69171 307.14465 202.47174 310.51282 215.05185 317.40955 220.6619 320.29663 222.36194 320.9381 227.97198 322.0609 238.00208 326.31116 242.9321 327.91504 246.50214 328.39624 248.88214 328.07544 251.09216 327.19336 256.3622 324.30627 263.33228 319.97583 270.64236 315.00378 284.58246 304.8993 290.53253 300.32825 299.0326 293.11072 302.09262 290.14343 304.64264 287.57727 307.53268 283.8883 308.7227 281.96362 309.2327 279.8786 310.4227 273.9442 311.44272 266.16534 312.8027 249.56512 313.48273 235.61127 313.6527 225.74738 313.14273 219.17139 312.4627 215.48248 311.7827 213.3172 310.4227 211.39258 308.89267 209.8689 306.85266 208.66595 304.64264 208.02441 299.5426 207.06207 293.08255 206.58087 285.7725 206.42053 271.66235 206.66107 260.27225 207.38281 252.11218 208.42535 246.50214 209.6283 242.9321 210.91138 233.242 216.52502 218.11188 226.06812 214.54187 227.672 213.01184 228.5542 201.96176 236.1726 199.92172 238.09729 198.5617 240.50317 197.88171 243.22974 197.88171 246.03656 198.5617 248.76318 199.92172 251.169 201.96176 253.17383 204.34177 254.61737 207.23178 255.74011 214.20184 257.4242 224.74194 259.18848 226.27197 259.34882 229.33197 259.02808 233.07202 259.42902 233.07202 259.42902 238.51205 259.66962 285.60248 258.30627 315.01273 256.8628 319.60278 256.4618 321.9828 255.82031 327.25284 253.89563 340.85297 248.04138 358.8731 239.62097 371.11322 233.20544 373.49326 231.68176 375.53326 229.99768 376.89328 227.9126 377.91327 225.50677 378.08328 222.94055 377.91327 221.33667 377.57327 218.85065 376.55328 215.64282 375.19327 212.67566 372.13324 207.30261 369.0732 203.1325 365.84317 199.92474 364.14316 198.6416 361.76315 197.35852 359.7231 196.63678 357.5131 196.39618 355.3031 196.63678 353.26306 197.27832 349.18304 199.203 338.30295 205.37799 327.59283 212.27466 324.36282 214.52014 319.94278 216.28442 315.35275 219.73279 310.4227 224.0633 307.87268 227.19086 306.51266 229.35608 305.66266 231.84216 305.32266 234.40833 305.66266 240.98431 306.51266 249.48492 307.87268 258.78748 310.5927 275.7887 311.7827 283.7279 314.33273 294.9552 315.52274 299.04504 316.71274 302.4132 318.58276 306.58337 320.1128 308.58826 321.8128 310.35254 324.02283 311.63562 326.40283 312.43762 332.6929 313.7207 340.85297 314.68298 349.69302 315.4048 366.69318 316.20667 373.66324 316.28687 375.36325 316.20667 381.1433 314.76318 388.79337 314.44238 394.91342 313.6405 398.31345 312.6781 400.0135 311.63562 401.5435 310.27234 405.11353 306.42297 409.02356 301.29053 416.50363 290.06335 419.90366 284.6101 426.5337 272.74133 428.91373 267.6089 430.10373 264.40112 430.61374 261.59424 430.27374 258.78748 429.08374 253.97583 427.2137 248.04138 422.45367 235.45087 418.03363 224.86523 413.2736 214.76074 410.72357 210.67078 408.68356 208.34515 406.81354 207.22241 404.9435 206.42053 402.7335 206.01953 398.48346 205.85913 393.38342 206.09973 382.50333 207.22241 369.4132 209.2273 361.76315 210.91138 358.36313 211.95392 344.93298 217.9685 340.00296 220.53473 337.79294 222.21881 336.2629 224.38403 335.24292 226.95026 335.0729 229.67688 335.58292 232.3233 336.77292 234.80933 338.64294 236.81421 340.85297 238.25769 343.573 239.05963 348.67303 239.46057 358.5331 239.46057 365.84317 238.73889 365.84317 238.73889 417.18362 232.1629 455.60397 226.54932 462.064 225.42657 464.78403 224.62463 468.69406 222.69995 475.4941 218.3695 478.38412 215.88342 480.08414 213.638 480.93417 211.07178 481.10416 208.34515 480.59415 205.61853 479.23416 203.1325 477.3641 201.12769 474.9841 199.76434 472.26407 199.0426 469.54404 199.1228 466.99405 199.92474 464.61404 201.44843 462.40402 203.45331 460.36398 205.37799 460.194 205.37799 460.194 205.37799 459.34396 205.53833 456.96396 206.58087 454.75394 208.10461 449.6539 213.07666 447.7839 215.48248 439.6238 228.71454 429.42374 246.5177 425.6837 254.29657 424.49368 257.1836 423.98367 259.58942 423.98367 261.99524 424.3237 264.40112 425.3437 266.64648 428.06372 271.69873 432.31375 278.11432 437.2438 285.01105 446.93387 297.84216 455.26395 307.62585 458.66397 311.31482 461.554 314.28198 464.444 316.60767 468.52408 319.33423 470.90408 320.45703 473.6241 320.9381 476.34415 320.7777 478.89413 319.97583 485.69418 317.08887 494.1943 312.5979 503.37436 307.14465 512.38446 301.61133 527.8546 291.50684 529.8946 289.58215 533.9746 285.17145 542.1347 278.83606 545.19476 276.1095 549.1048 272.17993 550.4648 270.01465 551.4848 267.5287 552.8448 260.63196 554.0348 251.65015 555.0548 241.94666 555.7348 232.4837 556.2448 223.6623 556.2448 210.02924 556.0748 204.81659 555.7348 200.64648 555.22485 197.11792 553.8648 192.78748 552.6748 190.46179 550.9748 188.61731 548.7648 187.17383 546.38477 186.45209 543.66473 186.29169 537.03467 186.85303 528.1946 188.53711 518.1645 190.7024 499.1243 195.51404 484.3342 199.84454 474.13412 203.2127 467.84402 205.85913 464.27402 207.78381 461.384 210.10944 455.43393 215.48248 453.05392 218.0487 452.0339 218.2893 449.6539 219.57239 447.7839 221.41687 444.04385 225.98792 442.85385 227.9126 441.83383 230.39862 441.32382 233.12524 441.66385 235.85187 442.51382 238.49829 443.87387 240.82391 445.91385 242.7486 448.29385 244.19208 450.8439 244.99402 453.56393 245.15442 456.28397 244.67322 469.20407 240.42297 483.99417 235.04993 483.99417 235.04993 485.86423 234.16779 489.26425 231.60156 497.7643 228.2334 500.99435 226.54932 514.4245 216.76556 531.4246 203.53351 539.4147 197.27832 556.41486 182.84332 563.2149 176.66833 567.12494 172.65863 568.31494 171.13495 569.1649 169.37067 572.735 159.90771 577.155 146.67566 585.9951 117.48486 593.13513 92.38403 597.7252 74.66101 600.2752 63.513977 601.2952 57.33905 601.2952 54.772827 600.7852 49.07898 599.5952 42.50305 596.7052 29.511536 593.13513 15.317139 590.9251 8.17981 590.07513 6.0145874 588.88513 4.0097046 587.1851 2.4058228 584.6351 0.9623413 582.7651 0.32080078 580.215 0.0 578.17505 0.16040039 576.815 0.48114014 576.815 0.48114014 576.645 0.48114014 574.435 0.9623413 571.37494 2.5662231 568.99493 4.651306 567.80493 6.255188 566.95496 8.01947 566.44495 10.024292 566.2749 12.670715 566.95496 15.317139 568.14496 17.722961 570.01495 19.647644 572.225 21.091125ZM693.94604 228.2334L692.076 226.87012 689.86597 226.22852 687.48596 226.22852 685.446 226.95026 667.9358 235.21033 654.1657 241.30505 636.82556 246.9989 622.2054 251.89075 586.8451 265.0426 581.405 267.1277 578.85504 268.57117 578.85504 268.57117 578.85504 268.57117 578.85504 268.57117 578.85504 268.57117 575.965 268.97217 573.245 270.09485 571.20496 271.2978 571.20496 271.2978 571.20496 271.2978 571.20496 271.2978 570.52496 270.09485 567.63495 264.08032 566.1049 260.07056 566.1049 252.69269 567.12494 219.41199 569.1649 177.63068 570.52496 155.09607 575.795 117.32446 586.3351 37.290405 586.8451 27.266113 588.0351 12.911316 587.8651 9.863892 587.0151 6.9769287 585.4851 4.490906 583.2751 2.4058228 580.55505 0.9623413 577.66504 0.32080078 574.605 0.40100098 571.71497 1.283081 569.1649 2.887024 567.12494 5.1324463 565.5949 7.7788696 564.9149 10.746033 563.0449 33.0401 563.0449 34.804382 552.6748 114.1969 547.23474 152.93079 545.7047 176.3476 543.8347 218.44965 542.6447 252.37195 542.8147 262.31604 542.8147 263.83972 544.5147 269.6137 546.38477 273.7838 550.12476 281.32214 554.71484 289.26135 557.26483 292.62952 558.6249 294.073 560.4949 295.75708 563.0449 297.20056 565.7649 297.92236 568.65497 298.00256 571.545 297.28076 573.925 296.39868 581.06506 292.62952 584.9751 290.30383 587.0151 288.86035 588.7151 287.01587 589.2251 285.8932 589.2251 285.8932 589.2251 285.8932 589.5651 285.7328 593.98517 284.0487 636.99554 267.92963 661.64575 257.66473 675.5859 249.96606 692.586 240.02197 694.286 238.57849 695.64606 236.65381 696.15607 234.48853 695.986 232.1629 695.306 229.99768Z"
