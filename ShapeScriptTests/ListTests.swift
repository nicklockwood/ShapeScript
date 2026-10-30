//
//  ListTests.swift
//  ShapeScriptTests
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import Euclid
import XCTest

final class ListTests: XCTestCase {
    func testConversionErrorDescribesSingletonElementWithoutUnwrappingList() throws {
        let list: Value = [1]
        XCTAssertEqual(list.type, .list(.number))
        XCTAssertEqual(list.typeForError, .number)
        XCTAssertEqual(Value.pretransformed(.tuple([list])).typeForError, .number)
        XCTAssertEqual(list.unwrapped(recursive: true), list)
        XCTAssertEqual(try Array(XCTUnwrap(list.sequenceValue)), [1])

        let multiple: Value = [1, 2]
        let empty: Value = []
        XCTAssertEqual(multiple.typeForError, multiple.type)
        XCTAssertEqual(empty.typeForError, empty.type)
    }

    func testArrayLiteralsCreateLists() {
        let empty: Value = []
        let single: Value = [1]
        let nested: Value = [[1]]
        XCTAssertEqual(empty, .list([]))
        XCTAssertEqual(single, .list([1]))
        XCTAssertEqual(nested, .list([.list([1])]))
        XCTAssertNotEqual(empty, .void)
    }

    func testSingletonListDoesNotUnwrapOrEnumerateItsPath() throws {
        let path = Value.path(.square())
        let list = Value.list([path])
        XCTAssertEqual(list.unwrapped(recursive: true), list)
        XCTAssertEqual(list.type, .list(.path))
        XCTAssertEqual(list["count"], 1)
        XCTAssertEqual(list[0], path)
        XCTAssertEqual(try Array(XCTUnwrap(list.sequenceValue)), [path])
        XCTAssertEqual(try Array(XCTUnwrap(Value.tuple([list]).sequenceValue)), [path])
        XCTAssertEqual(list.as(.path), path)
        XCTAssertEqual(list["points"], path["points"])
    }

    func testSlicesAlwaysReturnLists() throws {
        let delegate = TestDelegate()
        let scene = try evaluate(parse("""
        define paths square circle
        define single paths[0 to 0]
        print single.count
        print (single).count
        for p in single { print p.points.count }
        define empty paths[1 to 0]
        print empty.count
        for p in empty { print "unexpected" }
        fill single
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [1, 1, 5, 0])
        XCTAssertTrue(scene.geometry.build())
        XCTAssertFalse(scene.geometry.meshes().isEmpty)
    }

    func testChildCollectionDoesNotDependOnCardinality() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define inspect {
            print children.count
            for child in children { print child.points.count }
        }
        inspect {}
        inspect { square }
        inspect {
            square
            square
        }
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [0, 1, 5, 2, 5, 5])
    }

    func testLoopResultsAreLists() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define paths for i in 1 to 1 { square }
        print paths.count
        for p in paths { print p.points.count }
        define nested for i in 1 to 1 { paths }
        print nested.count
        print nested[0].count
        for collection in nested { print collection[0].points.count }
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [1, 5, 1, 1, 5])
    }

    func testListSlicesPreserveNestedCollections() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define values (1 2) (3 4)
        define single values[1 to 1]
        print single.count
        print single[0].count
        print single[0][0]
        print single[-1][-1]
        print single.allButFirst.count
        print single.allButLast.count
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [1, 2, 3, 4, 0, 0])
    }

    func testJSONArraysAreLists() {
        let value = Value(json: [[1, 2]])
        XCTAssertEqual(value, .list([.list([1, 2])]))
        XCTAssertEqual(value["count"], 1)
        XCTAssertEqual(value[0]?["count"], 2)
    }

    func testContextualCastsRetainTupleCompatibility() {
        let examples: [[Value]] = [[], [1], [1, 2], [1, 2, 3], [.string("red")], [.path(.square())]]
        let types: [ValueType] = [
            .number,
            .boolean,
            .string,
            .text,
            .vector,
            .size,
            .rotation,
            .color,
            .point,
            .path,
            .mesh,
            .tuple([.number, .number]),
            .tuple([.number]),
        ]
        for values in examples {
            for type in types {
                XCTAssertEqual(
                    Value.list(values).as(type),
                    Value.tuple(values).as(type),
                    "Conversion of \(values) to \(type)"
                )
            }
        }
    }

    func testListArgumentsAndArithmetic() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define values (1 2 3)[0 to 2]
        print values + 1
        print values - 1
        print values * 2
        print values / 2
        print -values
        print dot values (1 1 1)
        print join ("a b".words) ","
        print join ("a".words) ","
        print sum values
        print sin ((0 1)[0 to 0])
        path { values }
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [
            2,
            3,
            4,
            0,
            1,
            2,
            2,
            4,
            6,
            0.5,
            1,
            1.5,
            -1,
            -2,
            -3,
            6,
            "a,b",
            "a",
            6,
            0,
        ])
    }

    func testUnnamedBlockCombinesMeshListWithMesh() throws {
        let scene = try evaluate(parse("""
        define cutout {
            extrude {
                circle { size 2 }
                along circle { size 10 }
            }
            cylinder
        }
        cutout {}
        """), delegate: nil)
        let group = try XCTUnwrap(scene.geometry.children.first)
        XCTAssertEqual(group.children.count, 2)
        XCTAssertTrue(group.children.allSatisfy { !$0.isPath })
        XCTAssertTrue(group.build())
        XCTAssertFalse(group.meshes().isEmpty)
    }

    func testUnnamedBlockCombinesLoopMeshListWithMesh() throws {
        let scene = try evaluate(parse("""
        define shapes {
            for i in 1 to 1 { cube }
            sphere { position 2 }
        }
        shapes { position 3 }
        """), delegate: nil)
        let group = try XCTUnwrap(scene.geometry.children.first)
        XCTAssertEqual(group.children.count, 2)
        XCTAssertEqual(group.transform.translation.x, 3)
        XCTAssertEqual(group.children[0].transform.translation.x, 0)
        XCTAssertEqual(group.children[1].transform.translation.x, 2)
    }

    func testUnnamedBlockGroupsMultipleMeshListsForCSG() throws {
        for body in [
            "extrude { square { position -1 } }\nextrude { square { position 1 } }",
            "for i in 1 to 1 { cube { position -1 } }\nfor i in 1 to 1 { cube { position 1 } }",
        ] {
            let scene = try evaluate(parse("""
            define pair { \(body) }
            intersection {
                pair {}
                cube { size 4 }
            }
            """), delegate: nil)
            let intersection = try XCTUnwrap(scene.geometry.children.first)
            XCTAssertEqual(intersection.children.count, 2, body)
            let group = try XCTUnwrap(intersection.children.first)
            XCTAssertEqual(group.type, .group, body)
            XCTAssertEqual(group.children.count, 2, body)
            let mesh = try XCTUnwrap(intersection.mesh())
            XCTAssertEqual(mesh.signedVolume, 2, accuracy: 1e-8, body)
        }
    }

    func testUnnamedBlockGroupsSingleLoopForCSG() throws {
        let scene = try evaluate(parse("""
        define pair {
            for x in (-1 1) { cube { position x } }
        }
        intersection {
            pair { position 3 }
            cube {
                size 4
                position 3
            }
        }
        """), delegate: nil)
        let intersection = try XCTUnwrap(scene.geometry.children.first)
        let mesh = try XCTUnwrap(intersection.mesh())
        XCTAssertEqual(mesh.signedVolume, 2, accuracy: 1e-8)
        XCTAssertEqual(mesh.bounds.center.x, 3, accuracy: 1e-8)
        XCTAssertEqual(intersection.children.count, 2)
        let group = try XCTUnwrap(intersection.children.first)
        XCTAssertEqual(group.type, .group)
        XCTAssertEqual(group.children.count, 2)
    }

    func testNamedBlockReturningList() throws {
        let scene = try evaluate(parse("""
        define shapes { for i in 1 to 2 { cube } }
        shapes { name "pair" }
        """), delegate: nil)
        XCTAssertEqual(scene.geometry.children.first?.name, "pair")
    }

    func testEmptyLoopResultCanBeIgnoredOrEnumerated() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define values for i in 1 to 0 { square }
        print values.count
        for value in values { print "unexpected" }
        define sample(p) { for point in p step 0.5 { print point.position } }
        sample path { point 0 }
        """), delegate: delegate)
        XCTAssertEqual(delegate.log.first, 0)
    }

    func testUserFunctionPreservesListArgument() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define inspect(value) {
            print value.count
            for item in value { print item.points.count }
        }
        inspect ((square circle)[0 to 0])
        inspect ((square circle)[0 to 1])
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [1, 5, 2, 5, 17])
    }

    func testListAndTupleCastsPreserveNestedArguments() {
        let examples: [[Value]] = [[], [1], [1, 2, 3], [.tuple([1, 2]), .tuple([3, 4])]]
        let types: [ValueType] = [.list(.any), .list(.number), .list(.list(.number))]
        for values in examples {
            for type in types {
                XCTAssertEqual(Value.list(values).as(type), Value.tuple(values).as(type))
            }
        }
        XCTAssertEqual(Value.tuple([1, 2]).as(.list(.number)), .list([1, 2]))
        XCTAssertEqual(Value.list([1, 2]).as(.tuple([.number, .number])), .tuple([1, 2]))
    }

    func testListTupleEqualityAndMembership() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define values (1 2 3)[0 to 1]
        print values = (1 2)
        print (1 2) in (values (3 4))
        print values in ((1 2) (3 4))
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [true, true, true])
    }
}
