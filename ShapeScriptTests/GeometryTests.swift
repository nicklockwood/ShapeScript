//
//  GeometryTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 28/08/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

@testable import Euclid
@testable import ShapeScript
import Foundation
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
        XCTAssert(camera.overestimatedBounds.isEmpty)
        XCTAssertEqual(group.overestimatedBounds, cube.overestimatedBounds)
    }

    func testSceneVisibleBoundsIgnoreHiddenSiblingsWhenGeometryIsFocused() throws {
        let scene = try evaluate(parse("""
        group {
            focus cube {
                position 10
            }
            cube {
                position 100
            }
        }
        """), delegate: nil)

        XCTAssertEqual(scene.geometry.overestimatedBounds.center, [55, 0, 0])
        XCTAssertEqual(scene.geometry.overestimatedBounds.size, [91, 1, 1])
        XCTAssertEqual(scene.visibleBounds.center, [10, 0, 0])
        XCTAssertEqual(scene.visibleBounds.size, [1, 1, 1])
    }

    func testSceneVisibleGeometryIgnoresHiddenSiblingsWhenGeometryIsFocused() throws {
        let scene = try evaluate(parse("""
        group {
            focus cube {
                position 10
            }
            cube {
                position 100
            }
        }
        """), delegate: nil)

        XCTAssertEqual(scene.geometry.children.first?.children.count, 2)
        let group = try XCTUnwrap(scene.visibleGeometry.children.first)
        XCTAssertEqual(group.children.count, 1)
        XCTAssertEqual(group.children.first?.transform.translation, [10, 0, 0])
        XCTAssertEqual(scene.visibleGeometry.overestimatedBounds.center, scene.visibleBounds.center)
        XCTAssertEqual(scene.visibleGeometry.overestimatedBounds.size, scene.visibleBounds.size)
    }

    func testSceneVisibleBoundsUseOnlyFocusedRootGeometry() throws {
        let scene = try evaluate(parse("""
        focus cube {
            position 10
        }
        sphere {
            position 100
        }
        """), delegate: nil)

        XCTAssertEqual(scene.visibleBounds.center, [10, 0, 0])
        XCTAssertEqual(scene.visibleBounds.size, [1, 1, 1])
    }

    func testGroupedChildrenAreRenderedInScene() throws {
        let scene = try evaluate(parse("""
        group {
            cube
            sphere
        }
        """), delegate: nil)

        let group = try XCTUnwrap(scene.children.first)
        let cube = try XCTUnwrap(group.children.first)
        let sphere = try XCTUnwrap(group.children.last)

        XCTAssertTrue(cube.isRenderedInScene(focus: false))
        XCTAssertTrue(sphere.isRenderedInScene(focus: false))
    }

    func testBooleanChildrenAreOnlyRenderedInSceneWhenDebugged() throws {
        let scene = try evaluate(parse("""
        difference {
            cube {
                size 0.8
                color blue
            }
            debug sphere {
                color green
            }
        }
        """), delegate: nil)

        let difference = try XCTUnwrap(scene.children.first)
        let cube = try XCTUnwrap(difference.children.first)
        let sphere = try XCTUnwrap(difference.children.last)

        XCTAssertFalse(cube.debug)
        XCTAssertTrue(sphere.debug)
        XCTAssertTrue(difference.isRenderedInScene(focus: false))
        XCTAssertFalse(cube.isRenderedInScene(focus: false))
        XCTAssertTrue(sphere.isRenderedInScene(focus: false))
    }

    func testBooleanChildrenAreOnlyRenderedInSceneWhenFocused() throws {
        let scene = try evaluate(parse("""
        difference {
            focus cube {
                size 0.8
            }
            sphere
        }
        """), delegate: nil)

        let difference = try XCTUnwrap(scene.children.first)
        let cube = try XCTUnwrap(difference.children.first)
        let sphere = try XCTUnwrap(difference.children.last)

        XCTAssertTrue(cube.isFocused)
        XCTAssertFalse(sphere.isFocused)
        XCTAssertFalse(difference.isRenderedInScene(focus: true))
        XCTAssertTrue(cube.isRenderedInScene(focus: true))
        XCTAssertFalse(sphere.isRenderedInScene(focus: true))
    }

    func testWithoutUnfocusedGeometryRemovesHiddenSiblings() throws {
        let scene = try evaluate(parse("""
        group {
            focus cube {
                position 10
            }
            cube {
                position 100
            }
        }
        """), delegate: nil)

        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.childIsFocused)
        XCTAssertEqual(geometry.children.count, 2)

        let copy = geometry.withoutUnfocusedGeometry()
        XCTAssertEqual(copy.children.count, 1)
        XCTAssertEqual(copy.children[0].transform.translation, [10, 0, 0])
        XCTAssertEqual(copy.objectCount, 1)
        XCTAssertEqual(copy.polygons { false }.count, 6)
        XCTAssertEqual(copy.overestimatedBounds.center, [10, 0, 0])
        XCTAssertEqual(copy.exactBounds(with: copy.transform).size, [1, 1, 1])
    }

    func testWithoutDebugClearsDebugState() throws {
        let scene = try evaluate(parse("""
        group {
            cube
            debug cube {
                position 10
            }
        }
        """), delegate: nil)

        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.childDebug)
        XCTAssertTrue(geometry.children[1].debug)

        let copy = geometry.withoutDebug()
        XCTAssertFalse(copy.childDebug)
        XCTAssertFalse(copy.children[0].debug)
        XCTAssertFalse(copy.children[1].debug)
        XCTAssertEqual(copy.children.count, 2)
        XCTAssertEqual(copy.children[1].transform.translation, [10, 0, 0])
    }

    func testDebugAndFocusDoNotAffectGeometryIdentity() throws {
        let scene = try evaluate(parse("""
        cube
        debug cube
        focus cube
        """), delegate: nil)

        guard scene.children.count == 3 else {
            XCTFail()
            return
        }
        let normal = scene.children[0]
        let debug = scene.children[1]
        let focused = scene.children[2]

        XCTAssertFalse(normal.debug)
        XCTAssertFalse(normal.isFocused)
        XCTAssertTrue(debug.debug)
        XCTAssertFalse(debug.isFocused)
        XCTAssertFalse(focused.debug)
        XCTAssertTrue(focused.isFocused)

        XCTAssertEqual(normal, debug)
        XCTAssertEqual(normal, focused)
        XCTAssertEqual(normal.hashValue, debug.hashValue)
        XCTAssertEqual(normal.hashValue, focused.hashValue)
        XCTAssertEqual(normal.cacheKey, debug.cacheKey)
        XCTAssertEqual(normal.cacheKey, focused.cacheKey)
    }

    func testLowDetailPrimitiveBounds() {
        let cylinder = GeometryType.cylinder(segments: 3)
        let cone = GeometryType.cone(segments: 3)
        let sphere = GeometryType.sphere(segments: 3)
        let expected = Vector(0.75, 1, 0.866025403784)
        XCTAssertEqual(cylinder.bounds.size, expected, accuracy: epsilon)
        XCTAssertEqual(cone.bounds.size, expected, accuracy: epsilon)
        XCTAssertEqual(sphere.bounds.size, expected, accuracy: epsilon)
    }

    func testIcospherePrimitiveBounds() {
        XCTAssertEqual(GeometryType.icosphere(subdivisions: 0).bounds.size, Vector(size: 1))
    }

    func testPrimitiveGenerationCanBeCancelled() {
        let context = EvaluationContext(source: "", delegate: nil)
        for type in [
            GeometryType.cone(segments: 256),
            .cylinder(segments: 256),
            .icosphere(subdivisions: 6),
            .sphere(segments: 256),
        ] {
            let shape = Geometry(type: type, in: context)
            nonisolated(unsafe) var checks = 0
            XCTAssertFalse(shape.build {
                checks += 1
                return checks < 4
            })
            XCTAssertLessThan(checks, 10)
            XCTAssertLessThan(shape.mesh?.polygons.count ?? .max, 256 * 2)
        }
    }

    func testTransformedCubeBounds() {
        let context = EvaluationContext(source: "", delegate: nil)
        let offset = Vector(1, 2, 3)
        context.state.transform = .translation(offset)
        let shape = Geometry(type: GeometryType.cube, in: context)
        XCTAssertEqual(shape.exactBounds(with: shape.transform).center, offset)
    }

    func testTransformedConeBounds() throws {
        let context = EvaluationContext(source: "", delegate: nil)
        context.state.transform = Transform(
            rotation: .yaw(.degrees(45)),
            translation: [1, 2, 3]
        )
        let shape = Geometry(type: GeometryType.cone(segments: 5), in: context)
        let bounds = shape.exactBounds(with: shape.transform)
        _ = shape.build { true }
        let mesh = try XCTUnwrap(shape.mesh)
        let expected = mesh.transformed(by: context.state.transform).bounds
        XCTAssertEqual(bounds.min, expected.min, accuracy: epsilon)
        XCTAssertEqual(bounds.max, expected.max, accuracy: epsilon)
    }

    func testTransformedSquarePathBounds() {
        let context = EvaluationContext(source: "", delegate: nil)
        let offset = Vector(1, 2, 3)
        context.state.transform = .translation(offset)
        let shape = Geometry(type: .path(.square()), in: context)
        XCTAssertEqual(shape.exactBounds(with: shape.transform).center, offset)
    }

    func testSquareCommandUsesPathPrimitiveGeometry() throws {
        let scene = try evaluate(parse("""
        color red
        square {
            position 1 2
            size 3 4
        }
        """), delegate: nil)
        let geometry = try XCTUnwrap(scene.children.first)

        XCTAssertEqual(geometry.type, .square)
        XCTAssertEqual(geometry.material.color, .red)
        XCTAssertEqual(
            geometry.path(pretransformed: true),
            Path.square(color: .red)
                .scaled(by: [3, 4]).translated(by: [1, 2])
        )
        XCTAssertFalse(geometry.hasMesh)
    }

    func testCircleCommandUsesPathPrimitiveGeometry() throws {
        let scene = try evaluate(parse("""
        detail 12
        color blue
        circle {
            position 1 2
            size 3 4
        }
        """), delegate: nil)
        let geometry = try XCTUnwrap(scene.children.first)

        XCTAssertEqual(geometry.type, .circle(segments: 12))
        XCTAssertEqual(geometry.material.color, .blue)
        XCTAssertEqual(geometry.path(pretransformed: true), Path.circle(
            segments: 12,
            color: .blue
        ).scaled(by: [3, 4]).translated(by: [1, 2]))
        XCTAssertFalse(geometry.hasMesh)
    }

    func testTransformedFilledSquareBounds() {
        let context = EvaluationContext(source: "", delegate: nil)
        let offset = Vector(1, 2, 3)
        context.state.transform = .translation(offset)
        let shape = Geometry(type: GeometryType.fill([.square()]), in: context)
        XCTAssertEqual(shape.exactBounds(with: shape.transform).center, offset)
        XCTAssertEqual(shape.overestimatedBounds.size, [1, 1, 0])
        XCTAssertEqual(shape.overestimatedBounds.center, [1, 2, 3])
        XCTAssertEqual(shape.exactBounds(with: shape.transform), shape.overestimatedBounds)
    }

    func testSelfIntersectingFilledPathBuildsMesh() throws {
        let scene = try evaluate(parse("""
        fill path {
            curve 0
            curve 1
            curve 0 2
            curve 1 2
            curve 0
        }
        """), delegate: nil)
        XCTAssertTrue(scene.build { true })

        let geometry = try XCTUnwrap(scene.children.first)
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertFalse(mesh.bounds.isEmpty)
        XCTAssertEqual(mesh.bounds, Bounds(min: [0.26, 0, 0], max: [0.74, 2, 0]))
        XCTAssertEqual(geometry.overestimatedBounds, mesh.bounds)
    }

    func testGeneratedGeometryIsDeterministic() throws {
        let program = """
        detail 16
        difference cube { size 0.8 } sphere
        """

        func generatedMeshFingerprint() throws -> String {
            let scene = try evaluate(parse(program), delegate: TestDelegate())
            XCTAssertTrue(scene.build { true })
            let geometry = Geometry(
                type: .group,
                name: nil,
                transform: .identity,
                material: .default,
                smoothing: nil,
                children: scene.children,
                sourceLocation: nil
            )
            return geometry.flattened().orderedFingerprint
        }

        let expected = try generatedMeshFingerprint()
        for _ in 0 ..< 20 {
            XCTAssertEqual(try generatedMeshFingerprint(), expected)
        }
    }

    func testTextFourCounterUsesOddEvenFillForCaps() throws {
        #if canImport(CoreText)
        func centroid(of path: Path) -> Vector {
            let positions = path.points.dropLast(path.isClosed ? 1 : 0).map(\.position)
            return positions.reduce(.zero, +) / Double(positions.count)
        }

        func mesh(for program: String) throws -> Mesh {
            let scene = try evaluate(parse(program), delegate: TestDelegate())
            XCTAssertEqual(scene.children.count, 1)
            let geometry = try XCTUnwrap(scene.children.first)
            XCTAssertTrue(geometry.build { true })
            return geometry.flattened()
        }

        func capCovers(_ point: Vector, in mesh: Mesh) -> Bool {
            mesh.polygons.contains { polygon in
                guard abs(polygon.plane.normal.z) > 0.5,
                      let z = polygon.vertices.first?.position.z
                else {
                    return false
                }
                return polygon.intersects(Vector(point.x, point.y, z))
            }
        }

        let glyph = try XCTUnwrap(Path.text("4").first)
        let subpaths = glyph.subpaths
        let subpathPolygons = subpaths.map { Polygon($0) }
        let subpathPoints = subpaths.map {
            Array($0.points.dropLast($0.isClosed ? 1 : 0).map(\.position))
        }
        let counterIndex = try XCTUnwrap(subpaths.indices.first { index in
            subpathPolygons.indices.contains { otherIndex in
                guard otherIndex != index else {
                    return false
                }
                guard let polygon = subpathPolygons[otherIndex] else {
                    return false
                }
                let insideCount = subpathPoints[index].filter {
                    polygon.bounds.intersects($0) && polygon.intersects($0)
                }.count
                return insideCount > subpathPoints[index].count / 2
            }
        })
        let counterPoint = centroid(of: subpaths[counterIndex])

        let fillMesh = try mesh(for: "fill text \"4\"")
        XCTAssertFalse(capCovers(counterPoint, in: fillMesh))
        let extrudeMesh = try mesh(for: "extrude text \"4\"")
        XCTAssertFalse(capCovers(counterPoint, in: extrudeMesh))
        let alongMesh = try mesh(for: """
        extrude {
            text "4"
            along path {
                point 0 0 -0.5
                point 0 0 0.5
            }
        }
        """)
        XCTAssertFalse(capCovers(counterPoint, in: alongMesh))
        #endif
    }

    func testTransformedMultipleFilledPathBounds() {
        let context = EvaluationContext(source: "", delegate: nil)
        let offset = Vector(1, 2, 3)
        context.state.transform = .translation(offset)
        let shape = Geometry(type: GeometryType.fill([
            .square(),
            .circle(radius: 0.5).translated(by: [1, 0, 0]),
        ]), in: context)
        XCTAssertEqual(shape.overestimatedBounds.size, [2, 1, 0])
        XCTAssertEqual(shape.overestimatedBounds.center, [1.5, 2, 3])
        XCTAssertEqual(shape.exactBounds(with: shape.transform), shape.overestimatedBounds)
    }

    func testTransformedMultipleExtrudedPathBounds() {
        let context = EvaluationContext(source: "", delegate: nil)
        let offset = Vector(1, 2, 3)
        context.state.transform = .translation(offset)
        let shape = Geometry(type: GeometryType.extrude([
            .square(),
            .circle(radius: 0.5).translated(by: [1, 0, 0]),
        ], .default), in: context)
        XCTAssertEqual(shape.overestimatedBounds.size, [2, 1, 1])
        XCTAssertEqual(shape.overestimatedBounds.center, [1.5, 2, 3])
        XCTAssertEqual(shape.exactBounds(with: shape.transform), shape.overestimatedBounds)
    }

    func testStraightExtrusionBoundsIgnoreMiterLimit() {
        let context = EvaluationContext(source: "", delegate: nil)
        let shape = Geometry(type: GeometryType.extrude([
            .square(),
        ], .init(
            along: [],
            twist: .zero,
            align: nil,
            miterLimit: 1
        )), in: context)
        XCTAssertEqual(shape.type, .extrude([.square()], .default))
        XCTAssertEqual(shape.overestimatedBounds.size, [1, 1, 1])
        XCTAssertEqual(shape.exactBounds(with: shape.transform), shape.overestimatedBounds)
    }

    func testTransformedMultipleExtrudedPathBoundsWithTwist() {
        let context = EvaluationContext(source: "", delegate: nil)
        let offset = Vector(1, 2, 3)
        context.state.transform = .translation(offset)
        let shape = Geometry(type: GeometryType.extrude([
            .square(),
            .circle(radius: 0.5).translated(by: [1, 0, 0]),
        ], .init(
            along: [.line([0, 0, -0.5], [0, 0, 0.5])],
            twist: .halfPi,
            align: nil,
            miterLimit: nil
        )), in: context)
        XCTAssertEqual(shape.overestimatedBounds.size, [2, 2, 1])
        XCTAssertEqual(shape.overestimatedBounds.center, [1.5, 1.5, 3])
        XCTAssertEqual(shape.exactBounds(with: shape.transform), shape.overestimatedBounds)
    }

    func testExtrusionBoundsRespectMiterLimit() {
        let profile = Path.square(size: 0.2)
        let along = Path([
            .point(0, 0, 0),
            .point(10, 0, 0),
            .point(0, 1, 0),
        ])
        let limitedOptions = ExtrudeOptions(
            along: [along],
            twist: .zero,
            align: nil,
            miterLimit: 1
        )
        let unlimitedBounds = GeometryType.extrude([profile], .init(
            along: [along],
            twist: .zero,
            align: nil,
            miterLimit: nil
        )).bounds
        let limitedBounds = GeometryType.extrude([profile], limitedOptions).bounds
        let meshBounds = Mesh.extrude(
            profile,
            along: along,
            miterLimit: limitedOptions.miterLimit
        ).bounds

        XCTAssertNotEqual(limitedBounds, unlimitedBounds)
        XCTAssertEqual(limitedBounds, meshBounds)
    }

    func testDetailedExtrusionBuildTiming() throws {
        let path = Path([
            .point(-0.075, -0.344),
            .point(-0.075, -0.328),
            .point(-0.060, -0.328),
            .point(-0.060, -0.281),
            .point(0.060, -0.281),
            .point(0.060, -0.217),
            .point(0.075, -0.217),
            .point(0.075, -0.344),
            .point(-0.075, -0.344),
        ])
        let along = Path.curve([
            .point(-1.011, 0, 0),
            .point(-1.011, 1.587, 0),
            .curve(-0.934, 1.973, 0),
            .curve(-0.715, 2.308, 0),
            .curve(-0.386, 2.531, 0),
            .curve(0, 2.609, 0),
            .curve(0.386, 2.531, 0),
            .curve(0.715, 2.308, 0),
            .curve(0.934, 1.973, 0),
            .point(1.587, 1.011, 0),
        ], detail: 99)
        let geometry = Geometry(
            type: .extrude([path], .init(
                along: [along],
                twist: .zero,
                align: nil,
                miterLimit: nil
            )),
            in: EvaluationContext(source: "", delegate: nil)
        )

        let rawExtrusion = timed("detailed extrusion raw Mesh.extrude") {
            Mesh.extrude(path, along: along)
        }
        let rawMesh = rawExtrusion.result
        XCTAssertFalse(rawMesh.isEmpty)
        XCTAssertLessThan(rawExtrusion.duration, 1.5)

        let build = timed("detailed extrusion Geometry.build") {
            geometry.build { true }
        }
        let buildSucceeded = build.result
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertTrue(buildSucceeded)
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertLessThan(build.duration, 1.5)
    }

    func testStraightExtrusionBuildIgnoresMiterLimit() throws {
        let geometry = Geometry(
            type: .extrude([.square()], .init(
                along: [],
                twist: .zero,
                align: nil,
                miterLimit: 1
            )),
            in: EvaluationContext(source: "", delegate: nil)
        )

        XCTAssertTrue(geometry.build { true })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertEqual(mesh.bounds.size, [1, 1, 1])
    }

    func testTransformedMultipleLathedPathBounds() {
        let context = EvaluationContext(source: "", delegate: nil)
        let offset = Vector(1, 2, 3)
        context.state.transform = .translation(offset)
        let shape = Geometry(type: GeometryType.lathe([
            .square(),
            .circle(radius: 0.5).translated(by: [0, 1, 0]),
        ], segments: 4), in: context)
        XCTAssertEqual(shape.overestimatedBounds.size, [1, 2, 1])
        XCTAssertEqual(shape.overestimatedBounds.center, [1, 2.5, 3])
        XCTAssertEqual(shape.exactBounds(with: shape.transform), shape.overestimatedBounds)
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
        XCTAssertEqual(a.visibleBounds, b.visibleBounds)
        XCTAssertEqual(a.children.count, b.children.count)
        XCTAssertEqual(a.children.map(\.mesh), b.children.map(\.mesh))
        XCTAssertEqual(a.children.map {
            $0.mesh?.polygons.count ?? 0
        }, b.children.map {
            $0.mesh?.polygons.count ?? 0
        })
    }

    // MARK: Sub-object caching

    func testFilledCharacterCaching() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        fill text "Hello World"    
        """), delegate: nil, cache: cache)
        _ = scene.build { true }
        #if canImport(CoreText)
        // Cache should have only 8 entries as the 'o' and 'l' are repeated
        XCTAssertEqual(cache.count, 8)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 1)
        #endif
    }

    func testExtrudedCharacterCaching() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        extrude text "Hello World"    
        """), delegate: nil, cache: cache)
        _ = scene.build { true }
        #if canImport(CoreText)
        // Cache should have only 8 entries as the 'o' and 'l' are repeated
        XCTAssertEqual(cache.count, 8)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 1)
        #endif
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
        // Cache should have 4 entries: extrusion1, extrusion2, hull1 and hull2
        XCTAssertEqual(cache.count, 4)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Meshes both have non-uniform vertex colors so material color must be baked
        XCTAssertEqual(meshes.first?.materials, [Material(color: .white)])
        XCTAssertEqual(meshes.last?.materials, [Material(color: .white)])
        XCTAssertEqual(meshes.first?.hasVertexColors, true)
        XCTAssertEqual(meshes.last?.hasVertexColors, true)
        XCTAssertNotEqual(meshes.first, meshes.last)
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

    func testExtrusionColorCaching() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            extrude {
                path {
                    orientation 0 0 -0.4
                    curve 0 1 0.75
                    curve -1 0
                    curve 0 -1 0.25
                    curve 1 0
                    curve 1 1
                    curve 0 1 0.75
                }
            }
        }
        thing { color red }
        thing { color green }
        """), delegate: nil, cache: cache)
        _ = scene.build { true }
        // Cache should have only 1 entry: path
        XCTAssertEqual(cache.count, 1)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Mesh colors are uniform, so neither has any baked material
        XCTAssertEqual(meshes.first?.materials, [nil])
        XCTAssertEqual(meshes.last?.materials, [nil])
        XCTAssertEqual(meshes.first?.hasVertexColors, false)
        XCTAssertEqual(meshes.last?.hasVertexColors, false)
        XCTAssertEqual(meshes.first, meshes.last)
    }

    func testTwistedExtrusionColorCaching() throws {
        let cache = GeometryCache()
        let scene = try evaluate(parse("""
        define thing {
            extrude {
                square { color blue }
                twist 1
            }
        }
        thing { color red }
        thing { color green }
        """), delegate: nil, cache: cache)
        _ = scene.build { true }
        // Cache should have only 1 entry: extrude
        XCTAssertEqual(cache.count, 1)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Mesh colors are uniform, so neither has any baked material
        XCTAssertEqual(meshes.first?.materials, [nil])
        XCTAssertEqual(meshes.last?.materials, [nil])
        XCTAssertEqual(meshes.first?.hasVertexColors, false)
        XCTAssertEqual(meshes.last?.hasVertexColors, false)
        XCTAssertEqual(meshes.first, meshes.last)
        // Geometries are not recolored
        XCTAssertEqual(scene.children.first?.material, Material(color: .blue))
        XCTAssertEqual(scene.children.last?.material, Material(color: .blue))
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
                    curve 0 1 0.75
                    curve -1 0
                    curve 0 -1 0.25
                    curve 1 0
                    curve 1 1
                    curve 0 1 0.75
                }
            }
        }
        thing { color red }
        thing { color green }
        """), delegate: nil, cache: cache)
        _ = scene.build { true }
        // Cache should have only 3 entries: sphere, path, minkowski
        XCTAssertEqual(cache.count, 3)
        let meshes = scene.children.compactMap(\.mesh)
        XCTAssertEqual(meshes.count, 2)
        // Mesh colors are uniform, so neither has any baked material
        XCTAssertEqual(meshes.first?.materials, [nil])
        XCTAssertEqual(meshes.last?.materials, [nil])
        XCTAssertEqual(meshes.first?.hasVertexColors, false)
        XCTAssertEqual(meshes.last?.hasVertexColors, false)
        XCTAssertEqual(meshes.first, meshes.last)
    }

    func testMinkowskiColorCaching2() throws {
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

private extension Mesh {
    var orderedFingerprint: String {
        polygons.map { polygon in
            let vertices = polygon.vertices.map { vertex in
                [
                    vertex.position.components,
                    vertex.normal.components,
                    vertex.texcoord.components,
                    vertex.color.components,
                ].description
            }.joined(separator: "|")
            return "\(String(describing: polygon.material)):\(vertices)"
        }.joined(separator: "\n")
    }
}

private func timed<T>(
    _ label: String,
    _ operation: () throws -> T
) rethrows -> (result: T, duration: TimeInterval) {
    let start = Date.timeIntervalSinceReferenceDate
    do {
        let result = try operation()
        let duration = Date.timeIntervalSinceReferenceDate - start
        print(String(format: "Timing: %@ %.3fs", label, duration))
        return (result, duration)
    } catch {
        let duration = Date.timeIntervalSinceReferenceDate - start
        print(String(format: "Timing: %@ %.3fs", label, duration))
        throw error
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
