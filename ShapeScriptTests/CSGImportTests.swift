//
//  CSGImportTests.swift
//  ShapeScriptTests
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import Euclid
import XCTest

final class CSGImportTests: XCTestCase {
    private func mesh(_ source: String) throws -> Mesh {
        let geometry = try Geometry(csgString: source, isCancelled: { false })
        XCTAssertTrue(geometry.build { false })
        return geometry.merged()
    }

    func testCubeAndPrimitivePreservation() throws {
        let geometry = try Geometry(csgString: "cube(size = [2, 3, 4], center = false);", isCancelled: { false })
        XCTAssertEqual(geometry.children.first?.type, .cube)
        XCTAssertTrue(geometry.build { false })
        XCTAssertEqual(geometry.merged().bounds.min, .zero)
        XCTAssertEqual(geometry.merged().bounds.max, Vector(2, 3, 4))
        XCTAssertEqual(try mesh("cube(2, true);").signedVolume, 8, accuracy: 0.000001)
    }

    func testSphereAndTaperedCylinder() throws {
        let sphere = try mesh("sphere(d = 4, $fn = 16);")
        XCTAssertEqual(sphere.bounds.size.x, 4, accuracy: 0.000001)
        XCTAssertTrue(sphere.isWatertight)
        let cylinder = try mesh("cylinder(h = 4, r1 = 1, r2 = 0.5, center = true, $fn = 16);")
        XCTAssertEqual(cylinder.bounds.min.z, -2, accuracy: 0.000001)
        XCTAssertEqual(cylinder.bounds.max.z, 2, accuracy: 0.000001)
        XCTAssertEqual(cylinder.bounds.size.x, 2, accuracy: 0.000001)
        XCTAssertTrue(cylinder.isWatertight)
    }

    func testTransformsAndColours() throws {
        let result = try mesh("""
        color([1, 0, 0, 0.5]) {
            translate([1, 2, 3]) scale([2, 3, 4]) cube(1, true);
        }
        """)
        XCTAssertEqual(result.bounds.min, Vector(0, 0.5, 1))
        XCTAssertEqual(result.bounds.max, Vector(2, 3.5, 5))
        XCTAssertEqual(
            (result.polygons.first?.material as? Material)?.color,
            Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        )
    }

    func testRotationAndMirroring() throws {
        for transform in ["rotate([0, 0, 90])", "rotate(a = 90, v = [0, 0, 1])"] {
            let result = try mesh("\(transform) cube([2, 3, 4], true);")
            XCTAssertEqual(result.bounds.size.x, 3, accuracy: 0.000001)
            XCTAssertEqual(result.bounds.size.y, 2, accuracy: 0.000001)
        }
        let mirrored = try mesh("mirror([1, 0, 0]) cube([2, 3, 4]);")
        XCTAssertEqual(mirrored.bounds.min.x, -2, accuracy: 0.000001)
        XCTAssertEqual(mirrored.signedVolume, 24, accuracy: 0.000001)
        XCTAssertTrue(mirrored.isWatertight)
    }

    func testTransformPreservesExtrudedProfileColours() throws {
        let result =
            try mesh("translate([1,0,0]) linear_extrude(height=2) color([1,0,0,1]) polygon([[0,0],[1,0],[1,1],[0,1]]);")
        XCTAssertTrue(result.polygons.contains { polygon in
            (polygon.material as? Material)?.color == .red || polygon.vertices.contains { $0.color == .red }
        })
    }

    func testAffineMatrixIncludingShear() throws {
        let result = try mesh("multmatrix([[1,1,0,2],[0,1,0,3],[0,0,1,4],[0,0,0,1]]) cube(1);")
        XCTAssertEqual(result.bounds.min, Vector(2, 3, 4))
        XCTAssertEqual(result.bounds.max, Vector(4, 4, 5))
        XCTAssertEqual(result.signedVolume, 1, accuracy: 0.000001)
    }

    func testBooleanOperations() throws {
        let difference = try mesh("difference() { cube(2, true); cube(1, true); }")
        XCTAssertEqual(difference.signedVolume, 7, accuracy: 0.000001)
        let intersection = try mesh("intersection() { cube(2, true); cube(1, true); }")
        XCTAssertEqual(intersection.signedVolume, 1, accuracy: 0.000001)
        let union = try mesh("union() { cube(2, true); cube(1, true); }")
        XCTAssertEqual(union.signedVolume, 8, accuracy: 0.000001)
        let transformedCutter = try mesh("difference() { cube(2,true); translate([0.25,0,0]) cube(1,true); }")
        XCTAssertEqual(transformedCutter.signedVolume, 7, accuracy: 0.000001)
    }

    func testHullAndMinkowski() throws {
        let hull = try mesh("hull() { cube(1); translate([2,0,0]) cube(1); }")
        XCTAssertEqual(hull.signedVolume, 3, accuracy: 0.000001)
        let sum = try mesh("minkowski() { cube(1, true); cube(1, true); }")
        XCTAssertEqual(sum.signedVolume, 8, accuracy: 0.000001)
    }

    func testIntersectionOfRotatedBoxes() throws {
        let result = try mesh("""
        intersection() {
            cube([100, 20, 20], true);
            multmatrix([[0.46984631039, 0.88256411925, 0.01802831123, 0],
                        [-0.81379768134, 0.44096961053, -0.37852230637, 0],
                        [-0.34202014332, 0.16317591116, 0.92541657839, 0],
                        [0, 0, 0, 1]]) cube([100, 20, 20], true);
            multmatrix([[0.41721770627, 0.66835566162, -0.61581660836, 0],
                        [0.64245892818, -0.69617191219, -0.32029860173, 0],
                        [-0.64278760968, -0.26200263022, -0.71984631039, 0],
                        [0, 0, 0, 1]]) cube([100, 20, 20], true);
            multmatrix([[0.0190076282, -0.60192849838, 0.7983237394, 0],
                        [0.02926918072, 0.79846077351, 0.60133493846, 0],
                        [-0.99939082701, 0.01193633086, 0.03279479952, 0],
                        [0, 0, 0, 1]]) cube([100, 20, 20], true);
        }
        """)
        XCTAssertTrue(result.isWatertight)
        XCTAssertEqual(result.submeshes.count, 1)
        XCTAssertGreaterThan(result.signedVolume, 0)
    }

    func testLinearExtrusionAndClockwisePolygon() throws {
        for profile in ["square([2, 3]);", "polygon(points=[[0,0],[0,3],[2,3],[2,0]], paths=undef, convexity=1);"] {
            let result = try mesh("linear_extrude(height = 4) { \(profile) }")
            XCTAssertEqual(result.bounds.min, .zero)
            XCTAssertEqual(result.bounds.max, Vector(2, 3, 4))
            XCTAssertEqual(result.signedVolume, 24, accuracy: 0.000001)
        }
    }

    func testTransformedPolygonHolesSurviveExtrusion() throws {
        let result = try mesh("""
        linear_extrude(height = 2) translate([1,2,3]) polygon(
            points = [[0,0],[4,0],[4,4],[0,4],[1,1],[1,3],[3,3],[3,1]],
            paths = [[0,1,2,3],[4,5,6,7]]
        );
        """)
        XCTAssertEqual(result.signedVolume, 24, accuracy: 0.000001)
        XCTAssertEqual(result.bounds.min.z, 0, accuracy: 0.000001)
        XCTAssertTrue(result.isWatertight)
    }

    func testStraightExtrusionDefaultsToOneSection() throws {
        let expected = try mesh("linear_extrude(height=4, slices=1) square(1);")
        for parameters in ["", ", $fn=30", ", $fa=1, $fs=0.1", ", twist=0, $fn=30"] {
            let result = try mesh("linear_extrude(height=4\(parameters)) square(1);")
            XCTAssertEqual(result, expected, parameters)
            XCTAssertTrue(result.polygons.flatMap(\.vertices).allSatisfy {
                $0.position.z == 0 || $0.position.z == 4
            }, parameters)
        }
    }

    func testStraightExtrusionPreservesExplicitSlices() throws {
        let result = try mesh("linear_extrude(height=4, slices=4, $fn=30) square(1);")
        let heights = Set(result.polygons.flatMap(\.vertices).map(\.position.z))
        XCTAssertEqual(heights, [0, 1, 2, 3, 4])
        XCTAssertEqual(result.signedVolume, 4, accuracy: 0.000001)
        XCTAssertTrue(result.isWatertight)
    }

    func testTwistedExtrusionRetainsDefaultSections() throws {
        let result = try mesh("linear_extrude(height=4, twist=90, $fn=30) square(1);")
        let expected = try mesh("linear_extrude(height=4, twist=90, slices=30) square(1);")
        XCTAssertEqual(result, expected)
    }

    func testTwistUsesOpenSCADClockwiseConvention() throws {
        let result = try mesh("linear_extrude(height=4, twist=90, slices=4) translate([2,0,0]) square(1, true);")
        let top = result.polygons.flatMap(\.vertices).filter { abs($0.position.z - 4) < 0.000001 }
        XCTAssertFalse(top.isEmpty)
        XCTAssertTrue(top.allSatisfy { $0.position.y < -1 })
    }

    func testFullRevolution() throws {
        let result = try mesh("rotate_extrude($fn = 16, angle = 360) translate([2,0,0]) square([1,3]);")
        XCTAssertEqual(result.bounds.min.z, 0, accuracy: 0.000001)
        XCTAssertEqual(result.bounds.max.z, 3, accuracy: 0.000001)
        XCTAssertEqual(result.bounds.max.x, 3, accuracy: 0.000001)
        XCTAssertTrue(result.isWatertight)
    }

    func testMiteredOffsetMapsToPathInset() throws {
        let result = try mesh("linear_extrude(height=1) offset(delta=1, chamfer=false) square(2, true);")
        XCTAssertEqual(result.bounds.min.x, -2, accuracy: 0.000001)
        XCTAssertEqual(result.bounds.max.x, 2, accuracy: 0.000001)
        XCTAssertEqual(result.signedVolume, 16, accuracy: 0.000001)
    }

    func testPolyhedronAndIndexValidation() throws {
        let result =
            try mesh(
                "polyhedron(points = [[0,0,0],[1,0,0],[0,1,0],[0,0,1]], faces = [[0,1,2],[0,3,1],[0,2,3],[1,3,2]]);"
            )
        XCTAssertTrue(result.isWatertight)
        XCTAssertEqual(abs(result.signedVolume), 1 / 6, accuracy: 0.000001)
        XCTAssertThrowsError(try mesh("polyhedron([[0,0,0],[1,0,0],[0,1,0]], [[0,1,9]]);"))
    }

    func testCommentsScientificNotationAndEmptyInput() throws {
        XCTAssertEqual(try mesh("/* start */ cube(1e-1); // end").signedVolume, 0.001, accuracy: 0.000001)
        XCTAssertEqual(try mesh("// start\r\ncube(1);\r\n").signedVolume, 1, accuracy: 0.000001)
        XCTAssertTrue(try mesh("// empty").isEmpty)
    }

    func testBasicTextAndEscapes() throws {
        #if canImport(CoreText)
        let geometry = try Geometry(
            csgString: "text(\"Hi \\\"CSG\\\"\", size=2, font=\"Helvetica\", halign=\"left\", valign=\"baseline\");",
            isCancelled: { false }
        )
        XCTAssertNotNil(geometry.path)
        XCTAssertFalse(geometry.paths(pretransformed: true).isEmpty)
        let result = try mesh("linear_extrude(height=1) text(\"Hi\", font=\"Helvetica\");")
        XCTAssertFalse(result.isEmpty)
        #endif
    }

    func testUnsupportedOperationsAndOptionsHaveLocations() throws {
        for source in [
            "offset(r=1) circle(1);", "projection() cube(1);", "surface(file=\"a.dat\");",
            "import(file=\"a.stl\");", "resize([2,3,4]) cube(1);",
            "linear_extrude(height=2, scale=0.5) square(1);",
            "rotate_extrude(angle=90) square(1);", "cube(1, unknown=true);",
            "difference() { square(2); circle(1); }", "text(\"a\", halign=\"center\");",
        ] {
            XCTAssertThrowsError(try mesh("\n\(source)")) { error in
                XCTAssertNotNil(error as? CSGImportError)
                XCTAssertTrue(error.localizedDescription.contains("line 2"), error.localizedDescription)
            }
        }
    }

    func testMalformedInput() throws {
        for source in [
            "cube(1)",
            "cube(size=1,size=2);",
            "union() { cube(1);",
            "cube([1,2]);",
            "cube(1e999);",
            "/*",
            "text(\"unterminated)",
        ] {
            XCTAssertThrowsError(try mesh(source), source)
        }
        let deep = String(repeating: "group(){", count: 300) + "cube(1);" + String(repeating: "}", count: 300)
        XCTAssertThrowsError(try mesh(deep))
    }

    func testCancellation() {
        XCTAssertThrowsError(try Geometry(csgString: "cube(1);", isCancelled: { true })) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testTessellationLimits() {
        for source in [
            "sphere($fn=100000);",
            "circle($fn=1e20);",
            "linear_extrude(height=1,slices=100000) circle($fn=1000);",
        ] {
            XCTAssertThrowsError(try mesh(source))
        }
    }

    func testScriptImportAndErrorPropagation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("part.csg")
        try "cube([2,3,4], true);".write(to: url, atomically: true, encoding: .utf8)
        let scene = try evaluate(parse("import \"part.csg\""), delegate: TestDelegate(directory: directory))
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(scene.geometry.merged().signedVolume, 24, accuracy: 0.000001)
        try "color([1,0,0,1]) polygon([[0,0],[1,0],[1,1],[0,1]]);".write(to: url, atomically: true, encoding: .utf8)
        let extruded = try evaluate(parse("extrude import \"part.csg\""), delegate: TestDelegate(directory: directory))
        XCTAssertTrue(extruded.build { false })
        XCTAssertEqual(extruded.geometry.merged().signedVolume, 1, accuracy: 0.000001)
        XCTAssertTrue(extruded.geometry.merged().polygons.contains { ($0.material as? Material)?.color == .red })
        try "projection() cube(1);".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try evaluate(
            parse("import \"part.csg\""),
            delegate: TestDelegate(directory: directory)
        )) { error in
            XCTAssertTrue(ProgramError(error).hint?.contains("Unsupported CSG operation 'projection'") == true)
        }
    }
}
