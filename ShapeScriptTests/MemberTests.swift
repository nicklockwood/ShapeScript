//
//  MemberTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 30/10/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

@testable import Euclid
@testable import ShapeScript
import XCTest

final class MemberTests: XCTestCase {
    // MARK: member access

    func testTupleVectorLookup() {
        let program = "print (1 0).x"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0])
    }

    func testOutOfBoundsTupleVectorLookup() {
        let program = "print (1 0).z"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.0])
    }

    func testTooLongTupleVectorLookup() {
        let program = "print (1 2 3 4).x"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownMember("x", of: "tuple", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testSingleElementTupleVectorLookup() {
        let program = "print (1).x"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0])
    }

    func testNestedSingleElementTupleVectorLookup() {
        let program = "print (1 (2)).x"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0])
    }

    func testNestedSingleElementTupleVectorLookup2() {
        let program = "print ((1) 2).x"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0])
    }

    func testStringTupleVectorLookup() {
        let program = "print (\"1\" \"2\").x"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0])
    }

    func testMixedTupleVectorLookup() {
        let program = "print (\"1\" 2).x"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0])
    }

    func testTupleSizeHeightLookup() {
        let program = "print (1 0.5).height"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.5])
    }

    func testTupleSizeDepthLookup() {
        let program = "print (1 0.5).depth"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0])
    }

    func testTupleRotationRollLookup() {
        let program = "print (1 0.5).roll"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssert(delegate.log == [1.0] || delegate.log == [-1])
    }

    func testTupleRotationPitchLookup() {
        let program = "print (1 0.5).pitch"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.0])
    }

    func testTupleRGBARedLookup() {
        let program = "print (0.1 0.2 0.3 0.4).red"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.1])
    }

    func testTupleRGBAlphaLookup() {
        let program = "print (0.1 0.2 0.3).alpha"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0])
    }

    func testTupleIAGreenLookup() {
        let program = "print (0.1 0.2).green"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.1])
    }

    func testTupleIAAlphaLookup() {
        let program = "print (0.1 0.2).alpha"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.2])
    }

    func testHexAlphaLookup() {
        let program = "print #f00.alpha"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1])
    }

    func testHexTupleAlphaLookup() {
        let program = "print (#f00 0.2).alpha"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.2])
    }

    func testHexStringAlphaLookup() {
        let program = "print \"#f00\".alpha"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1])
    }

    func testHexStringTupleAlphaLookup() {
        let program = "print (\"#f00\" 0.2).alpha"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.2])
    }

    func testTooLongTupleColorLookup() {
        let program = "print (1 2 3 4 5).red"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown tuple member property 'red'")
            XCTAssertNotEqual(error?.suggestion, "red")
            guard case .unknownMember("red", of: "tuple", _) = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testEmptyTupleColorLookup() {
        let program = "print ().blue"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown empty tuple member property 'blue'")
            XCTAssertNotEqual(error?.suggestion, "blue")
            guard case .unknownMember("blue", of: "empty tuple", _) = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testTupleWordsLookup() {
        let program = "print (\"foo\" 1 2).words"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["foo1", "2"])
    }

    func testTupleCharactersLookup() {
        let program = "print (\"foo\" 1).characters"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, ["f", "o", "o", "1"])
    }

    func testNonNumericColorLookup() {
        let program = "print (\"foo\" \"bar\").red"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown tuple member property 'red'")
            guard case .unknownMember("red", of: "tuple", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testTupleNonexistentLookup() {
        let program = "print (1 2).foo"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown tuple member property 'foo'")
            guard case .unknownMember("foo", of: "tuple", _) = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testColorWidthLookup() {
        let program = "color 1 0.5\nprint color.width"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown color member property 'width'")
            guard case .unknownMember("width", of: "color", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testRotationXLookup() {
        let program = """
        cube {
            print orientation.x
        }
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown rotation member property 'x'")
            guard case .unknownMember("x", of: "rotation", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testRotationYawLookup() {
        let program = """
        cube {
            orientation 0.3 0.2 0.1
            print orientation.yaw
        }
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log.first as? Double ?? 0, 0.2, accuracy: epsilon)
    }

    func testTupleOrdinalLookup() {
        let program = "define col 1 0.5\nprint col.second"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log.first as? Double ?? 0, 0.5, accuracy: epsilon)
    }

    func testTupleOrdinalOutOfBoundsLookup() {
        let program = "define col 1 0.5\nprint col.third"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown tuple member property 'third'")
            guard case .unknownMember("third", of: "tuple", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testTupleVeryHighOrdinalLookups() {
        let numbers = (1 ... 99).map { $0.description }.joined(separator: " ")
        let program = """
        define foo \(numbers)
        print foo.tenth
        print foo.nineteenth
        print foo.twentythird
        print foo.thirtyninth
        print foo.fortyseventh
        print foo.fiftythird
        print foo.sixtyeighth
        print foo.seventyfirst
        print foo.eightysixth
        print foo.ninetysecond
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [10, 19, 23, 39, 47, 53, 68, 71, 86, 92])
    }

    func testTupleCountLastRestLookup() {
        let program = """
        define foo 2 4 6
        print foo.count
        print foo.last
        print foo.allButFirst
        print foo.allButLast
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [3, 6, 4, 6, 2, 4])
    }

    func testSingleValueOrdinalLookup() {
        let program = """
        define foo 10
        print foo.first
        print foo.count
        print foo.last
        print foo.allButFirst
        print foo.allButLast
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [10, 1, 10])
    }

    func testEmptyTupleOrdinalLookup() {
        let program = """
        define foo ()
        print foo.count
        print foo.allButFirst
        print foo.allButLast
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0])
    }

    func testSingleNumberXComponentLookup() {
        let program = """
        define foo 10
        print foo.x
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [10])
    }

    func testSingleVectorYComponentLookup() {
        let program = """
        define foo 1 2 3
        define bar foo
        print bar.y
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [2])
    }

    func testSingleVectorColorComponentLookup() {
        let program = """
        define foo color
        define bar foo
        print bar.red
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1])
    }

    func testMeshBoundsLookup() {
        let program = """
        print (fill square).bounds
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Bounds(
            min: .init(-0.5, -0.5, 0),
            max: .init(0.5, 0.5, 0)
        )])
    }

    func testMeshPolygonsLookup() throws {
        let program = """
        print (fill square).polygons
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, Mesh.fill(.square()).polygons)
    }

    func testPathPolygonsLookup() throws {
        let program = """
        print square.polygons
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown path member property 'polygons'")
            guard case .unknownMember("polygons", of: "path", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testCameraPolygonsLookup() throws {
        let program = """
        print camera.polygons
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown camera member property 'polygons'")
            guard case .unknownMember("polygons", of: "camera", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testInvalidMeshComponentLookup() {
        let program = """
        print (fill { circle }).x
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.message, "Unknown mesh member property 'x'")
            guard case .unknownMember("x", of: "mesh", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testPolygonPointsLookup() throws {
        let program = """
        print cube.polygons.first.points
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        let points = try XCTUnwrap(delegate.log as? [PathPoint])
        XCTAssertEqual(points.count, 4)
    }

    func testPolygonCenterLookup() throws {
        let program = """
        print cube.polygons.first.center
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        let center = try XCTUnwrap(delegate.log as? [Vector]).first
        XCTAssertEqual(center, Vector(0.5, 0, 0))
    }

    func testPointColorLookup() throws {
        let program = """
        define foo path {
            color red
            point 0 0
            color green
            point 1 0
            point 1 1
        }
        print foo.points.first.color
        print foo.points.second.color
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [Color.red, Color.green])
    }

    func testMemberPrecedence() {
        let program = """
        define a 0.5 0.3
        define b 0.2 0.4
        print a.x * b.x + a.y * b.y
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.22])
    }

    func testMemberChaining() {
        let program = """
        define a (1 2 3) (4 5 6)
        print a.second.y
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5])
    }

    func testNestedMemberLookup() {
        let program = """
        define a ((1 2 3) (4))
        print a.second.first
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [4])
    }

    func testBlockResultTupleValueLookup() {
        let program = """
        define a {
            option b 0
            b + 1
            b + 2
        }
        define c a { b 4 }
        print c.second
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [6])
    }

    func testFunctionResultTupleValueLookup2() {
        let program = """
        define a(b) {
            b + 1
            b + 2
        }
        define c a(4)
        print c.second
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [6])
    }

    func testFunctionResultNestedTupleValueLookup() {
        let program = """
        define a(b) {
            (b + 1 b + 2)
            (b + 3 b + 4)
        }
        define c a(4)
        print c.second.first
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [7])
    }

    func testFunctionResultNestedTuplesCollapsedIfNeeded() {
        let program = """
        define triangle {
            polygon {
                point 1 0
                point 1 1
                point 0 1
            }
        }
        define triangles {
            for 1 to 3 {
                triangle
            }
        }
        define triangles2 {
            for 1 to 3 {
                triangles
            }
        }
        mesh { triangles2 }
        """
        XCTAssertNoThrow(try evaluate(parse(program), delegate: nil))
    }

    // MARK: subscripting

    func testTupleVectorSubscripting() {
        let program = "print (1 0)[\"x\"]"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0])
    }

    func testTupleVectorIndexing() {
        let program = "print (1 0)[0]"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [1.0])
    }

    func testNestedTupleVectorIndexing() {
        let program = """
        define values 1 0
        print (values)[1]
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.0])
    }

    func testOutOfBoundsTupleVectorSubscripting() {
        let program = "print (1 0)[\"z\"]"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [0.0])
    }

    func testNonExistentTupleVectorSubscripting() {
        let program = "print (1 0)[\"w\"]"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            guard case .unknownMember("w", of: "tuple", _)? = error?.type else {
                XCTFail()
                return
            }
        }
    }

    func testOutOfBoundsTupleVectorIndexing() {
        let program = "print (1 0)[2]"
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .invalidIndex(2, range: 0 ..< 2))
        }
    }

    func testFunctionResultNestedTupleValueIndexing() {
        let program = """
        define a(b) {
            (b + 1 b + 2)
            (b + 3 b + 4)
        }
        define c a(4)
        print c[1][0]
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [7])
    }

    func testFunctionMixedTupleValueLookupAndIndexing() {
        let program = """
        define a(b) {
            (b + 1 b + 2)
            (b + 3 b + 4)
        }
        define c a(4)
        print c.second[0]
        print c[1].first
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [7, 7])
    }

    func testRangeSubscripting() {
        let program = "print (1 to 4)[1]"
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [2.0])
    }

    func testObjectSubscripting() {
        let program = """
        define foo object {
            a 5
            b "hello"
        }
        print foo.a
        print foo.b
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        XCTAssertEqual(delegate.log, [5.0, "hello"])
    }

    func testObjectFirstIndex() {
        let program = """
        define foo object {
            a 5
            b "hello"
        }
        // You can always access first element due to automatic tuple promotion
        print foo.first
        print foo[0]
        """
        let delegate = TestDelegate()
        XCTAssertNoThrow(try evaluate(parse(program), delegate: delegate))
        let object: [String: AnyHashable] = ["a": 5.0, "b": "hello"]
        XCTAssertEqual(delegate.log, [object, object])
    }

    func testObjectOrdinalSubscripting() {
        let program = """
        define foo object {
            a 5
            b "hello"
        }
        print foo.second
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .unknownMember("second", of: "object", options: ["a", "b"]))
        }
    }

    func testInvalidObjectSubscripting() {
        let program = """
        define foo object {
            a 5
            b "hello"
        }
        print foo.c
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .unknownMember("c", of: "object", options: ["a", "b"]))
        }
    }

    func testObjectIndexedSubscripting() {
        let program = """
        define foo object {
            a 5
            b "hello"
        }
        print foo[1]
        """
        XCTAssertThrowsError(try evaluate(parse(program), delegate: nil)) { error in
            let error = try? XCTUnwrap(error as? RuntimeError)
            XCTAssertEqual(error?.type, .invalidIndex(1, range: 0 ..< 1))
        }
    }
}
