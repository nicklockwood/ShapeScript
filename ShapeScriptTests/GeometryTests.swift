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

class GeometryTests: XCTestCase {
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
                scale: nil
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
}
