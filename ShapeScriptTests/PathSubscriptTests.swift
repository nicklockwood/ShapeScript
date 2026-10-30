//
//  PathSubscriptTests.swift
//  ShapeScriptTests
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import Euclid
import XCTest

final class PathSubscriptTests: XCTestCase {
    func testStepSelectsExistingPointsAndListsByIndex() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define track path { point 0\npoint 0.2\npoint 1 }
        print (track.points step 2).count
        print (track.points step 2)[1].position.x
        print (track.points step -2)[0].position.x
        print (square.points.allButLast step 1).count
        print (square.points step 1).count
        print (square.points.allButLast step 2)[1] = square.points[2]
        print (square.points.allButLast step -1)[0] = square.points[3]
        print ((1 2 3 4 5) step 2)
        print (((1 2 3 4 5) step 2) step 2)
        print ((1 2 3 4 5) step -2)
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [2, 1, 1, 4, 5, true, true, 1, 3, 5, 1, 5, 5, 3, 1])
    }

    func testSteppedRangeSubscriptAndResampling() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define step 0.25
        print square[step] = square[0.25]
        print (square step 0.25) = square[from 0 step 0.25]
        print square[from 0 step 0.25].points.count
        print (square[from 0 step 0.25].points.allButLast step 4).count
        print square[0.25 to 1.25 step 0.1] = square[0.25 to 1.25][from 0 step 0.1]
        define open path { point 0\npoint 1 }
        print open[from 0 step 0.3].points.count
        print open[from 0 step -0.3].points.first.position.x
        print (path { square[from 0 step 0.7] }).points.count
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [true, true, 17, 4, true, 4, 1, 7])
    }

    func testPathStepMatchesSubscriptResampling() throws {
        var paths = [
            "square", "path {}", "path { point 0 }", "path { point 0\npoint 1 }",
            "union { square }", "group { square }", "square[from 0.25]",
            "path { square\ncircle { position 3 } }",
        ]
        #if canImport(CoreText)
        paths.append("text \"I\"")
        #endif
        for path in paths {
            for step in ["0.3", "2", "-0.3", "-1"] {
                let delegate = TestDelegate()
                _ = try evaluate(parse("""
                define track \(path)
                define sampled track step \(step)
                print sampled = track[from 0 step \(step)]
                print sampled.points = track[from 0 step \(step)].points
                """), delegate: delegate)
                XCTAssertEqual(delegate.log, [true, true], "\(path) step \(step)")
                let scene = try evaluate(parse("""
                define track \(path)
                path { track[0.25 to 1.25] step \(step) }
                path { track[0.25 to 1.25 step \(step)] }
                """), delegate: nil)
                XCTAssertEqual(scene.children.count, 2)
                let first = try XCTUnwrap(scene.children.first?.path())
                let second = try XCTUnwrap(scene.children.last?.path())
                XCTAssertEqual(first.subpaths.count, second.subpaths.count)
                XCTAssertEqual(first.points.count, second.points.count)
                for (a, b) in zip(first.points, second.points) {
                    XCTAssertLessThan((a.position - b.position).length, 1e-8)
                }
            }
        }
    }

    func testPathStepReturnsPathAndResamplesPreviousResult() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define sampled square step 0.7
        print (path { sampled }).points = sampled.points
        print sampled.points.count
        define points for p in sampled { p }
        print points.count
        print (sampled step 0.1) = sampled[from 0 step 0.1]
        print (sampled step 0.1) = (square step 0.1)
        define sample { square step 0.5 }
        define moved sample { position 3 }
        print moved.bounds.center.x
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [true, 7, 6, true, false, 3])
    }

    func testPathErrorIncludesClosingSubscriptBracket() throws {
        for expression in [
            "vertical_wave_path[from 0]",
            "vertical_wave_path[from 0   ]",
            "vertical_wave_path[from 0 step 0.25]",
            "vertical_wave_path[from 0][from 0.5]",
        ] {
            let source = "define vertical_wave_path square\nprint sqrt \(expression)"
            XCTAssertThrowsError(try evaluate(parse(source), delegate: nil), source) { error in
                let error = error as? RuntimeError
                XCTAssertEqual(error?.message, "Type mismatch")
                XCTAssertEqual(error.map { String(source[$0.range]) }, expression)
            }
        }
    }

    func testInvalidSteps() throws {
        for source in [
            "square.points.allButLast step 0.5",
            "(1 2) step 0.5",
            "square.points.allButLast step 0",
            "square[from 0 step 0]",
            "square step 0",
            "cube step 1",
        ] {
            XCTAssertThrowsError(try evaluate(parse("print " + source), delegate: nil), source)
        }
    }

    func testPathDistanceSlicesAndListIndexSlices() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define samples square[from 0.25 step 0.5].points.allButLast step 1
        print samples.count
        print samples[from 5].count
        print samples[from 5][0] = samples[5]
        print square[0.25].position = samples[0].position
        define numeric 10 to 20 step 0.5
        print numeric[2]
        print numeric[from 18]
        define partial square[0.5 to 0.7]
        print partial.points.count
        print partial[0].position = square[0.5].position
        print partial[0.2].position = square[0.7].position
        print (path { partial }).points.count
        print square[0.5 to 0.7 step 0.1].points.count
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [8, 3, true, true, 11, 19, 19.5, 20, 2, true, true, 2, 3])
    }

    func testPathResamplingAndSliceInputs() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define selected square[0.25 to 1.25 step 0.5]
        print selected.points.count
        print selected[from 0 step 0.25].points.count
        print selected.points.count
        print square[3.5 to 4.5].points.count
        print square[0.5 to 8.5].points.count
        define outline union { square }
        print (outline[from 0.25].points.allButLast step 1).count
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [3, 4, 3, 3, 12, 5])
        XCTAssertThrowsError(try evaluate(parse("print cube[from 0.5]"), delegate: nil))
    }

    func testClosedPathSlicesWrapAndKeepSampleCount() throws {
        let path = Path.square()
        for step in [-1.3, -1, 0.7, 1, 2] {
            let count = path.interpolated(step: step).points.count
            for start in [-9.3, 0, 0.25, 4, 12.3] {
                let sampled = path.interpolated(from: start, step: step)
                XCTAssertEqual(sampled.points.count, count)
                XCTAssertTrue(sampled.isClosed)
                for (index, point) in sampled.points.dropLast().enumerated() {
                    let expected = try XCTUnwrap(path.interpolatedPoint(at: start + Double(index) * step))
                    XCTAssertEqual((point.position - expected.position).length, 0, accuracy: 1e-8)
                }
            }
        }
    }

    func testPathSlicesPreserveCornersAndEndpoints() {
        let path = Path([.point(0, 0), .point(1, 0), .point(1, 2)])
        let sampled = path.interpolated(from: 0.5, to: 2.5)
        XCTAssertEqual(sampled.points.map(\.position), [Vector(0.5, 0), Vector(1, 0), Vector(1, 1.5)])
        XCTAssertFalse(sampled.isClosed)
        XCTAssertTrue(Path.square().interpolated(from: 0.5).isClosed)
        XCTAssertFalse(Path.square().interpolated(from: 0.5, to: 0.7).isClosed)
    }

    func testClosedPathSliceDoesNotRecursivelySplitRoundingRemainder() throws {
        var points = (0 ..< 32).map { i -> PathPoint in
            let angle = Double(i) * 2 * .pi / 32
            return .curve(cos(angle), sin(angle))
        }
        points.append(points[0])
        let path = Path(points)
        for index in 0 ..< 100 {
            let offset = path.length * Double(index) / 100
            let sliced = path.interpolated(from: offset)
            XCTAssertEqual(sliced.subpaths.count, 1)
            XCTAssertTrue(sliced.isClosed)
            XCTAssertEqual(sliced.length, path.length, accuracy: 1e-8)
            let first = try XCTUnwrap(sliced.points.first)
            let expected = try XCTUnwrap(path.interpolatedPoint(at: offset))
            XCTAssertEqual((first.position - expected.position).length, 0, accuracy: 1e-8)
        }
    }

    func testPathSliceEdgeCases() {
        let path = Path([.point(0, 0), .point(1, 0), .point(2, 0)])
        XCTAssertEqual(path.interpolated(from: -1, to: 3).points, path.points)
        XCTAssertEqual(path.interpolated(from: 3).points.map(\.position), [Vector(2, 0)])
        XCTAssertEqual(path.interpolated(from: 1, to: 1).points.count, 1)
        XCTAssertEqual(
            path.interpolated(from: 1.75, to: 0.25).points.map(\.position),
            [Vector(1.75, 0), Vector(1, 0), Vector(0.25, 0)]
        )
        XCTAssertEqual(
            path.interpolated(from: 0.5).interpolated(from: 0.5).points.first?.position,
            Vector(1, 0)
        )
        XCTAssertTrue(Path([]).interpolated(from: 1).points.isEmpty)
        let square = Path.square()
        XCTAssertTrue(square.interpolated(from: 0.5, to: 4.5).isClosed)
        XCTAssertEqual(square.interpolated(from: -0.5).points, square.interpolated(from: 3.5).points)
        XCTAssertEqual(square.interpolated(from: 0.5, to: 8.5).length, 8, accuracy: 1e-8)
        XCTAssertEqual(square.interpolated(from: 1).points.count, square.points.count)
    }

    func testPathSlicePreservesAttributesAndInteriorOrientations() throws {
        let path = Path([
            .point(0, 0, texcoord: Vector(0, 0), color: .red),
            .point(1, 0, texcoord: Vector(1, 0), color: .green),
            .point(1, 1, texcoord: Vector(1, 1), color: .blue),
        ])
        let sliced = path.interpolated(from: 0.5, to: 1.5)
        XCTAssertEqual(sliced.points[1], path.points[1])
        XCTAssertEqual(sliced.points[1].orientation, path.points[1].orientation)
        XCTAssertEqual(sliced.points.first?.color, path.interpolatedPoint(at: 0.5)?.color)
        XCTAssertEqual(sliced.points.last?.color, path.interpolatedPoint(at: 1.5)?.color)
        XCTAssertEqual(sliced.points.first?.texcoord, Vector(0.5, 0))
        XCTAssertEqual(sliced.points.last?.texcoord, Vector(1, 0.5))
        XCTAssertTrue(sliced.points.allSatisfy { $0.orientation != nil })
        // Slicing at a corner preserves its original orientation.
        let cornerStart = path.interpolated(from: 1)
        XCTAssertEqual(cornerStart.points[0].orientation, path.points[1].orientation)
        let forward = try XCTUnwrap(cornerStart.points[0].orientation?.forward)
        XCTAssertEqual(forward, path.points[1].orientation?.forward)
        let curved = Path([.curve(0, 0), .curve(1, 0), .curve(1, 1)])
        XCTAssertEqual(curved.interpolated(from: 0.5, to: 1.5).points[1].isCurved, curved.points[1].isCurved)
    }

    func testPathSlicesPreserveSubpathsAndBlockTransforms() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define sample { square[0.25 to 1.25 step 0.5].points step 1 }
        define moved sample { position 3 }
        print moved.count
        for p in moved { print p.position.x > 2 }
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [3, true, true, true])
        let path = Path(subpaths: [.square(), Path([.point(3, 0), .point(5, 0)])])
        let sampled = path.interpolated(from: 0.25, step: 0.5)
        XCTAssertEqual(sampled.subpaths.count, 2)
        XCTAssertTrue(sampled.subpaths[0].isClosed)
        XCTAssertFalse(sampled.subpaths[1].isClosed)
        XCTAssertEqual(sampled.subpaths[1].points.first?.position.x, 3.25)
    }

    func testRangeMembers() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define r 1 to 5
        define s r step 2
        print r.start
        print r.end
        print s.start
        print s.end
        print s.step
        print s.count
        print r[1]
        print s[1]
        print s[-1]
        print 2.5 in r
        print 2.5 in s
        print 3 in s
        print s[0 to 2 step 2]
        print "start" in r
        print "start" in s
        print "step" in r
        print "step" in s
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [1, 5, 1, 5, 2, 3, 2, 3, 5, true, false, true, 1, 5, true, true, false, true])
    }

    func testFiniteRangeCount() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define r 1 to 5
        print r.count
        print (r).count
        print (1 to 5).count
        print (1 to 5 step 2).count
        print (0.2 to 2.7).count
        print (5 to 1).count
        print (3 to 3).count
        print "count" in (1 to 5)
        print "count" in (from 5)
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [5, 5, 5, 3, 3, 0, 1, true, false])
        XCTAssertEqual(ValueType.range.memberType("count"), .number)
        XCTAssertNil(Value.range(.init(from: 5, to: nil))["count"])
    }

    func testRangeStepMember() throws {
        XCTAssertNil(Value.range(.init(from: 1, to: 5))["step"])
        XCTAssertEqual(ValueType.range.memberType("step"), .number)
        XCTAssertEqual(try Value.range(XCTUnwrap(.init(from: 1, to: 5, step: 2)))["step"], 2)
    }

    func testRepeatedStepsSelectListElementsAndReplaceRangeIncrement() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define s square[from 0 step (1 / 3)].points.allButLast step 1
        define t s step 4
        print s.count
        print t.count
        print t[1] = s[4]
        define n 1 to 5 step 3
        for i in n step 2 { print i }
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [12, 3, true, 1, 3, 5])
    }

    func testSteppedSquareMatchesDirectVertexOrientations() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define direct for p in square { p.orientation }
        define stepped for p in square.points.allButLast step 1 { p.orientation }
        print direct = stepped
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [true])
    }

    func testGeometryBuildersUseSampledPath() throws {
        for builder in ["path", "hull", "fill", "extrude", "lathe", "loft"] {
            let setup = """
            define samples square step 0.7
            """
            let expected = try evaluate(parse(setup + "\n" + """
            \(builder) {
                path {
                    for p in samples.points { p }
                }
            }
            """), delegate: nil)
            let sampled = try evaluate(parse(setup + "\n" + """
            \(builder) { samples }
            """), delegate: nil)
            XCTAssertEqual(sampled.children.count, expected.children.count, builder)
            for (actual, expected) in zip(sampled.children, expected.children) {
                if actual.isPath {
                    XCTAssertEqual(actual.path()?.points, expected.path()?.points, builder)
                } else {
                    XCTAssertEqual(actual.mesh(), expected.mesh(), builder)
                }
            }
        }
    }

    func testBooleanPathSubscriptSamplesEvaluatedBoundary() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define original difference {
            square { size 2 }
            circle
        }
        define samples original step 0.3
        define result path { samples }
        print result.points = original.points
        print result.points.count = samples.points.count
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [false, true])
    }

    func testPointListReturnedByTransformedBlock() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define samples { square.points.allButLast step 1 }
        define s samples { position 3 }
        print s.count
        for p in s { print p.position.x > 2 }
        """), delegate: delegate)
        XCTAssertEqual(delegate.log, [4, true, true, true, true])
    }

    func testSolidGeometryCannotBeLoopBounds() throws {
        for geometry in [
            "cube",
            "group { cube }",
            "group { square\ncube }",
            "union { cube }",
            "difference { cube\ncube }",
        ] {
            for source in [
                "for item in (\(geometry)) { print item }",
                "define model \(geometry)\nfor item in model { print item }",
                "define model \(geometry)\nfor item in ((model)) { print item }",
                "define model { \(geometry) }\nfor item in model { print item }",
            ] {
                let delegate = TestDelegate()
                XCTAssertThrowsError(try evaluate(parse(source), delegate: delegate), source) { error in
                    XCTAssertEqual((error as? RuntimeError)?.message, "Type mismatch", source)
                    XCTAssertEqual(
                        (error as? RuntimeError)?.hint,
                        "The loop bounds should be a list, object, path, or range, not a mesh.",
                        source
                    )
                }
                XCTAssertTrue(delegate.log.isEmpty, source)
            }
        }
    }

    func testPathGeometryRemainsIterable() throws {
        for geometry in ["square", "group { square }", "union { square }"] {
            for source in [
                "for p in (\(geometry)) { print p.position }",
                "define model \(geometry)\nfor p in model { print p.position }",
            ] {
                let delegate = TestDelegate()
                _ = try evaluate(parse(source), delegate: delegate)
                XCTAssertEqual(delegate.log.count, 4, source)
                XCTAssertTrue(delegate.log.allSatisfy { $0 is Vector }, source)
            }
        }
    }

    func testEmptyPathGeometryProducesNoIterations() throws {
        for geometry in [
            "path {}",
            "group {}",
            "union {}",
            "difference {}",
            "intersection {}",
            "xor {}",
            "hull {}",
            "minkowski {}",
            "difference { square\nsquare }",
        ] {
            for source in [
                "for p in (\(geometry)) { print p }",
                "define model \(geometry)\nfor p in model { print p }",
            ] {
                let delegate = TestDelegate()
                _ = try evaluate(parse(source), delegate: delegate)
                XCTAssertTrue(delegate.log.isEmpty, source)
            }
        }
    }

    func testCollectionsCanContainSolidGeometry() throws {
        let delegate = TestDelegate()
        _ = try evaluate(parse("""
        define models cube sphere
        for model in models { print model.bounds.width }
        for model in models[0 to 0] { print model.bounds.width }
        define inspect { for model in children { print model.bounds.width } }
        inspect { cube }
        """), delegate: delegate)
        XCTAssertEqual(delegate.log.count, 4)
        XCTAssertTrue(delegate.log.allSatisfy { $0 is Double })
    }

    func testOtherLoopInputs() throws {
        XCTAssertNil(Value.number(1).sequenceValue)
        XCTAssertEqual(try Array(XCTUnwrap(Value.tuple([1]).sequenceValue)), [1])
        XCTAssertEqual(try Array(XCTUnwrap(Value.tuple([]).sequenceValue)), [])
        let object: Value = ["b": 2, "a": 1]
        XCTAssertEqual(try Array(XCTUnwrap(object.sequenceValue)), [.tuple(["a", 1]), .tuple(["b", 2])])
    }
}
