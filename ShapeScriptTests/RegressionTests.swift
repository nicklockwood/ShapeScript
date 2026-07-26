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

    func testExtrudedOutsetComicSans3HasValidCaps() throws {
        #if os(macOS)
        let program = """
        detail 64
        font "comic sans ms"
        extrude inset (text "3") -0.01
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { true })
        let mesh = try XCTUnwrap(geometry.mesh)
        let font = CTFontCreateWithName("comic sans ms" as CFString, 1, nil)
        let shape = try XCTUnwrap(Path.text("3", font: font, detail: 8).first)
        let expected = Mesh.extrude(shape.inset(by: -0.01))

        XCTAssertEqual(mesh.polygons.count, expected.polygons.count)
        XCTAssertFalse(mesh.polygons.containsIntersections)
        XCTAssertTrue(mesh.hasConsistentCapDirections)
        let internalCapPolygons = mesh.polygons.filter { polygon in
            abs(polygon.plane.normal.z) > 0.5 && polygon.vertices.contains {
                let z = $0.position.z
                return abs(z - mesh.bounds.min.z) > epsilon && abs(z - mesh.bounds.max.z) > epsilon
            }
        }
        XCTAssertTrue(internalCapPolygons.isEmpty)
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertTrue(mesh.isConsistentlyWound)
        XCTAssertGreaterThan(mesh.signedVolume, 0)
        #endif
    }

    func testExtrudedOutsetComicSansDPreservesHole() throws {
        #if os(macOS)
        let program = """
        detail 64
        font "comic sans ms"
        extrude inset (text "d") -0.03
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { true })
        let mesh = try XCTUnwrap(geometry.mesh)
        let font = CTFontCreateWithName("comic sans ms" as CFString, 1, nil)
        let shape = try XCTUnwrap(Path.text("d", font: font, detail: 8).first)
        let filledArea = Mesh.fill(shape.inset(by: -0.03)).surfaceArea / 2

        XCTAssertEqual(mesh.endCapArea(at: mesh.bounds.min.z), filledArea, accuracy: epsilon)
        XCTAssertEqual(mesh.endCapArea(at: mesh.bounds.max.z), filledArea, accuracy: epsilon)
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertTrue(mesh.isConsistentlyWound)
        XCTAssertGreaterThan(mesh.signedVolume, 0)
        #endif
    }

    func testExtrusion() throws {
        let program = "extrude text \"hello\""
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 129)
        #endif
    }

    func testInsetExtrudedNumber8() throws {
        let program = "inset (extrude text \"8\") 0.03"
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { true })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertGreaterThan(mesh.signedVolume, 0)
        #endif
    }

    func testInsetExtrudedNumber8PastStrokeWidthIsEmpty() throws {
        let program = "inset (extrude text \"8\") 0.06"
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { true })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertTrue(mesh.isEmpty)
        #endif
    }

    func testInsetExtrudedTextDoesNotDisappear() throws {
        let program = "inset (extrude text \"Hello\") 0.01"
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { true })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertGreaterThan(mesh.signedVolume, 0)
        XCTAssertTrue(mesh.polygons.areWatertight, "hole edges: \(mesh.polygons.holeEdges.count)")
        #endif
    }

    func testInsetFilledTextDoesNotDisappear() throws {
        let program = "inset (fill text \"txt\") 0.01"
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { true })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertGreaterThan(mesh.polygons.surfaceArea, 0)
        #endif
    }

    func testInsetFilledTextPreservesCharacterOffsets() throws {
        let program = "inset (fill text \"Hello\") 0.04"
        let originalScene = try evaluate(parse("fill text \"Hello\""), delegate: TestDelegate())
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(originalScene.children.count, 1)
        XCTAssertEqual(scene.children.count, 1)
        let originalGeometry = try XCTUnwrap(originalScene.children.first)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(originalGeometry.build { true })
        XCTAssertTrue(geometry.build { true })
        let original = try XCTUnwrap(originalGeometry.mesh)
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertGreaterThan(mesh.bounds.size.x, original.bounds.size.x * 0.5)
        #endif
    }

    func testInsetFilledTextDoesNotBakeMaterial() throws {
        let program = "inset (fill text \"Hello\") 0.03"
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { true })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertEqual(mesh.materials, [nil])
        XCTAssertFalse(mesh.hasVertexColors)
        #endif
    }

    func testInsetFilledTextPreservesSourceMaterial() throws {
        let program = """
        inset (fill {
            color red
            text "Hello"
        }) 0.03
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { true })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertEqual(mesh.materials, [Material(color: .red)])
        XCTAssertFalse(mesh.hasVertexColors)
        #endif
    }

    func testInsetExtrudedTextAlongPathPreservesEndCapMaterial() throws {
        let program = """
        inset (extrude {
            color red
            text "e"
            along path {
                point 0
                point 1
                point 1 0 1
            }
        }) 0.01
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { true })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertFalse(mesh.isEmpty)
        let endCapPolygons = mesh.polygons.filter {
            $0.vertices.allSatisfy { $0.position.x.isApproximatelyEqual(to: mesh.bounds.min.x) } ||
                $0.vertices.allSatisfy { $0.position.z.isApproximatelyEqual(to: mesh.bounds.max.z) }
        }
        XCTAssertFalse(endCapPolygons.isEmpty)
        XCTAssertTrue(endCapPolygons.allSatisfy {
            $0.material as? Material == Material(color: .red)
        })
        XCTAssertFalse(mesh.hasVertexColors)
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
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 661)
        #endif
    }

    func testExtrusionAlongClosedPath() throws {
        let program = "extrude { text \"hello\" \n along circle }"
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 1712)
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
            for (i, geometry) in context.state.children.compactMap({
                $0.value as? Geometry
            }).enumerated() {
                XCTAssert(geometry.isWatertight { false }, """
                \(name) object \(i + 1) was not watertight
                """)
            }
        }
    }
}

private extension Mesh {
    var hasConsistentCapDirections: Bool {
        let capPolygons = polygons.filter {
            $0.endCapZ(in: bounds) != nil
        }
        let capsByZ = Dictionary(grouping: capPolygons) {
            $0.endCapZ(in: bounds) == bounds.min.z
        }
        return capsByZ.values.allSatisfy { polygons in
            guard let normal = polygons.first?.plane.normal.z.sign else {
                return true
            }
            return polygons.allSatisfy {
                $0.plane.normal.z.sign == normal
            }
        }
    }

    func endCapArea(at z: Double) -> Double {
        polygons.filter {
            $0.vertices.allSatisfy { abs($0.position.z - z) < epsilon }
        }.reduce(0) {
            $0 + $1.area
        }
    }
}

private extension Collection<Euclid.Polygon> {
    var containsIntersections: Bool {
        let polygons = Array(self)
        for i in polygons.indices {
            for j in polygons.indices.dropFirst(i + 1) {
                if polygons[i].hasInteriorIntersection(with: polygons[j]) {
                    return true
                }
            }
        }
        return false
    }
}

private extension Euclid.Polygon {
    func hasInteriorIntersection(with other: Euclid.Polygon) -> Bool {
        let sharedVertices = Set(vertices.map(\.position)).intersection(other.vertices.map(\.position))
        if sharedVertices.count >= 2 {
            return false
        }
        return vertices.contains {
            !sharedVertices.contains($0.position) && other.intersects($0.position)
        } || other.vertices.contains {
            !sharedVertices.contains($0.position) && intersects($0.position)
        }
    }

    func endCapZ(in bounds: Bounds) -> Double? {
        if vertices.allSatisfy({ abs($0.position.z - bounds.min.z) < epsilon }) {
            return bounds.min.z
        }
        if vertices.allSatisfy({ abs($0.position.z - bounds.max.z) < epsilon }) {
            return bounds.max.z
        }
        return nil
    }
}
