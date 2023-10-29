//
//  GeometryTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 28/08/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

@testable import Euclid
@testable import ShapeScript
import XCTest

class GeometryTests: XCTestCase {
    // MARK: Bounds

    func testGroupOfShapeCameraBoundsNotEmpty() {
        let cube = Geometry(
            type: .cube,
            name: nil,
            transform: .identity,
            material: .default,
            smoothing: nil,
            wrapMode: nil,
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
                offset: Vector(2.5539, 0.5531, 0.0131),
                rotation: Rotation(
                    roll: .radians(-0.5 * .pi),
                    yaw: .radians(-0.4999 * .pi),
                    pitch: .radians(-0.5 * .pi)
                ),
                scale: nil
            ),
            material: .default,
            smoothing: nil,
            wrapMode: nil,
            children: [],
            sourceLocation: nil
        )
        let group = Geometry(
            type: .group,
            name: nil,
            transform: .identity,
            material: .default,
            smoothing: nil,
            wrapMode: nil,
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
        XCTAssert(cylinder.bounds.size.isEqual(to: expected))
        XCTAssert(cone.bounds.size.isEqual(to: expected))
        XCTAssert(sphere.bounds.size.isEqual(to: expected))
    }

    func testTransformedCubeBounds() {
        let context = EvaluationContext(source: "", delegate: nil)
        let offset = Vector(1, 2, 3)
        context.transform = Transform.offset(offset)
        let shape = Geometry(type: GeometryType.cube, in: context)
        XCTAssertEqual(shape.exactBounds(with: shape.transform).center, offset)
    }

    func testTransformedConeBounds() {
        let context = EvaluationContext(source: "", delegate: nil)
        context.transform = Transform(
            offset: Vector(1, 2, 3),
            rotation: .yaw(.degrees(45))
        )
        let shape = Geometry(type: GeometryType.cone(segments: 5), in: context)
        let bounds = shape.exactBounds(with: shape.transform)
        _ = shape.build { true }
        let expected = shape.mesh?.transformed(by: context.transform).bounds
        XCTAssert(bounds.isEqual(to: expected ?? .empty))
    }

    func testTransformedSquarePathBounds() {
        let context = EvaluationContext(source: "", delegate: nil)
        let offset = Vector(1, 2, 3)
        context.transform = Transform.offset(offset)
        let shape = Geometry(type: GeometryType.path(.square()), in: context)
        XCTAssertEqual(shape.exactBounds(with: shape.transform).center, offset)
    }

    func testTransformedFilledSquareBounds() {
        let context = EvaluationContext(source: "", delegate: nil)
        let offset = Vector(1, 2, 3)
        context.transform = Transform.offset(offset)
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
        XCTAssertEqual(a.children.map { $0.mesh }, b.children.map { $0.mesh })
        XCTAssertEqual(a.children.map {
            $0.mesh?.polygons.count ?? 0
        }, b.children.map {
            $0.mesh?.polygons.count ?? 0
        })
    }
}
