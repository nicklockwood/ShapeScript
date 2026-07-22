//
//  SVGPathTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 18/02/2024.
//  Copyright © 2024 Nick Lockwood. All rights reserved.
//

@testable import Euclid
@testable import ShapeScript
import SVGPath
import XCTest

final class SVGPathTests: XCTestCase {
    func testNoCrashWithEmptyPath() {
        XCTAssertEqual(SVGPath(Path.empty), SVGPath(commands: []))
    }

    func testFillSVGPathWithDoubledBackSegments() throws {
        let path = try Path(
            SVGPath(string: smallSVGPathWithDoubledBackSegment),
            detail: 1,
            color: ShapeScript.Material.default.color
        )
        let mesh = Mesh.fill(path)

        XCTAssertEqual(path.subpaths.count, 2)
        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertEqual(mesh.bounds, Bounds(min: [0, -20, 0], max: [20, 0, 0]))
    }

    func testExtrudeSVGPathWithDoubledBackSegments() throws {
        let path = try Path(SVGPath(
            string: svgPathWithDoubledBackSegments,
            with: .init(invertYAxis: false)
        ), detail: 1)
        let mesh = Mesh.extrude(path, depth: 8).makeWatertight()
        let capArea = Mesh(mesh.polygons.filter {
            abs($0.plane.normal.z) > 0.5
        }).surfaceArea

        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertTrue(mesh.isConsistentlyWound)
        XCTAssertEqual(mesh.bounds, Bounds(min: [0, 0, -4], max: [200, 200, 4]))
        XCTAssertEqual(capArea, Mesh.fill(path).surfaceArea, accuracy: epsilon)

        let fillPolygons = Mesh.fill(path, faces: .front).polygons
        for polygon in mesh.polygons where abs(polygon.plane.normal.z) < 0.5 {
            let projectedPoints = Set(polygon.vertices.map {
                Vector($0.position.x, $0.position.y, 0)
            })
            XCTAssertLessThanOrEqual(projectedPoints.count, 2)
            let normal = Vector(polygon.plane.normal.x, polygon.plane.normal.y, 0).normalized()
            let midpoint = polygon.vertices.reduce(.zero) { $0 + $1.position } / Double(polygon.vertices.count)
            let normalSideIsFilled = fillPolygons.containsProjectedPoint(midpoint + normal * 1e-4)
            let backSideIsFilled = fillPolygons.containsProjectedPoint(midpoint - normal * 1e-4)
            guard normalSideIsFilled != backSideIsFilled else {
                continue
            }
            XCTAssertFalse(normalSideIsFilled)
            XCTAssertTrue(backSideIsFilled)
        }
    }

    func testExtrudeSVGPathWithDoubledBackSegmentsAlongBentPath() throws {
        let path = try Path(
            SVGPath(string: svgPathWithDoubledBackSegments),
            detail: 4,
            color: ShapeScript.Material.default.color
        )
        let along = Path([
            .point(1, 20),
            .point(0, 10),
            .point(0, -10),
        ], color: ShapeScript.Material.default.color)
        let mesh = Mesh
            .extrude(path, along: along)
            .makeWatertight()

        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertTrue(mesh.isConsistentlyWound)
        XCTAssertGreaterThan(mesh.signedVolume, 0)
        try assertCapsMatchFilledSections(for: path, extrudedAlong: along, in: mesh)
    }

    func testShapeScriptExtrudesSVGPathWithDoubledBackSegmentsAlongBentPath() throws {
        let scene = try evaluate(parse("""
        extrude {
            svgpath "\(svgPathWithDoubledBackSegments)"
            along path {
                point 1 20
                point 0 10
                point 0 -10
            }
        }
        """), delegate: nil)
        XCTAssertTrue(scene.build { true })

        let geometry = try XCTUnwrap(scene.children.first)
        let mesh = try XCTUnwrap(geometry.mesh).transformed(by: geometry.transform)
        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertTrue(mesh.isConsistentlyWound)
        XCTAssertGreaterThan(mesh.signedVolume, 0)
        let path = try Path(
            SVGPath(string: svgPathWithDoubledBackSegments),
            detail: 4,
            color: ShapeScript.Material.default.color
        )
        let along = Path([
            .point(1, 20),
            .point(0, 10),
            .point(0, -10),
        ], color: ShapeScript.Material.default.color)
        try assertCapsMatchFilledSections(for: path, extrudedAlong: along, in: mesh)
    }
}

private func assertCapsMatchFilledSections(
    for path: Path,
    extrudedAlong along: Path,
    in mesh: Mesh,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let sections = path.extrusionContours(along: along)
    let capSpecs = try [
        (section: XCTUnwrap(sections.first), outwardNormal: Vector(0.099503719021, 0.99503719021, 0)),
        (section: XCTUnwrap(sections.last), outwardNormal: Vector(0, -1, 0)),
    ]
    for (section, outwardNormal) in capSpecs {
        let expectedPolygons = Mesh.fill(section, faces: .front).polygons
        let expectedArea = abs(expectedPolygons.signedProjectedArea(along: outwardNormal))
        let actualPolygons = mesh.polygons.coplanar(with: section, normal: outwardNormal)
        let actualArea = actualPolygons.signedProjectedArea(along: outwardNormal)
        XCTAssertEqual(actualArea, expectedArea, accuracy: max(epsilon, expectedArea * 1e-9), file: file, line: line)
        XCTAssertTrue(actualPolygons.allSatisfy(\.isConvex), file: file, line: line)
        XCTAssertTrue(
            actualPolygons.matchesFilledCoverage(of: expectedPolygons, sampleSpacing: 4),
            file: file,
            line: line
        )
    }
}

private extension Collection<Euclid.Polygon> {
    func signedProjectedArea(along normal: Vector) -> Double {
        reduce(0) { $0 + $1.vertices.vectorArea.dot(normal) }
    }

    func coplanar(with path: Path, normal: Vector) -> [Euclid.Polygon] {
        filter { polygon in
            abs(polygon.plane.normal.dot(normal)) > 0.99 &&
                polygon.vertices.allSatisfy { path.plane?.intersects($0.position) == true }
        }
    }

    func matchesFilledCoverage(
        of expectedPolygons: [Euclid.Polygon],
        sampleSpacing: Double
    ) -> Bool {
        guard let plane = expectedPolygons.first?.plane else {
            return isEmpty
        }
        let flatteningPlane = FlatteningPlane(normal: plane.normal)
        let points = expectedPolygons.flatMap { polygon in
            polygon.vertices.map { flatteningPlane.flattenPoint($0.position) }
        }
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max()
        else {
            return isEmpty
        }
        for x in stride(from: minX + sampleSpacing / 2, to: maxX, by: sampleSpacing) {
            for y in stride(from: minY + sampleSpacing / 2, to: maxY, by: sampleSpacing) {
                let point = flatteningPlane.unflattenPoint([x, y], onto: plane)
                let expectedContains = expectedPolygons.containsCoplanarPoint(point)
                let actualContains = containsCoplanarPoint(point)
                if expectedContains != actualContains {
                    return false
                }
            }
        }
        return true
    }

    func containsCoplanarPoint(_ point: Vector) -> Bool {
        contains {
            $0.plane.intersects(point) && $0.intersectsCoplanarPoint(point)
        }
    }

    func containsProjectedPoint(_ point: Vector) -> Bool {
        contains { $0.containsProjectedPoint(point) }
    }
}

private extension Euclid.Polygon {
    func containsProjectedPoint(_ point: Vector) -> Bool {
        let positions = vertices.map(\.position)
        var contains = false
        var previousIndex = positions.count - 1
        for index in positions.indices {
            let current = positions[index]
            let previous = positions[previousIndex]
            if (current.y > point.y) != (previous.y > point.y) {
                let x = (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x
                if point.x < x {
                    contains.toggle()
                }
            }
            previousIndex = index
        }
        return contains
    }
}

private let smallSVGPathWithDoubledBackSegment = """
M 0,0 H 20 V 10 H 10 H 20 V 20 H 0 Z
"""

private let svgPathWithDoubledBackSegments = """
m 0,0 v 56 c 19.494146,0 36.937569,0 56,0 V 0 Z m 64,0 v 8 h 8 V 0 Z m 8,8 v 8 h -8 v 8 \
h 8 v 8 h 8 v 8 h 8 v -8 c 5.333333,0 10.666667,0 16,0 v 8 c 5.33333,0 10.66667,0 16,0 \
0,-5.333333 0,-10.666667 0,-16 h -8 c 0,-5.333333 0,-10.666667 0,-16 h 8 V 0 H 96 v 8 h \
8 v 8 H 80 V 8 Z m 8,0 h 8 V 0 h -8 z m 24,32 h -8 c 0,5.333333 0,10.666667 0,16 h 8 c \
0,-5.333333 0,-10.666667 0,-16 z m -8,16 h -8 v -8 h -8 c 0,5.333333 0,10.666667 0,16 h \
8 c 0,5.333333 0,10.666667 0,16 h 8 v 8 h -8 v -8 h -8 c 0,8 0,16 0,24 5.333333,0 \
10.666667,0 16,0 v -8 h 8 v -8 h 8 v -8 h -8 v -8 h -8 c 0,-5.333333 0,-10.666667 0,-16 \
z m 16,24 h 8 c 0,5.333333 0,10.666667 0,16 h 8 v 8 h -8 c 0,5.33333 0,10.66667 0,16 h 8 \
v -8 h 8 c 0,-8 0,-16 0,-24 h -8 v -8 c 5.33333,0 10.66667,0 16,0 0,11.776985 0,20.74956 \
0,32 h -8 c 0,5.33333 0,10.66667 0,16 h -8 c 0,8 0,16 0,24 h -8 v -8 h -8 c 0,5.33333 \
0,10.66667 0,16 h 8 v 8 h 8 v 8 h -8 v 8 h -8 v 8 c 5.33333,0 10.66667,0 16,0 v 8 h 8 v \
-8 h 8 v -8 h -8 v -8 h 8 v -8 c 5.33333,0 10.66667,0 16,0 v 8 h -8 c 0,5.33333 \
0,10.66667 0,16 5.33333,0 10.66667,0 16,0 v -8 h 8 v -8 h -8 c 0,-16 0,-32 0,-48 h 8 v \
-8 h 8 v -8 h -8 -8 v 8 c -5.33333,0 -10.66667,0 -16,0 v -8 h 8 v -8 h -8 c 0,-8 0,-16 \
0,-24 h 8 v -8 -8 h -8 v 8 c -8,0 -16,0 -24,0 v -8 h -8 v 8 h -8 z m 8,-16 c 0,-5.333333 \
0,-10.666667 0,-16 h -8 c 0,5.333333 0,10.666667 0,16 z m 8,0 h 8 c 0,-8 0,-16 0,-24 h \
-8 c 0,8 0,16 0,24 z m 56,48 h 8 v 8 h 8 V 96 h -8 v 8 h -8 z m -8,64 h 8 v 8 c \
5.33333,0 10.66667,0 16,0 v -8 h -8 c 0,-5.33333 0,-10.66667 0,-16 h -8 v 8 h -8 z m \
-8,16 v 8 h 8 v -8 z m -16,0 h -8 v 8 h 8 z m -32,-88 v -8 h -8 v 8 z m -8,0 h -8 v 8 h \
8 z M 80,48 v -8 c -5.333333,0 -10.666667,0 -16,0 0,5.333333 0,10.666667 0,16 h 8 V 48 Z \
M 144,0 v 56 h 56 V 0 Z M 8,8 h 40 c 0,14.106822 0,26.62675 0,40 -14.106822,0 \
-26.62675,0 -40,0 z m 120,0 v 24 h 8 V 8 Z m 24,0 h 40 V 48 H 152 Z M 16,16 c 0,8 0,16 \
0,24 8,0 16,0 24,0 0,-8 0,-16 0,-24 -8,0 -16,0 -24,0 z m 144,0 v 24 h 24 V 16 Z M 0,64 c \
0,5.333333 0,10.666667 0,16 H 8 C 8,74.666667 8,69.333333 8,64 Z m 16,0 c 0,8.712801 \
0,15.440427 0,24 H 8 v 8 c 10.666667,0 21.333333,0 32,0 v 8 c 5.333333,0 10.666667,0 \
16,0 v -8 h -8 v -8 h -8 v -8 h 8 v -8 c -5.333333,0 -10.666667,0 -16,0 0,5.333333 \
0,10.666667 0,16 h -8 c 0,-8.054707 0,-16.875713 0,-24 z m 32,8 h 8 v 8 h -8 v 8 h 8 8 v \
8 8 h 8 c 0,-8 0,-16 0,-24 h -8 c 0,-5.333333 0,-10.666667 0,-16 -5.333333,0 \
-10.666667,0 -16,0 z m 16,32 h -8 v 8 h 8 z m -8,8 h -8 v 8 h 8 z m 0,8 v 8 h 8 c 0,8 \
0,16 0,24 h 8 c 0,-5.33333 0,-10.66667 0,-16 h 8 v -8 h -8 v -8 c -5.333333,0 \
-10.666667,0 -16,0 z m 24,8 h 8 v -8 h -8 z m 8,-8 h 8 v -8 h -8 z m 0,8 v 8 h 8 c \
0,5.33333 0,10.66667 0,16 -8,0 -16,0 -24,0 0,8 0,16 0,24 h 8 c 0,8 0,16 0,24 h 8 c \
0,-5.33333 0,-10.66667 0,-16 h 8 v -8 h -8 v -8 h -8 v -8 c 5.333333,0 10.666667,0 16,0 \
v 8 h 8 c 0,-13.33333 0,-26.66667 0,-40 -5.333333,0 -10.666667,0 -16,0 z m 16,40 v 8 h 8 \
v -8 z m -8,16 c 0,5.33333 0,10.66667 0,16 h 8 c 0,-5.33333 0,-10.66667 0,-16 z m -24,-8 \
h -8 v 8 h 8 z m 16,-40 h -8 v 8 h 8 z m -32,-8 h -8 -8 v 8 c 5.333333,0 10.666667,0 \
16,0 z m -16,0 c 0,-5.33333 0,-10.66667 0,-16 -8,0 -16,0 -24,0 v 8 h 8 v 8 h -8 v 8 c \
5.333333,0 10.666667,0 16,0 v -8 z m -24,0 v -8 c -5.333333,0 -10.6666667,0 -16,0 v 8 c \
5.3333333,0 10.666667,0 16,0 z M 8,96 H 0 c 0,5.33333 0,10.66667 0,16 H 8 C 8,106.66667 \
8,101.33333 8,96 Z M 176,64 v 8 h 8 v -8 z m 8,8 v 8 h 8 v 8 h 8 V 64 h -8 v 8 z m 0,8 h \
-8 v -8 h -8 c 0,8 0,16 0,24 h 8 v -8 h 8 z m 0,48 v 8 h 8 v -8 z m 8,8 v 8 8 h 8 v -16 \
z m -56,0 c 8,0 16,0 24,0 0,8 0,16 0,24 -8,0 -16,0 -24,0 0,-8 0,-16 0,-24 z M 0,144 v 56 \
c 18.666667,0 37.333333,0 56,0 0,-18.66667 0,-37.33333 0,-56 -18.666667,0 -37.333333,0 \
-56,0 z m 144,0 v 8 h 8 v -8 z M 8,152 c 13.333333,0 26.666667,0 40,0 0,13.33333 \
0,26.66667 0,40 -13.333333,0 -26.666667,0 -40,0 0,-13.33333 0,-26.66667 0,-40 z m 8,8 c \
0,8 0,16 0,24 8,0 16,0 24,0 0,-8 0,-16 0,-24 -8,0 -16,0 -24,0 z m 48,32 v 8 h 8 v -8 z m \
128,0 v 8 h 8 v -8 z
"""
