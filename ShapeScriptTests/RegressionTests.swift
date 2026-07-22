//
//  RegressionTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 27/07/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

@testable import Euclid
@testable import ShapeScript
import XCTest

private let projectDirectory: URL = testsDirectory.deletingLastPathComponent()

private let exampleURLs: [URL] = try! FileManager.default
    .contentsOfDirectory(
        at: projectDirectory.appendingPathComponent("Examples"),
        includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "shape" }

private let testShapesURLs: [URL] = try! FileManager.default
    .contentsOfDirectory(
        at: testsDirectory.appendingPathComponent("TestShapes"),
        includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "shape" }
    .filter {
        #if os(iOS)
        return !$0.deletingPathExtension().lastPathComponent.hasSuffix("-mac")
        #else
        return !$0.deletingPathExtension().lastPathComponent.hasSuffix("-ios")
        #endif
    }

final class RegressionTests: XCTestCase {
    func testFill() throws {
        let program = "fill text \"hello\""
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 14)
        #endif
    }

    func testExtrusion() throws {
        let program = "extrude text \"hello\""
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 130)
        #endif
    }

    func testExtrusionAlongOpenPath() throws {
        let program = """
        extrude {
            text "hello"
            along path {
                point 0
                curve 1
                point 1 0 1
            }
        }
        """
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 614)
        #endif
    }

    func testExtrusionAlongClosedPath() throws {
        let program = "extrude { text \"hello\" \n along circle }"
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 1587)
        #endif
    }

    func testExtrudedTextAlongNonPlanarCurvedPathIsWatertight() throws {
        let program = """
        detail 64

        extrude {
            text {
                orientation -0.5
                "Hello"
                size 0.1
            }
            along path {
                point 0 0
                curve 0 0 1
                curve 0 1 1
                curve 1 1 1
                point 1 1 2
            }
        }
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { true })
        let mesh = geometry.flattened()
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertTrue(mesh.isConsistentlyWound)
        XCTAssertGreaterThan(mesh.signedVolume, 0)
        #endif
    }

    func testLathe() throws {
        let program = "lathe text \"hello\""
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 1712)
        #endif
    }

    func testDifference() throws {
        let program = "difference cube { size 0.8 } sphere"
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 188)
        #endif
    }

    func testUnion() throws {
        let program = "union cube { size 0.8 } sphere"
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 236)
        #endif
    }

    func testStencil() throws {
        let program = "stencil cube cylinder { size 0.5 2 0.5 \n color red }"
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 38)
        #endif
    }

    func testHull() throws {
        let program = "hull sphere cube { position 1 }"
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 69)
        #endif
    }

    func testOffCenterHullIsWatertight() throws {
        let program = """
        detail 16
        smoothing 0

        hull {
            position 0 0.15

            cylinder {
                size 0.3 1 0.3
                orientation 0.5
                position 0 0 0.5
            }
            cylinder {
                size 0.3 1 0.3
                orientation 0.5
                position 0 0 -0.5
            }
            cylinder {
                size 0.2 1.1 0.2
                orientation 0.5
                position 0 0 0.5
            }
            cylinder {
                size 0.2 1.1 0.2
                orientation 0.5
                position 0 0 -0.5
            }
        }
        """
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
    }

    func testMinkowski() throws {
        let program = "minkowski sphere { size 0.1 } cube"
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 182)
        #endif
    }

    func testDifference2() throws {
        let program = """
        detail 190

        define RADIUSBOTTOM    94
        define RADIUSTOP       104.8
        define HEIGHT          64
        define DEPTH           (HEIGHT / 2)
        define THICKNESS       (RADIUSBOTTOM / 10)
        define WALLTHICKNESS   1
        define DIAMETER        (THICKNESS * (pi / 2) - WALLTHICKNESS * 2)

        define LATHE lathe path {
            point 0 HEIGHT
            point (RADIUSTOP / 2 + THICKNESS)  HEIGHT
            point (RADIUSBOTTOM / 2 + THICKNESS)  0
            point 0  0
        }

        define CUBE cube {
            size (RADIUSTOP + THICKNESS * 2 + WALLTHICKNESS) (HEIGHT - DEPTH) (RADIUSTOP + THICKNESS * 2 + WALLTHICKNESS)
            position 0  ((HEIGHT + DIAMETER) - ((HEIGHT - DEPTH) / 2))
        }

        define CONE cone {
            orientation 1
            size (RADIUSTOP + THICKNESS * 2 + WALLTHICKNESS * 2)  (THICKNESS * 2)
            position 0  (HEIGHT / 2 + THICKNESS / 2)
        }

        print LATHE.polygons.count
        print CUBE.polygons.count
        print CONE.polygons.count
                        
        difference LATHE CUBE CONE
        """
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 1330) // TODO: why isn't this 1140?
        XCTAssertEqual(delegate.log, [570.0, 6.0, 950.0])
    }

    func testExamples() throws {
        XCTAssertFalse(exampleURLs.isEmpty)
        XCTAssertFalse(testShapesURLs.isEmpty)
        for url in exampleURLs + testShapesURLs {
            let name = url.lastPathComponent
            let input = try String(contentsOf: url)
            let program = try parse(input)
            let delegate = TestDelegate(directory: url.deletingLastPathComponent())
            let context = EvaluationContext(source: program.source, delegate: delegate)
            XCTAssertNoThrow(try program.evaluate(in: context), "\(name) errored")
            for (i, geometry) in context.children.compactMap({
                $0.value as? Geometry
            }).enumerated() {
                XCTAssert(geometry.isWatertight { false }, """
                \(name) object \(i + 1) was not watertight
                """)
            }
        }
    }
}
