//
//  GeometryTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 28/08/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid
@testable import ShapeScript
import XCTest

final class GeometryTests: XCTestCase {
    // MARK: Bounds

    func testGroupOfShapeCameraBoundsNotEmpty() {
        let cube = Geometry(
            type: .cube,
            name: nil,
            transform: .identity,
            material: .default,
            smoothing: nil,
            children: [],
            sourceLocation: nil
        )
        let camera = Geometry(
            type: .camera(Camera(
                position: nil,
                orientation: nil,
                scale: nil,
                antialiased: true
            )),
            name: nil,
            transform: Transform(
                scale: nil,
                rotation: Rotation(
                    roll: .radians(-0.5 * .pi),
                    yaw: .radians(-0.4999 * .pi),
                    pitch: .radians(-0.5 * .pi)
                ),
                translation: [2.5539, 0.5531, 0.0131]
            ),
            material: .default,
            smoothing: nil,
            children: [],
            sourceLocation: nil
        )
        let group = Geometry(
            type: .group,
            name: nil,
            transform: .identity,
            material: .default,
            smoothing: nil,
            children: [cube, camera],
            sourceLocation: nil
        )
        XCTAssert(camera.bounds.transformed(by: camera.transform).isEmpty)
        XCTAssertEqual(group.bounds, cube.bounds)
    }

    func testLowDetailPrimitiveBounds() {
        let cylinder = GeometryType.cylinder(segments: 3)
        let cone = GeometryType.cone(segments: 3)
        let sphere = GeometryType.sphere(segments: 3)
        let expected = Vector(0.75, 1, 0.866025403784)
        XCTAssertEqual(cylinder.bounds.size, expected, accuracy: 1e-10)
        XCTAssertEqual(cone.bounds.size, expected, accuracy: 1e-10)
        XCTAssertEqual(sphere.bounds.size, expected, accuracy: 1e-10)
    }

    func testTransformedCubeBounds() {
        let context = EvaluationContext(source: "", delegate: nil)
        let offset = Vector(1, 2, 3)
        context.transform = .translation(offset)
        let shape = Geometry(type: GeometryType.cube, in: context)
        XCTAssertEqual(shape.exactBounds(with: shape.transform).center, offset)
    }

    func testTransformedConeBounds() throws {
        let context = EvaluationContext(source: "", delegate: nil)
        context.transform = Transform(
            rotation: .yaw(.degrees(45)),
            translation: [1, 2, 3]
        )
        let shape = Geometry(type: GeometryType.cone(segments: 5), in: context)
        let bounds = shape.exactBounds(with: shape.transform)
        _ = shape.build { true }
        let mesh = try XCTUnwrap(shape.mesh)
        let expected = mesh.transformed(by: context.transform).bounds
        XCTAssertEqual(bounds.min, expected.min, accuracy: 1e-10)
        XCTAssertEqual(bounds.max, expected.max, accuracy: 1e-10)
    }

    func testTransformedSquarePathBounds() {
        let context = EvaluationContext(source: "", delegate: nil)
        let offset = Vector(1, 2, 3)
        context.transform = .translation(offset)
        let shape = Geometry(type: .path(.square()), in: context)
        XCTAssertEqual(shape.exactBounds(with: shape.transform).center, offset)
    }

    func testTransformedFilledSquareBounds() {
        let context = EvaluationContext(source: "", delegate: nil)
        let offset = Vector(1, 2, 3)
        context.transform = .translation(offset)
        let shape = Geometry(type: GeometryType.fill([.square()]), in: context)
        XCTAssertEqual(shape.exactBounds(with: shape.transform).center, offset)
    }

    // MARK: Intersection

    func testGroupIntersection() throws {
        let a = try evaluate(parse("""
        intersection {
            cube
            translate -0.75
            group {
                cube
                translate 1.5
                cube
            }
        }
        """), delegate: nil)
        let b = try evaluate(parse("""
        intersection {
            cube
            translate -0.75
            union {
                cube
                translate 1.5
                cube
            }
        }
        """), delegate: nil)
        XCTAssertEqual(a.bounds, b.bounds)
        XCTAssertEqual(a.children.count, b.children.count)
        XCTAssertEqual(a.children.map(\.mesh), b.children.map(\.mesh))
        XCTAssertEqual(a.children.map {
            $0.mesh?.polygons.count ?? 0
        }, b.children.map {
            $0.mesh?.polygons.count ?? 0
        })
    }

    // MARK: Material caching

    func testHullColorCaching() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            hull {
                extrude {
                    square { size 0.1 }
                    along circle
                }
            }
        }
        thing { color red }
        thing { color blue }    
        """), delegate: nil, cache: cache)
        _ = scene.build { true }
        // Cache should have only 2 entries: the extrusion and the hull
        XCTAssertEqual(cache.count, 2)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Meshes should not have baked materials, as they are recolorable
        XCTAssertEqual(meshes.first?.materials, [nil])
        XCTAssertEqual(meshes.first, meshes.last)
    }

    func testHullColorCaching2() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            hull {
                extrude {
                    square { size 0.1 }
                    along circle
                }
                cube { color blue }
            }
        }
        thing { color red }
        thing { color blue }    
        """), delegate: nil, cache: cache)
        _ = scene.build { true }
        // Cache should have 4 entries: cube, extrusion, hull1 and hull2
        XCTAssertEqual(cache.count, 4)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // First mesh has a mix of colors, so these are baked into the vertices
        XCTAssertEqual(meshes.first?.materials, [Material(color: .white)])
        XCTAssertEqual(meshes.first?.hasVertexColors, true)
        // Second mesh is uniformly blue, so shouldn't have any baked material
        XCTAssertEqual(meshes.last?.materials, [nil])
        XCTAssertEqual(meshes.last?.hasVertexColors, false)
    }

    func testHullColorCaching3() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            hull {
                extrude {
                    square { size 0.1 }
                    along path {
                        orientation 0 0 -0.4
                        color red
                        curve 0 1 0.75
                        curve -1 0
                        color green
                        curve 0 -1 0.25
                        curve 1 0
                        color blue
                        curve 1 1
                        curve 0 1 0.75
                    }
                }
            }
        }
        thing { color red }
        thing { color blue }
        """), delegate: nil, cache: cache)
        _ = scene.build { true }
        // Cache should have 3 entries: extrusion, hull1 and hull2
        XCTAssertEqual(cache.count, 3)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Meshes both have non-uniform vertex colors so material color must be baked
        XCTAssertEqual(meshes.first?.materials, [Material(color: .white)])
        XCTAssertEqual(meshes.first?.hasVertexColors, true)
        XCTAssertEqual(meshes.first, meshes.last)
    }

    func testHullColorCaching4() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            hull {
                extrude {
                    square { size 0.1 }
                    along path {
                        orientation 0 0 -0.4
                        color red
                        curve 0 1 0.75
                        curve -1 0
                        color green
                        curve 0 -1 0.25
                        curve 1 0
                        color blue
                        curve 1 1
                        curve 0 1 0.75
                    }
                }
            }
        }
        thing { color red }
        thing { color red }
        """), delegate: nil, cache: cache)
        _ = scene.build { true }
        // Cache should have only 2 entries: extrusion and hull
        XCTAssertEqual(cache.count, 2)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Even though meshes have non-uniform vertex colors, override color is same for both so cache hits
        XCTAssertEqual(meshes.first, meshes.last)
    }

    func testHullColorCaching5() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            hull {
                extrude {
                    square { size 0.1 }
                    along path {
                        orientation 0 0 -0.4
                        color rnd rnd rnd
                        curve 0 1 0.75
                        curve -1 0
                        color rnd rnd rnd
                        curve 0 -1 0.25
                        curve 1 0
                        color rnd rnd rnd
                        curve 1 1
                        curve 0 1 0.75
                    }
                }
            }
        }
        thing { color red }
        thing { color red }
        """), delegate: nil, cache: cache)
        _ = scene.build { true }
        // Cache should have 4 entries: extrusion1, extrusion2, hull1 and hull2
        XCTAssertEqual(cache.count, 4)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Even though override colors are the same, each mesh has different random vertex colors
        XCTAssertEqual(meshes.first?.materials, [Material(color: .white)])
        XCTAssertEqual(meshes.first?.materials, meshes.last?.materials)
        XCTAssertEqual(meshes.first?.hasVertexColors, true)
        XCTAssertEqual(meshes.last?.hasVertexColors, true)
        XCTAssertNotEqual(meshes.first, meshes.last)
    }

    func testMinkowskiColorCaching() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            minkowski {
                sphere {
                    size 0.05
                }
                path {
                    orientation 0 0 -0.4
                    color rnd rnd rnd
                    curve 0 1 0.75
                    curve -1 0
                    color rnd rnd rnd
                    curve 0 -1 0.25
                    curve 1 0
                    color rnd rnd rnd
                    curve 1 1
                    curve 0 1 0.75
                }
            }
        }
        thing { color red }
        thing { color red }
        """), delegate: nil, cache: cache)
        _ = scene.build { true }
        // Cache should have 5 entries: sphere, path1, path2, minkowski1, minkowski2
        XCTAssertEqual(cache.count, 5)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Even though override colors are the same, each mesh has different random vertex colors
        XCTAssertEqual(meshes.first?.materials, [Material(color: .white)])
        XCTAssertEqual(meshes.first?.materials, meshes.last?.materials)
        XCTAssertEqual(meshes.first?.hasVertexColors, true)
        XCTAssertEqual(meshes.last?.hasVertexColors, true)
        XCTAssertNotEqual(meshes.first, meshes.last)
    }
}

private func XCTAssertEqual(
    _ a: @autoclosure () throws -> Vector,
    _ b: @autoclosure () throws -> Vector,
    accuracy: Double,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #file,
    line: UInt = #line
) {
    do {
        let a = try a(), b = try b()
        if abs(a.x - b.x) > accuracy || abs(a.y - b.y) > accuracy || abs(a.z - b.z) > accuracy {
            var m = message()
            if m.isEmpty {
                m = "\(a) is not equal to \(b) +/- \(accuracy)"
            }
            XCTFail(m, file: file, line: line)
        }
    } catch {
        XCTFail(error.localizedDescription)
    }
}
