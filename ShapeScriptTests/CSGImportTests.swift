//
//  CSGImportTests.swift
//  ShapeScriptTests
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import Euclid
import XCTest

#if canImport(CoreText)
import CoreText
#endif

final class CSGImportTests: XCTestCase {
    func test2DOperationsRetainTheirGeometryTrees() throws {
        let url = URL(fileURLWithPath: "/tmp/profile.csg")
        for (operation, type) in [
            ("union", GeometryType.union), ("difference", .difference),
            ("intersection", .intersection), ("hull", .hull([])), ("minkowski", .minkowski),
        ] {
            let geometry = try Geometry(csgString: """
            translate([3,4,5]) {
                \(operation)() {
                    square(4,true);
                    square(2,true);
                }
            }
            """, at: url, isCancelled: { false })
            func descendants(_ geometry: Geometry) -> [Geometry] {
                [geometry] + geometry.children.flatMap(descendants)
            }
            let container = try XCTUnwrap(descendants(geometry).first {
                $0.type == type && $0.children.count == 2
            }, operation)
            XCTAssertNotNil(container.path())
            XCTAssertTrue(container.children.allSatisfy { $0.path() != nil || !$0.children.isEmpty })
            XCTAssertEqual(container.sourceLocation, SourceLocation(at: 2, in: url))
            XCTAssertEqual(try XCTUnwrap(geometry.path()).bounds.center, [3, 4, 0])
        }
    }

    func testAffine2DOperationsRetainTreesAndMatchTransformedProfiles() throws {
        for operation in ["union", "difference", "intersection", "hull", "minkowski"] {
            let source = """
            translate([2,3,0]) \(operation)() {
                square(4,true);
                translate([1,0,0]) square(2,true);
            }
            """
            let original = try Geometry(csgString: source, isCancelled: { false })
            let profile = try XCTUnwrap(original.path())
            let transformed = try Geometry(csgString: """
            multmatrix([[-1,0.5,0,7],[0,1,0,11],[0,0,1,0],[0,0,0,1]]) {
                \(source)
            }
            """, isCancelled: { false })
            let result = try XCTUnwrap(transformed.path(), operation)
            let expected = Path(subpaths: profile.subpaths.map { subpath in
                Path(subpath.points.map { point in
                    var point = point
                    let p = point.position
                    point.position = [-p.x + 0.5 * p.y + 7, p.y + 11, p.z]
                    return point
                })
            })
            XCTAssertLessThan((result.bounds.min - expected.bounds.min).length, 1e-8, operation)
            XCTAssertLessThan((result.bounds.max - expected.bounds.max).length, 1e-8, operation)
            XCTAssertEqual(
                Mesh.fill(result, faces: .front).surfaceArea,
                Mesh.fill(expected, faces: .front).surfaceArea,
                accuracy: 1e-8, operation
            )
            func operations(_ geometry: Geometry) -> [Geometry] {
                (geometry.children.count == 2 ? [geometry] : []) + geometry.children.flatMap(operations)
            }
            XCTAssertFalse(operations(transformed).isEmpty, operation)
        }
    }

    func testImportedCSGPreservesDefinitionLocations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("part.csg")
        let source = """
        union() {
            cube(1);
            multmatrix([[1,1,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]) {
                cube(2);
            }
        }
        """
        try source.write(to: fileURL, atomically: true, encoding: .utf8)
        let scene = try evaluate(parse("import \"part.csg\""), delegate: TestDelegate(directory: directory))
        XCTAssertTrue(scene.build { false })
        func descendants(_ geometry: Geometry) -> [Geometry] {
            [geometry] + geometry.children.flatMap(descendants)
        }
        let geometries = descendants(scene.geometry)
        let cube = try XCTUnwrap(geometries.first { $0.type == .cube })
        XCTAssertEqual(cube.sourceLocation, SourceLocation(at: 2, in: fileURL))
        let sheared = try XCTUnwrap(geometries.first { if case .mesh = $0.type { return true }; return false })
        // A baked mesh is defined by the matrix operation that created it.
        XCTAssertEqual(sheared.sourceLocation, SourceLocation(at: 3, in: fileURL))
        XCTAssertTrue(geometries.dropFirst().allSatisfy { $0.sourceLocation?.file == fileURL })
        let directlyOpened = try Scene(csgString: source, at: fileURL, isCancelled: { false })
        XCTAssertEqual(
            descendants(directlyOpened.geometry).first { $0.type == .cube }?.sourceLocation,
            SourceLocation(at: 2, in: fileURL)
        )
        let tagged = try Scene(
            csgString: source.replacingOccurrences(of: "cube(2)", with: "#cube(2)"),
            at: fileURL,
            isCancelled: { false }
        )
        let taggedMesh = try XCTUnwrap(descendants(tagged.geometry).first {
            if case .mesh = $0.type { return true }
            return false
        })
        XCTAssertEqual(taggedMesh.sourceLocation, SourceLocation(at: 4, in: fileURL))
    }

    func testUnknownSymbolsAreErrorsWithLocations() {
        for source in [
            "cubee(1);", "hullz() { cube(1); }", "cube(szie=2);",
            "cube(1, false, 3);", "text(\"Hi\", halgin=\"center\");",
            "text(\"Hi\", future_option=true);", "projection(cutt=true) cube(1);",
            "surface(flie=\"a.dat\");", "import(flie=\"a.stl\");", "resize(newsz=[1,2,3]) cube(1);",
            "roof(metod=\"straight\") square(1);",
        ] {
            XCTAssertThrowsError(try Scene(csgString: "\n\(source)", isCancelled: { false })) { error in
                let error = error as? CSGImportError
                XCTAssertTrue(error?.message.hasPrefix("Unknown CSG") == true, source)
                XCTAssertEqual(error?.line, 2, source)
                XCTAssertEqual(error?.column, 1, source)
            }
        }
    }

    func testInvalidUnsupportedFeatureValuesAreErrors() {
        for source in [
            "text(\"Hi\", halign=\"cenetr\");", "text(\"Hi\", valign=\"botom\");",
            "text(\"Hi\", direction=\"left\");", "projection(cut=2) cube(1);",
            "resize([1,2]) cube(1);", "resize([-1,2,3]) cube(1);",
            "resize([1,2,3], auto=\"yes\") cube(1);", "resize([1,2,3], auto=[1,2,0]) cube(1);",
            "surface(file=2);", "import(file=\"a.stl\", origin=[1,2,3]);",
            "roof(method=2) square(1);",
        ] {
            XCTAssertThrowsError(try Scene(csgString: source, isCancelled: { false }), source)
        }
    }

    func testDefaultTextAlignmentUsesLeftBaseline() throws {
        let scene = try Scene(
            csgString: "text(\"Hi\", halign=\"default\", valign=\"default\");",
            isCancelled: { false }
        )
        let baseline = try Scene(csgString: "text(\"Hi\");", isCancelled: { false })
        XCTAssertEqual(scene.geometry, baseline.geometry)
        XCTAssertEqual(scene.warnings, baseline.warnings)
    }

    func testUnsupportedLeavesAreSkippedAndWrappersPreserveChildren() throws {
        let scene = try Scene(
            csgString: "union() { roof() cube(2,true); surface(file=\"missing.dat\"); }",
            isCancelled: { false }
        )
        XCTAssertEqual(scene.warnings.count, 2)
        XCTAssertTrue(scene.warnings.contains { $0.contains("Cannot load surface 'missing.dat'") })
        XCTAssertTrue(scene.warnings.contains { $0.contains("Unsupported CSG operation 'roof'") })
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(scene.geometry.merged().signedVolume, 8, accuracy: 1e-8)
    }

    func testSurfaceLoadsHeightDataRelativeToTheCSGDocument() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "0 1\n2 3\n".write(to: directory.appendingPathComponent("height.dat"), atomically: true, encoding: .utf8)
        let url = directory.appendingPathComponent("part.csg")
        let source = #"surface(file="height.dat", center=true, invert=false, timestamp=1795701839);"#
        try source.write(to: url, atomically: true, encoding: .utf8)
        let scene = try Scene(csgString: source, at: url, isCancelled: { false })
        XCTAssertTrue(scene.warnings.isEmpty)
        XCTAssertTrue(scene.build { false })
        let mesh = scene.geometry.merged()
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertEqual(mesh.bounds, Bounds([-0.5, -0.5, -1], [0.5, 0.5, 3]))
        XCTAssertEqual(mesh.signedVolume, 2.5, accuracy: 1e-8)
    }

    func testRaggedDATSurfacesUseZeroPaddingAndExplicitMinimum() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("height.dat")
        for (heights, bottom, volume) in [("2 3\n4 5 6\n", 0.0, 7.0), ("0.5 2\n1 1.5 4\n", -0.5, 4.125)] {
            try heights.write(to: url, atomically: true, encoding: .utf8)
            let surface = try mesh("surface(file=\"\(url.path)\", invert=true);")
            XCTAssertTrue(surface.isWatertight)
            XCTAssertEqual(surface.bounds.min.z, bottom)
            XCTAssertEqual(surface.signedVolume, volume, accuracy: 1e-8)
        }
    }

    #if canImport(ImageIO)

    func testPNGSurfaceRetains16BitRGBAndIgnoresAlpha() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("height.png")
        let data = try XCTUnwrap(Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACEAYAAAAiJtFnAAAAK0lEQVR4nGOY48D4hWMGAwOjDlPE3xcM/xkkU0oNGFIaGGoZGLYw6vz/DwCzwgs/jqXaigAAAABJRU5ErkJggg=="
        ))
        try data.write(to: url)
        let surface = try mesh("surface(file=\"\(url.path)\");")
        let heights = [Vector(6500, 30000, 100), [32000, 180, 300], [40000, 500, 2200], [300, 600, 65000]]
            .map { $0.dot([0.2126, 0.7152, 0.0722]) * 100 / 65535 }
        XCTAssertTrue(surface.isWatertight)
        XCTAssertEqual(surface.bounds.min.z, try XCTUnwrap(heights.min()) - 1, accuracy: 1e-8)
        let points = surface.polygons.flatMap(\.vertices).map(\.position)
        for (i, height) in heights.enumerated() {
            let expected = Vector(Double(i % 2), Double(i / 2), height)
            XCTAssertTrue(points.contains { ($0 - expected).length < 1e-8 })
        }
    }

    func testInvertedPNGSurfaceKeepsNegativeHeights() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data =
            try XCTUnwrap(
                Data(
                    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAAAAABX3VL4AAAADklEQVR4nGNgsGdo+A8AAwEBv5Ve/PAAAAAASUVORK5CYII="
                )
            )
        let url = directory.appendingPathComponent("height.png")
        try data.write(to: url)
        let mesh = try mesh("surface(file=\"\(url.path)\", center=true, invert=true);")
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertEqual(mesh.bounds, Bounds([-0.5, -0.5, -101], [0.5, 0.5, 0]))
        XCTAssertEqual(mesh.signedVolume, 101 - 446.0 * 25 / 255, accuracy: 1e-8)
    }

    #endif

    func testUnsupportedRoofWarnsAndPreservesChildren() throws {
        let expected = try Scene(csgString: "group() { square(2); }", isCancelled: { false })
        for arguments in [
            "", "method=\"straight\"", "\"voronoi\"",
            "method=\"voronoi\", $fa=90, $fs=0, $fn=4, convexity=1",
        ] {
            let scene = try Scene(csgString: "roof(\(arguments)) { square(2); }", isCancelled: { false })
            XCTAssertEqual(scene.warnings.count, 1)
            XCTAssertEqual(
                scene.warnings.first,
                "Unsupported CSG operation 'roof' on line 1."
            )
            XCTAssertEqual(scene.geometry, expected.geometry)
            XCTAssertTrue(scene.build { false })
        }
        let empty = try Scene(csgString: "roof(); cube(1);", isCancelled: { false })
        XCTAssertTrue(empty.warnings.contains { $0.contains("Unsupported CSG operation 'roof'") })
        XCTAssertTrue(empty.build { false })
        XCTAssertEqual(empty.geometry.merged().signedVolume, 1, accuracy: 1e-8)
    }

    func testVectorLinearExtrusionKeepsItsProfileInXY() throws {
        for (arguments, min, max) in [
            ("height=5, v=[0.6,0,0.8], center=true, $fn=0, $fa=12, $fs=2", Vector(-1.5, 0, -2), Vector(3.5, 2, 2)),
            ("v=[3,0,4]", .zero, Vector(5, 2, 4)),
        ] {
            let result = try mesh("linear_extrude(\(arguments)) square(2);")
            XCTAssertTrue(result.isWatertight)
            XCTAssertEqual(result.signedVolume, 16, accuracy: 1e-8)
            XCTAssertLessThan((result.bounds.min - min).length, 1e-8)
            XCTAssertLessThan((result.bounds.max - max).length, 1e-8)
            XCTAssertTrue(result.polygons.allSatisfy { polygon in
                polygon.vertices.allSatisfy { ($0.normal - polygon.plane.normal).length < 1e-8 }
            })
        }
        XCTAssertTrue(try mesh("linear_extrude(v=[1,0,0]) square(2);").isEmpty)
    }

    func testVectorLinearExtrusionSupportsTwistAndTaper() throws {
        let result = try mesh("""
        linear_extrude(height=13, v=[0.230769,-0.307692,0.923077], center=true, twist=30,
                       slices=3, segments=0, scale=[0.5,1.5]) square(size=[2,1], center=false);
        """)
        let positions = Set(result.polygons.flatMap(\.vertices).map(\.position))
        XCTAssertTrue(result.isWatertight)
        XCTAssertEqual(positions.count, 16)
        XCTAssertEqual(Set(positions.map { Int($0.z.rounded()) }), [-6, -2, 2, 6])
        XCTAssertTrue(positions.contains { ($0 - Vector(-1.5, 2, -6)).length < 1e-5 })
        XCTAssertTrue(positions.contains { ($0 - Vector(2.3660254, -3.5, 6)).length < 1e-5 })
    }

    func testPartialRotateExtrudeSpansTheExportedArc() throws {
        let partial = try Scene(
            csgString: "rotate_extrude(angle=100, start=30, $fn=16) translate([2,0,0]) square(1);",
            isCancelled: { false }
        )
        XCTAssertTrue(partial.warnings.isEmpty)
        XCTAssertTrue(partial.build { false })
        let mesh = partial.geometry.merged()
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertGreaterThan(mesh.signedVolume, 0)
        let positions = mesh.polygons.flatMap(\.vertices).map(\.position)
        let angles = Set(positions.filter { hypot($0.x, $0.y) > 2.9 }.map {
            Int((atan2($0.y, $0.x) * 180 / .pi).rounded())
        })
        XCTAssertEqual(angles, [30, 50, 70, 90, 110, 130])
    }

    func testPartialRotateExtrudeSupportsNegativeSweepsOnEitherSideOfTheAxis() throws {
        for (offset, side) in [(2, 1.0), (-3, -1.0)] {
            let result = try mesh("rotate_extrude(angle=-10, $fn=16) translate([\(offset),0,0]) square(1);")
            XCTAssertTrue(result.isWatertight)
            XCTAssertEqual(result.signedVolume, 2.5 * sin(Angle.degrees(10)), accuracy: 1e-8)
            let positions = result.polygons.flatMap(\.vertices).map(\.position)
            XCTAssertTrue(positions.contains { ($0 - Vector(3 * side, 0, 0)).length < 1e-8 })
            XCTAssertTrue(positions.allSatisfy { $0.x * side > 0 && $0.y * side <= 1e-8 })
        }
        XCTAssertTrue(try mesh("rotate_extrude(angle=0) square(1);").isEmpty)
    }

    func testFullRotateExtrudeHonorsStartWithAnOddSegmentCount() throws {
        let profile = "translate([2,0,0]) square(1);"
        let legacy = try mesh("rotate_extrude($fn=3) \(profile)")
        let explicit = try mesh("rotate_extrude(angle=360, start=0, $fn=3) \(profile)")
        XCTAssertEqual(legacy.bounds.min.x, -3, accuracy: 1e-8)
        XCTAssertEqual(explicit.bounds.max.x, 3, accuracy: 1e-8)
        XCTAssertEqual(explicit.bounds.min.x, -1.5, accuracy: 1e-8)
        XCTAssertEqual(legacy.signedVolume, explicit.signedVolume, accuracy: 1e-8)
        XCTAssertEqual(try mesh("rotate_extrude(angle=360, $fn=3) \(profile)"), explicit)
    }

    func testFractionalRotateExtrudeUsesCurrentDefaultsForOldExports() throws {
        let profile = "translate([2,0,0]) square(1);"
        let legacy = try mesh("rotate_extrude(angle=150, convexity=2, $fn=7.5) \(profile)")
        let current = try mesh("rotate_extrude(angle=150, start=0, convexity=2, $fn=7.5) \(profile)")
        XCTAssertTrue(legacy.isWatertight)
        XCTAssertTrue(current.isWatertight)
        XCTAssertEqual(Set(current.polygons.flatMap(\.vertices).map(\.position)).count, 20)
        XCTAssertEqual(legacy, current)
    }

    func testRoundedOffsetTakesPrecedenceOverChamferedDelta() throws {
        let rounded = try mesh("linear_extrude(1) offset(r=1, delta=3, chamfer=true, $fn=7.5) square(2,true);")
        let defaultRadius = try mesh("linear_extrude(1) offset($fn=8) square(2,true);")
        XCTAssertEqual(rounded, defaultRadius)
        XCTAssertTrue(rounded.isWatertight)
        XCTAssertEqual(rounded.bounds, Bounds([-2, -2, 0], [2, 2, 1]))
        XCTAssertEqual(rounded.signedVolume, 12 + 2 * sqrt(2), accuracy: 1e-8)
    }

    func testUnsupportedMatrixOptionsWarnWithoutLosingOtherGeometry() throws {
        let projective = try Scene(
            csgString: "multmatrix([[1,0,0,2],[0,1,0,0],[0,0,1,0],[0,0,0.1,1]]) cube(1);",
            isCancelled: { false }
        )
        XCTAssertTrue(projective.warnings.contains { $0.contains("Projective") })
        XCTAssertTrue(projective.build { false })
        XCTAssertEqual(projective.geometry.merged().bounds, Bounds([2, 0, 0], [3, 1, 1]))
        let singular = try Scene(csgString: "cube(1); scale([0,1,1]) cube(4);", isCancelled: { false })
        XCTAssertTrue(singular.warnings.contains { $0.contains("Singular") })
        XCTAssertTrue(singular.build { false })
        XCTAssertEqual(singular.geometry.merged().signedVolume, 1, accuracy: 1e-8)
    }

    func testTransformsOfEmptyGeometryDoNotOverflow() throws {
        for child in [
            "group() {}",
            "linear_extrude(height=100) {}",
            "rotate_extrude() {}",
        ] {
            let scene = try Scene(
                csgString: """
                rotate([90,0,0])
                multmatrix([[1,0,0,0],[0,1,0,0],[0,0,1,-50],[0,0,0,1]]) {
                    \(child)
                    cube(1);
                }
                """,
                isCancelled: { false }
            )
            XCTAssertTrue(scene.build { false }, child)
            let result = scene.geometry.merged()
            XCTAssertEqual(result.signedVolume, 1, accuracy: 1e-8, child)
            XCTAssertEqual(result.bounds.min.y, 49, accuracy: 1e-8, child)
            XCTAssertEqual(result.bounds.max.y, 50, accuracy: 1e-8, child)
        }
    }

    func testPrimitiveChildrenAreIgnoredWithWarnings() throws {
        let scene = try Scene(csgString: "cube(size=2) { sphere(1); }", isCancelled: { false })
        XCTAssertEqual(scene.warnings.count, 1)
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(scene.geometry.merged().signedVolume, 8, accuracy: 1e-8)
        XCTAssertThrowsError(try Scene(csgString: "cube(1,size=2);", isCancelled: { false }))
    }

    func testMixedDimensionsAndUnsupportedExtrusionChildrenWarn() throws {
        let mixed = try Scene(csgString: "translate([2,0,0]) group() { cube(1); square(1); }", isCancelled: { false })
        XCTAssertFalse(mixed.warnings.isEmpty)
        XCTAssertTrue(mixed.build { false })
        XCTAssertEqual(mixed.geometry.merged().signedVolume, 1, accuracy: 1e-8)
        let extruded = try Scene(
            csgString: "linear_extrude(height=1) group() { square(1); surface(file=\"missing\"); }",
            isCancelled: { false }
        )
        XCTAssertTrue(extruded.build { false })
        XCTAssertEqual(extruded.geometry.merged().signedVolume, 1, accuracy: 1e-8)
        let incompatible = try Scene(
            csgString: "cube(1); linear_extrude(height=1) roof() cube(1);",
            isCancelled: { false }
        )
        XCTAssertEqual(incompatible.warnings.count, 2)
        XCTAssertTrue(incompatible.build { false })
        XCTAssertEqual(incompatible.geometry.merged().signedVolume, 1, accuracy: 1e-8)
    }

    #if canImport(CoreText)
    func testTextSizeUsesOpenSCADFontScale() throws {
        let scene = try Scene(
            csgString: "text(\"Open\", size=72, font=\"Helvetica-Bold\", $fn=32);",
            isCancelled: { false }
        )
        let geometry = try XCTUnwrap(scene.children.first)
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 100, nil)
        let expected = Bounds([Path].text(
            NSAttributedString(string: "Open", attributes: [.font: font]),
            detail: 4, isCancelled: { false }
        ))
        let actual = Bounds(geometry.paths(pretransformed: true))
        XCTAssertEqual(actual.min.x, expected.min.x, accuracy: 1e-6)
        XCTAssertEqual(actual.min.y, expected.min.y, accuracy: 1e-6)
        XCTAssertEqual(actual.max.x, expected.max.x, accuracy: 1e-6)
        XCTAssertEqual(actual.max.y, expected.max.y, accuracy: 1e-6)
    }

    func testTextLanguageUsesSystemShaping() throws {
        let source = "text(\"Hi\", font=\"Helvetica\", halign=\"center\", spacing=2, language=\"fr\");"
        let scene = try Scene(csgString: source, isCancelled: { false })
        XCTAssertTrue(scene.warnings.isEmpty)
        let fallback = try Scene(
            csgString: "text(\"Hi\", font=\"Helvetica\", halign=\"center\", spacing=2);",
            isCancelled: { false }
        )
        XCTAssertEqual(scene.geometry, fallback.geometry)
        XCTAssertTrue(fallback.warnings.isEmpty)
    }

    func testTextScriptSelectsLocalizedGlyphs() throws {
        let simplified = try Scene(
            csgString: #"text("骨", font="Helvetica", script="hans");"#, isCancelled: { false }
        )
        let traditional = try Scene(
            csgString: #"text("骨", font="Helvetica", language="zh-Hans", script="Hant");"#, isCancelled: { false }
        )
        let languageOnly = try Scene(
            csgString: #"text("骨", font="Helvetica", language="zh-Hant");"#, isCancelled: { false }
        )
        XCTAssertTrue(simplified.warnings.isEmpty)
        XCTAssertTrue(traditional.warnings.isEmpty)
        XCTAssertNotEqual(simplified.geometry, traditional.geometry)
        XCTAssertEqual(traditional.geometry, languageOnly.geometry)
    }

    func testTextScriptWarnsWhenCoreTextCannotForceShaping() throws {
        let scene = try Scene(
            csgString: #"text("سلام", font="Arial", direction="rtl", language="ar", script="Latn");"#,
            isCancelled: { false }
        )
        XCTAssertEqual(
            scene.warnings,
            ["Characters outside script 'Latn' keep their original writing system on line 1."]
        )
        XCTAssertFalse(scene.geometry.paths(pretransformed: true).isEmpty)
    }

    func testTextEmSizeAndVerticalWritingDirection() throws {
        let em = try mesh(#"linear_extrude(1) text("H", font="Helvetica", size=99, em=10);"#)
        let scaled = try mesh(#"linear_extrude(1) text("H", font="Helvetica", size=7.2);"#)
        XCTAssertEqual(em, scaled)
        let down = try mesh(#"linear_extrude(1) text("HHH", font="Helvetica", direction="ttb");"#)
        let up = try mesh(#"linear_extrude(1) text("HHH", font="Helvetica", direction="btt");"#)
        XCTAssertLessThan(down.bounds.min.y, 0)
        XCTAssertGreaterThan(up.bounds.max.y, down.bounds.max.y)
        XCTAssertEqual(down.bounds.size.y, up.bounds.size.y, accuracy: 1e-8)
    }

    func testTextAlignment() throws {
        let font = CTFontCreateWithName("Helvetica" as CFString, 1, nil)
        // Include whitespace, side bearings and descenders to distinguish advances
        // from visible bounds and glyph bounds from nominal font metrics.
        for text in ["Hi", "jgy", "  Hi  "] {
            let attributedString = NSAttributedString(string: text, attributes: [.font: font])
            let line = CTLineCreateWithAttributedString(attributedString)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let original = TextPath(
                text: [TextValue(string: text, font: "Helvetica")],
                wrapWidth: nil,
                detail: 4,
                isCancelled: { false }
            ).paths
            for (halign, x) in [("left", 0.0), ("center", -width / 2), ("right", -width)] {
                for (valign, y) in [
                    ("baseline", 0.0), ("top", -Double(bounds.maxY)),
                    ("center", -Double(bounds.midY)), ("bottom", -Double(bounds.minY)),
                ] {
                    let scene = try Scene(
                        csgString: """
                        text("\(text)", size=3, font="Helvetica", $fn=32, halign="\(halign)", valign="\(valign)");
                        """,
                        isCancelled: { false }
                    )
                    XCTAssertTrue(scene.warnings.isEmpty)
                    let geometry = try XCTUnwrap(scene.children.first)
                    let actual = Bounds(geometry.paths(pretransformed: true))
                    let expected = Bounds(original.translated(by: [x, y, 0]).scaled(by: 3 * 100.0 / 72))
                    XCTAssertEqual(actual.min.x, expected.min.x, accuracy: 1e-8)
                    XCTAssertEqual(actual.min.y, expected.min.y, accuracy: 1e-8)
                    XCTAssertEqual(actual.max.x, expected.max.x, accuracy: 1e-8)
                    XCTAssertEqual(actual.max.y, expected.max.y, accuracy: 1e-8)
                }
            }
        }
    }

    func testTextSpacingPreservesGlyphsAndUsesSpacedAdvanceForAlignment() throws {
        let font = CTFontCreateWithName("Helvetica" as CFString, 1, nil)
        func width(_ text: String) -> Double {
            CTLineGetTypographicBounds(CTLineCreateWithAttributedString(
                NSAttributedString(string: text, attributes: [.font: font])
            ), nil, nil, nil)
        }
        let glyph = Bounds(TextPath(
            text: [TextValue(string: "H", font: "Helvetica")],
            wrapWidth: nil, detail: 4, isCancelled: { false }
        ).paths)
        for spacing in [-1.0, 0, 0.5, 1, 2] {
            for (alignment, factor) in [("left", 0.0), ("center", -0.5), ("right", -1)] {
                let scene = try Scene(
                    csgString: """
                    text("H H ", font="Helvetica", size=3, spacing=\(spacing), halign="\(alignment)", $fn=32);
                    """,
                    isCancelled: { false }
                )
                XCTAssertTrue(scene.warnings.isEmpty)
                let geometry = try XCTUnwrap(scene.children.first)
                // Inspect the text operand, before the implicit root union merges overlapping glyphs.
                let textGeometry = try XCTUnwrap(geometry.children.first)
                let paths = textGeometry.paths(pretransformed: true).flatMap(\.subpaths)
                XCTAssertEqual(paths.count, 2)
                for (path, prefix) in zip(paths, ["", "H "]) {
                    let offset = (width(prefix) + width("H H ") * factor) * spacing
                    let bounds = path.bounds
                    XCTAssertEqual(bounds.min.x, (glyph.min.x + offset) * (3 * 100.0 / 72), accuracy: 1e-8)
                    XCTAssertEqual(bounds.max.x, (glyph.max.x + offset) * (3 * 100.0 / 72), accuracy: 1e-8)
                    XCTAssertEqual(bounds.min.y, glyph.min.y * (3 * 100.0 / 72), accuracy: 1e-8)
                    XCTAssertEqual(bounds.max.y, glyph.max.y * (3 * 100.0 / 72), accuracy: 1e-8)
                }
            }
        }
    }

    func testEmptyAlignedText() throws {
        for text in ["", "   "] {
            let scene = try Scene(
                csgString: "text(\"\(text)\", font=\"Helvetica\", halign=\"center\", valign=\"center\", spacing=2);",
                isCancelled: { false }
            )
            XCTAssertTrue(scene.warnings.isEmpty)
            let geometry = try XCTUnwrap(scene.children.first)
            XCTAssertTrue(geometry.paths(pretransformed: true).allSatisfy(\.isEmpty))
        }
    }

    func testFontStylesSelectMatchingFacesAndPreserveAlignment() throws {
        for (style, face) in [
            ("Regular", "Helvetica"), ("bold", "Helvetica-Bold"),
            ("Italic", "Helvetica-Oblique"), ("Oblique", "Helvetica-Oblique"),
            ("Bold Italic", "Helvetica-BoldOblique"), ("Bold Oblique", "Helvetica-BoldOblique"),
        ] {
            let source = "text(\"Style\", size=3, font=\"Helvetica:style=\(style)\", halign=\"center\", valign=\"top\");"
            let scene = try Scene(csgString: source, isCancelled: { false })
            let expected = try Scene(
                csgString: source.replacingOccurrences(of: "Helvetica:style=\(style)", with: face),
                isCancelled: { false }
            )
            XCTAssertTrue(scene.warnings.isEmpty, style)
            XCTAssertEqual(scene.geometry, expected.geometry, style)
        }
    }

    func testNamedFontStyleSelectsInstalledFace() throws {
        let scene = try Scene(
            csgString: "text(\"Style\", font=\"Helvetica Neue:style=Light\");",
            isCancelled: { false }
        )
        let expected = try Scene(csgString: "text(\"Style\", font=\"HelveticaNeue-Light\");", isCancelled: { false })
        XCTAssertTrue(scene.warnings.isEmpty)
        XCTAssertEqual(scene.geometry, expected.geometry)
    }

    func testFontStyleAppliesToFallbackFamily() throws {
        let regular = try Scene(csgString: "text(\"Style\", font=\"MissingCSGFontFamily\");", isCancelled: { false })
        let bold = try Scene(
            csgString: "text(\"Style\", font=\"MissingCSGFontFamily:style=Bold\");",
            isCancelled: { false }
        )
        XCTAssertEqual(regular.warnings, ["Unknown font 'MissingCSGFontFamily' on line 1."])
        XCTAssertEqual(bold.warnings, regular.warnings)
        XCTAssertNotEqual(regular.geometry, bold.geometry)
        let defaultFamily = try Scene(csgString: "text(\"Style\", font=\":style=Bold\");", isCancelled: { false })
        let explicitFamily = try Scene(
            csgString: "text(\"Style\", font=\"Liberation Sans:style=Bold\");",
            isCancelled: { false }
        )
        XCTAssertEqual(defaultFamily.warnings, explicitFamily.warnings)
        XCTAssertEqual(defaultFamily.geometry, explicitFamily.geometry)
    }

    func testMissingFontWarningsRetainCSGSourceLocation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("labels.csg")
        let source = "\ntext(\"Label\", font=\"MissingCSGFontFamily:style=Bold\");"
        try source.write(to: url, atomically: true, encoding: .utf8)
        let direct = try Scene(csgString: source, at: url, isCancelled: { false })
        XCTAssertEqual(direct.warnings, ["Unknown font 'MissingCSGFontFamily' on line 2."])
        let root = directory.appendingPathComponent("main.csg")
        let importedSource = "import(\"labels.csg\");"
        try importedSource.write(to: root, atomically: true, encoding: .utf8)
        let imported = try Scene(csgString: importedSource, at: root, isCancelled: { false })
        XCTAssertEqual(imported.warnings, ["labels.csg: Unknown font 'MissingCSGFontFamily' on line 2."])
        XCTAssertTrue(imported.build { false })
    }

    func testInstalledPostScriptFontNamesDoNotWarn() throws {
        for font in ["Helvetica-Bold", "HelveticaNeue-Light"] {
            let scene = try Scene(csgString: "text(\"Hi\", font=\"\(font)\");", isCancelled: { false })
            XCTAssertTrue(scene.warnings.isEmpty, font)
        }
    }

    func testUnsupportedFontStyleWarnsAndUsesBaseFont() throws {
        let scene = try Scene(
            csgString: "text(\"Hi\", font=\"Helvetica:style=MissingCSGStyle\");",
            isCancelled: { false }
        )
        XCTAssertEqual(scene.warnings.count, 1)
        XCTAssertTrue(scene.warnings[0].contains("Unsupported OpenSCAD font style"))
        let fallback = try Scene(csgString: "text(\"Hi\", font=\"Helvetica\");", isCancelled: { false })
        XCTAssertEqual(scene.geometry, fallback.geometry)
    }

    func testUnsupportedFontDescriptorsDoNotDiscardSupportedStyle() throws {
        let scene = try Scene(csgString: "text(\"Hi\", font=\"Helvetica:style=Bold:lang=fr\");", isCancelled: { false })
        XCTAssertEqual(scene.warnings.count, 1)
        XCTAssertTrue(scene.warnings[0].contains("lang=fr"))
        let expected = try Scene(csgString: "text(\"Hi\", font=\"Helvetica-Bold\");", isCancelled: { false })
        XCTAssertEqual(scene.geometry, expected.geometry)
    }
    #endif

    func testStringColorsMatchShapeScript() throws {
        for name in [
            "red",
            "GREEN",
            "lime",
            "RebeccaPurple",
            "cornflowerblue",
            "grey",
            "transparent",
            "#369",
            "#12345678",
        ] {
            guard case let .color(expected)? = Value.string(name).as(.color) else {
                return XCTFail("Expected a color for \(name)")
            }
            for alpha in [Double?.none, 0.25] {
                let argument = alpha.map { ", alpha=\($0)" } ?? ""
                let source = "color([1,0,0]) color(\"\(name)\"\(argument)) cube(1);"
                let scene = try Scene(csgString: source, isCancelled: { false })
                XCTAssertTrue(scene.warnings.isEmpty, name)
                XCTAssertTrue(scene.build { false })
                let polygons = scene.geometry.merged().polygons
                XCTAssertFalse(polygons.isEmpty)
                let color = alpha.map { expected.withAlphaComponent($0) } ?? expected
                XCTAssertTrue(polygons.allSatisfy { ($0.material as? Material)?.color == color }, name)
            }
        }
    }

    func testNumericAndHexMidtonesUseTheSameEncodedComponents() throws {
        for value in ["[0.5019607843137255, 0.25098039215686274, 0.7529411764705882, 0.4]", "\"#8040c066\""] {
            let scene = try Scene(csgString: "color(\(value)) cube(1);", isCancelled: { false })
            XCTAssertTrue(scene.build { false })
            let expected = Color(red: 128.0 / 255, green: 64.0 / 255, blue: 192.0 / 255, alpha: 0.4)
            XCTAssertTrue(scene.geometry.merged().polygons.allSatisfy { ($0.material as? Material)?.color == expected })
        }
    }

    func testUnknownColorWarnsAndUsesInheritedColor() throws {
        let scene = try Scene(csgString: "color([1,0,0]) color(\"notacolor\") cube(1);", isCancelled: { false })
        XCTAssertEqual(scene.warnings.count, 1)
        XCTAssertTrue(scene.warnings[0].contains("Unknown CSG color 'notacolor'"))
        XCTAssertTrue(scene.build { false })
        XCTAssertTrue(scene.geometry.merged().polygons.allSatisfy { ($0.material as? Material)?.color == .red })
    }

    func testInvalidValuesAndGeometryOptionsRemainErrors() {
        for source in [
            "text(\"Hi\", halign=2);", "text(\"Hi\", spacing=\"wide\");", "text(\"Hi\", size=-1);",
            "color(\"red\", alpha=2) cube(1);", "linear_extrude(height=-1) square(1);",
            "multmatrix([[1,0],[0,1]]) cube(1);",
        ] {
            XCTAssertThrowsError(try Scene(csgString: source, isCancelled: { false }), source)
        }
    }

    func testImportedCSGWarningsReachSceneIncludingExportValidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("warning.csg")
        try "color(\"notacolor\") cube(1);".write(to: url, atomically: true, encoding: .utf8)
        let importStatement = "import \"warning.csg\""
        let delegate = TestDelegate(directory: directory)
        let scene = try evaluate(parse("group { \(importStatement) }\n\(importStatement)"), delegate: delegate)
        XCTAssertEqual(scene.warnings.count, 1)
        XCTAssertTrue(scene.warnings[0].hasPrefix("warning.csg:"))
        let directlyOpened = try Scene(
            csgString: String(contentsOf: url), at: url, isCancelled: { false }
        )
        XCTAssertEqual(scene.warnings, directlyOpened.warnings.map { "warning.csg: \($0)" })
        XCTAssertTrue(directlyOpened.warnings[0].contains("on line 1."))
        let exportOnly = try evaluate(
            parse("if preview { cube } else { \(importStatement) }"),
            preview: true,
            delegate: delegate
        )
        XCTAssertEqual(exportOnly.warnings, scene.warnings)
    }

    private func descendants(_ geometry: Geometry) -> [Geometry] {
        [geometry] + geometry.children.flatMap(descendants)
    }

    func testBackgroundOverlaysPreserveTransformsWithoutChangingModel() throws {
        let source = """
        translate([10,0,0]) difference() {
            cube(4,true);
            %translate([2,0,0]) cube(2,true);
        }
        """
        let cache = GeometryCache(diskCache: nil)
        for _ in 0 ..< 2 {
            let scene = try Scene(csgString: source, cache: cache, isCancelled: { false })
            let root = try XCTUnwrap(scene.children.first)
            let overlay = try XCTUnwrap(root.children.first(where: \.isBackground))
            XCTAssertFalse(overlay.isHidden)
            XCTAssertEqual(overlay.overestimatedBounds.center, [12, 0, 0])
            XCTAssertTrue(root.renderedChildren.contains(where: { $0 === overlay }))
            let progress = RenderProgress()
            XCTAssertTrue(scene.build(progress: progress))
            XCTAssertTrue(progress.isFinished)
            XCTAssertTrue(scene.geometry.hasBuiltMeshes)
            XCTAssertTrue(overlay.hasBuiltMeshes)
            XCTAssertEqual(scene.geometry.merged().signedVolume, 64, accuracy: 1e-8)
            XCTAssertEqual(scene.visibleGeometry.merged().signedVolume, 64, accuracy: 1e-8)
            XCTAssertEqual(scene.visibleBounds.max.x, 13, accuracy: 1e-8)
        }
    }

    func testBackgroundOnlyDocumentIsVisibleButExportsEmpty() throws {
        let scene = try Scene(csgString: "%cube(4,true);", isCancelled: { false })
        let root = try XCTUnwrap(scene.children.first)
        let overlay = try XCTUnwrap(root.children.last)
        XCTAssertTrue(overlay.isBackground)
        XCTAssertEqual(root.renderedChildren.count, 1)
        XCTAssertTrue(root.renderedChildren.first === overlay)
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(overlay.cachedMesh, Mesh.cube())
        XCTAssertEqual(scene.visibleBounds.size, [4, 4, 4])
        XCTAssertTrue(scene.geometry.merged().isEmpty)
        XCTAssertTrue(scene.visibleGeometry.merged().isEmpty)
    }

    func testHiddenAndNestedBackgroundModifiers() throws {
        let scene = try Scene(csgString: """
        %group() { cube(1); %translate([3,0,0]) cube(1); *cube(20); }
        *%cube(30);
        """, isCancelled: { false })
        let root = try XCTUnwrap(scene.children.first)
        let overlays = root.children.filter { $0.isBackground && !$0.isHidden }
        XCTAssertEqual(overlays.count, 1)
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(scene.visibleBounds.min, [0, 0, 0])
        XCTAssertEqual(scene.visibleBounds.max, [4, 1, 1])
        XCTAssertTrue(scene.geometry.merged().isEmpty)
        XCTAssertTrue(overlays[0].children.filter { !$0.isHidden }.allSatisfy(\.hasBuiltMeshes))
    }

    func testBackgroundExtrusionReusesCachedMeshWithoutEvaluatingProfile() throws {
        let cache = GeometryCache(diskCache: nil)
        let source = "%linear_extrude(height=2) difference() { square(4,true); square(2,true); }"
        func difference(in geometry: Geometry) -> Geometry? {
            if geometry.type == .difference { return geometry }
            return geometry.children.lazy.compactMap { difference(in: $0) }.first
        }
        for iteration in 0 ..< 2 {
            let scene = try Scene(csgString: source, cache: cache, isCancelled: { false })
            let overlay = try XCTUnwrap(scene.children.first?.children.last)
            XCTAssertTrue(overlay.isBackground)
            let profile = try XCTUnwrap(difference(in: overlay))
            XCTAssertTrue(profile.cachedPath == nil)
            XCTAssertTrue(scene.build { false })
            XCTAssertEqual(profile.cachedPath == nil, iteration > 0)
            XCTAssertEqual(try XCTUnwrap(overlay.cachedMesh).signedVolume, 24, accuracy: 1e-8)
            XCTAssertTrue(scene.geometry.merged().isEmpty)
        }
    }

    func testFocusedBackgroundControlsVisibleBounds() throws {
        let scene = try Scene(csgString: "cube(100,true); !%translate([10,0,0]) cube(2,true);", isCancelled: { false })
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(scene.visibleBounds, Bounds([9, -1, -1], [11, 1, 1]))
        XCTAssertTrue(scene.visibleGeometry.merged().isEmpty)
    }

    func testBackgroundOperandsAreExcludedFromAllModelOperations() throws {
        for operation in ["union", "difference", "intersection", "hull", "minkowski"] {
            let scene = try Scene(
                csgString: "\(operation)() { cube(2,true); %cube(1,true); }",
                isCancelled: { false }
            )
            XCTAssertTrue(scene.build { false })
            XCTAssertEqual(scene.geometry.merged().signedVolume, 8, accuracy: 1e-8, operation)
            XCTAssertEqual(scene.geometry.volume { false }, 8, accuracy: 1e-8, operation)
        }
    }

    func testModifierMappings() throws {
        for (prefix, debug, hidden, focused) in [
            ("#", true, false, false), ("%", false, true, false),
            ("*", false, true, false), ("!", false, false, true),
            ("!##", true, false, true), ("%#!", true, true, true),
        ] {
            let geometry = try Geometry(csgString: "\(prefix) cube(1);", isCancelled: { false })
            let cube = try XCTUnwrap(geometry.children.first)
            XCTAssertEqual(cube.debug, debug, prefix)
            XCTAssertEqual(cube.isHidden, hidden, prefix)
            XCTAssertEqual(cube.isFocused, focused, prefix)
        }
    }

    func testModifiersOnGroupsPropagateToChildren() throws {
        let geometry = try Geometry(csgString: "#!group() { cube(1); sphere(1); }", isCancelled: { false })
        let group = try XCTUnwrap(geometry.children.first)
        XCTAssertTrue(group.debug)
        XCTAssertTrue(group.isFocused)
        XCTAssertTrue(group.children.allSatisfy { $0.debug && $0.isFocused })
    }

    func testHiddenModifiersExcludeBooleanOperands() throws {
        for prefix in ["%", "*"] {
            XCTAssertEqual(
                try mesh("difference() { cube(2,true); \(prefix)cube(1,true); }").signedVolume,
                8,
                accuracy: 1e-8
            )
            XCTAssertTrue(try mesh("difference() { \(prefix)cube(2,true); cube(1,true); }").isEmpty)
        }
        XCTAssertEqual(try mesh("difference() { cube(2,true); #cube(1,true); }").signedVolume, 7, accuracy: 1e-8)
    }

    func testFocusModifierFiltersSceneGeometry() throws {
        let scene = try Scene(csgString: "cube(4,true); !translate([10,0,0]) cube(1,true);", isCancelled: { false })
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(scene.visibleBounds, Bounds([9.5, -0.5, -0.5], [10.5, 0.5, 0.5]))
        XCTAssertEqual(scene.visibleGeometry.merged().signedVolume, 1, accuracy: 1e-8)
    }

    func testModifiersSurviveTransformsAndColors() throws {
        let geometry = try Geometry(csgString: """
        translate([2,3,4]) rotate([0,0,90]) scale([2,1,1]) color([1,0,0]) group() {
            #cube(1,true);
            %sphere(2);
            !translate([3,0,0]) cube(1,true);
        }
        """, isCancelled: { false })
        XCTAssertTrue(geometry.childDebug)
        XCTAssertTrue(geometry.childIsHidden)
        XCTAssertTrue(geometry.childIsFocused)
        XCTAssertTrue(geometry.build { false })
        let focused = geometry.withoutHiddenOrUnfocused()
        XCTAssertEqual(focused.merged().bounds, Bounds([1.5, 8, 3.5], [2.5, 10, 4.5]))
        XCTAssertTrue(focused.merged().polygons.allSatisfy { ($0.material as? Material)?.color == .red })
    }

    func testDebugModifierSurvivesShearedBooleanTransform() throws {
        let geometry = try Geometry(csgString: """
        multmatrix([[1,1,0,2],[0,1,0,3],[0,0,1,4],[0,0,0,1]])
        difference() { cube(2,true); #cube(1,true); }
        """, isCancelled: { false })
        XCTAssertTrue(geometry.childDebug)
        XCTAssertTrue(geometry.build { false })
        XCTAssertEqual(geometry.merged().signedVolume, 7, accuracy: 1e-8)
        let debug = try XCTUnwrap(descendants(geometry).first { $0.debug })
        XCTAssertEqual(debug.merged().bounds, Bounds([1, 2.5, 3.5], [3, 3.5, 4.5]))
    }

    func testModifiersOnTransformedMinkowskiSum() throws {
        let geometry = try Geometry(csgString: """
        translate([5,0,0]) minkowski() { #cube(1,true); cube(1,true); }
        """, isCancelled: { false })
        XCTAssertTrue(geometry.childDebug)
        XCTAssertTrue(geometry.build { false })
        XCTAssertEqual(geometry.merged().bounds, Bounds([4, -1, -1], [6, 1, 1]))
    }

    func testModifiersOnPathsAreNotFlattenedAway() throws {
        let geometry = try Geometry(
            csgString: "translate([2,0,0]) group() { #square(1); %circle(1); }",
            isCancelled: { false }
        )
        XCTAssertTrue(geometry.childDebug)
        XCTAssertTrue(geometry.childIsHidden)
        let visible = geometry.withoutHiddenOrUnfocused()
        XCTAssertFalse(visible.childIsHidden)
        XCTAssertEqual(visible.overestimatedBounds, Bounds([2, 0, 0], [3, 1, 0]))
        XCTAssertEqual(
            try mesh("linear_extrude(height=2) group() { square(1); %square(4); }").signedVolume,
            2, accuracy: 1e-8
        )
    }

    func testMalformedModifiersAndErrorLocations() throws {
        for source in ["#", "%!", "cube(#1);", "#%group() { ! }"] {
            XCTAssertThrowsError(try Geometry(csgString: source, isCancelled: { false })) {
                XCTAssertTrue($0 is CSGImportError)
            }
        }
        XCTAssertThrowsError(try Geometry(csgString: "\n# cube([1,2]);", isCancelled: { false })) {
            let error = $0 as? CSGImportError
            XCTAssertEqual(error?.line, 2)
            XCTAssertEqual(error?.column, 3)
            XCTAssertEqual(error?.errorDescription, error.map { "\($0.message) on line 2." })
        }
    }

    func testCSGSceneLoading() throws {
        let cache = GeometryCache()
        let scene = try Scene(csgString: "cube([2,3,4]);", cache: cache, isCancelled: { false })
        XCTAssertTrue(scene.cache === cache)
        XCTAssertEqual(scene.background, .color(.clear))
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(scene.geometry.merged().bounds, Bounds(.zero, [2, 3, 4]))
    }

    func testCSGSceneLoadingRejectsInvalidInputsAndCancellation() throws {
        XCTAssertThrowsError(try Scene(csgString: "cube([1,2]);", isCancelled: { false })) {
            XCTAssertTrue($0 is CSGImportError)
        }
        XCTAssertThrowsError(try Scene(csgString: "cube(1);", isCancelled: { true })) {
            XCTAssertTrue($0 is CancellationError)
        }
    }

    func testZeroSizeCubesRemainEmptyBooleanOperands() throws {
        let solid = try mesh("cube(2);")
        for emptyCube in [
            "cube(0);",
            "cube(size = [0, 0, 0], center = false);",
            "cube(size = [2, 0, 3], center = true);",
        ] {
            XCTAssertTrue(try mesh(emptyCube).isEmpty, emptyCube)
            XCTAssertTrue(try mesh("difference() { \(emptyCube) cube(2); }").isEmpty, emptyCube)
            XCTAssertEqual(try mesh("difference() { cube(2); \(emptyCube) }"), solid, emptyCube)
        }
    }

    private func mesh(_ source: String) throws -> Mesh {
        let geometry = try Geometry(csgString: source, isCancelled: { false })
        XCTAssertTrue(geometry.build { false })
        return geometry.merged()
    }

    func testResizeScalesAboutOriginAndSupportsExportedAutoFlags() throws {
        let child = "translate([2,3,4]) cube([2,3,4]);"
        let explicit = try mesh("resize([12,6,0]) \(child)")
        XCTAssertEqual(explicit.bounds, Bounds([12, 6, 4], [24, 12, 8]))
        for auto in ["true", "[false,false,true]", "[0,0,1]"] {
            let result = try mesh("resize(newsize=[12,6,0], auto=\(auto), convexity=0) \(child)")
            XCTAssertEqual(result.bounds, Bounds([12, 6, 24], [24, 12, 48]), auto)
        }
        XCTAssertEqual(try mesh("resize([0,0,0], true) \(child)").bounds, try mesh(child).bounds)
    }

    func testResizeUsesEvaluatedBounds() throws {
        let result = try mesh("""
        resize([2,0,0]) difference() {
            cube([8,2,2]);
            translate([4,-1,-1]) cube([5,4,4]);
        }
        """)
        XCTAssertEqual(result.bounds, Bounds(.zero, [2, 2, 2]))
        XCTAssertEqual(result.signedVolume, 8, accuracy: 1e-8)
        XCTAssertTrue(try mesh("resize([1,2,3]) {}").isEmpty)
    }

    func testResizeKeepsProfilesTwoDimensional() throws {
        let source = "resize([4,0,20], true) translate([2,3,0]) square([2,3]);"
        let scene = try Scene(csgString: source, isCancelled: { false })
        XCTAssertTrue(scene.warnings.isEmpty)
        XCTAssertEqual(Bounds(scene.geometry.paths(pretransformed: true)), Bounds([4, 6, 0], [8, 12, 0]))
        let result = try mesh("linear_extrude(height=2) \(source)")
        XCTAssertEqual(result.bounds, Bounds([4, 6, 0], [8, 12, 2]))
        XCTAssertEqual(result.signedVolume, 48, accuracy: 1e-8)
        let rotated = try mesh("linear_extrude(height=1) resize([6,8,0]) rotate(90) square([2,3]);")
        XCTAssertEqual(rotated.bounds.size.x, 6, accuracy: 1e-8)
        XCTAssertEqual(rotated.bounds.size.y, 8, accuracy: 1e-8)
        XCTAssertEqual(rotated.signedVolume, 48, accuracy: 1e-8)
    }

    func testProjectionReturnsSilhouetteOrSliceAtZero() throws {
        let floating = "translate([2,3,4]) cube([2,3,4]);"
        let silhouette = try Scene(csgString: "projection() \(floating)", isCancelled: { false })
        let paths = silhouette.geometry.paths(pretransformed: true)
        XCTAssertEqual(Bounds(paths), Bounds([2, 3, 0], [4, 6, 0]))
        XCTAssertTrue(silhouette.warnings.isEmpty)
        let miss = try Scene(csgString: "projection(cut=true) \(floating)", isCancelled: { false })
        XCTAssertTrue(miss.geometry.paths(pretransformed: true).allSatisfy(\.isEmpty))
        XCTAssertTrue(miss.warnings.isEmpty)
        for source in ["cube([2,3,4], center=true);", "cube([2,3,4]);"] {
            let cut = try mesh("linear_extrude(height=2) projection(true, convexity=3) \(source)")
            XCTAssertTrue(cut.isWatertight, source)
            XCTAssertEqual(cut.signedVolume, 12, accuracy: 1e-8, source)
        }
    }

    func testProjectionDropsEdgeOnFacesAndTangentContacts() throws {
        let verticalFace = "polyhedron([[0,0,0],[0,1,0],[0,1,1],[0,0,1]], [[0,1,2,3]]);"
        let edge = "translate([0,0,0.7071067811865476]) rotate([0,45,0]) cube(1,center=true);"
        let corner = "translate([0,0,0.8660254037844386]) rotate(54.735610317245346,[1,-1,0]) cube(1,center=true);"
        XCTAssertEqual(try mesh(verticalFace).projected(onto: .xy).points.count, 2)
        XCTAssertEqual(try mesh(edge).intersection(with: .xy).points.count, 2)
        XCTAssertEqual(try mesh(corner).intersection(with: .xy).points.count, 1)
        for source in ["projection() \(verticalFace)", "projection(true) \(edge)", "projection(true) \(corner)"] {
            let scene = try Scene(csgString: source, isCancelled: { false })
            XCTAssertTrue(scene.geometry.paths(pretransformed: true).allSatisfy(\.isEmpty), source)
            XCTAssertTrue(scene.warnings.isEmpty, source)
            XCTAssertTrue(try mesh("linear_extrude(height=2) \(source)").isEmpty, source)
        }
    }

    func testProjectionKeepsFilledRegionsAndHolesAlongsideContacts() throws {
        let mesh = try mesh("""
        linear_extrude(height=2) projection(cut=true) {
            difference() {
                cube([4,4,2], center=true);
                cube([2,2,4], center=true);
            }
            translate([10,0,0.7071067811865476]) rotate([0,45,0]) cube(1,center=true);
        }
        """)
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertEqual(mesh.bounds.size, [4, 4, 2])
        XCTAssertEqual(mesh.signedVolume, 24, accuracy: 1e-8)
    }

    func testProjectionProjectsPlanarMeshAndDropsItsSlice() throws {
        let face = "polyhedron([[0,0,-1],[0,1,-1],[1,1,1],[1,0,1]], [[0,1,2,3]]);"
        XCTAssertFalse(try mesh("linear_extrude(height=1) projection() \(face)").isEmpty)
        let section = try Scene(csgString: "projection(cut=true) \(face)", isCancelled: { false })
        XCTAssertTrue(section.geometry.paths(pretransformed: true).allSatisfy(\.isEmpty))
        XCTAssertEqual(section.warnings.count, 1)
    }

    func testCubeAndPrimitivePreservation() throws {
        let geometry = try Geometry(csgString: "cube(size = [2, 3, 4], center = false);", isCancelled: { false })
        XCTAssertEqual(geometry.children.first?.type, .cube)
        XCTAssertTrue(geometry.build { false })
        XCTAssertEqual(geometry.merged().bounds.min, .zero)
        XCTAssertEqual(geometry.merged().bounds.max, Vector(2, 3, 4))
        XCTAssertEqual(try mesh("cube(2, true);").signedVolume, 8, accuracy: 0.000001)
    }

    func testCirclesStartOnPositiveXAndRoundFractionalFragmentCountsUp() throws {
        for (fragments, segments) in [(5.0, 5), (5.5, 6)] {
            let result = try mesh("linear_extrude(1) circle(r=2, $fn=\(fragments));")
            let base = Set(result.polygons.flatMap { $0.vertices.map(\.position) }.filter { $0.z == 0 })
            XCTAssertEqual(base.count, segments)
            XCTAssertTrue(base.contains([2, 0, 0]))
            XCTAssertTrue(result.isWatertight)
        }
    }

    func testFragmentErrorControlsCircularDetailAndHelicalSlices() throws {
        for (source, count) in [
            ("linear_extrude(1) circle(r=2,$fe=0.1);", 20),
            ("linear_extrude(1) circle(r=2,$fe=0.1,$fn=12);", 24),
            ("linear_extrude(4,twist=90,segments=0,$fe=0.01) square(2,true);", 32),
        ] {
            let result = try mesh(source)
            XCTAssertTrue(result.isWatertight, source)
            XCTAssertEqual(Set(result.polygons.flatMap(\.vertices).map(\.position)).count, count, source)
        }
    }

    func testSphereAndTaperedCylinder() throws {
        let sphere = try mesh("sphere(d = 4, $fn = 16);")
        XCTAssertEqual(sphere.bounds.size.x, 4 * cos(.pi / 16), accuracy: 0.000001)
        XCTAssertTrue(sphere.isWatertight)
        let cylinder = try mesh("cylinder(h = 4, r1 = 1, r2 = 0.5, center = true, $fn = 16);")
        XCTAssertEqual(cylinder.bounds.min.z, -2, accuracy: 0.000001)
        XCTAssertEqual(cylinder.bounds.max.z, 2, accuracy: 0.000001)
        XCTAssertEqual(cylinder.bounds.size.x, 2, accuracy: 0.000001)
        XCTAssertTrue(cylinder.isWatertight)
    }

    func testOpenSCADPrimitiveStylesAndFragmentRounding() throws {
        for (source, count) in [
            ("sphere(r=2, style=\"orig\", $fn=5);", 15),
            ("sphere(r=2, style=\"orig\", $fn=5.5);", 18),
            ("sphere(r=2, style=\"octa\", $fn=12);", 38),
            ("cylinder(r=2, h=3, $fn=5.5);", 12),
        ] {
            let result = try mesh(source)
            let points = Set(result.polygons.flatMap(\.vertices).map(\.position))
            XCTAssertTrue(result.isWatertight, source)
            XCTAssertEqual(points.count, count, source)
            XCTAssertTrue(points.contains { ($0 - Vector(2, 0, 0)).length < 1e-8 }, source)
        }
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

    func testEmptyPrimitivesRemainEmptyDifferenceBases() throws {
        for primitive in ["square([0,2]);", "circle(0);", "sphere(0);", "cylinder(h=0);", "cylinder(r=0);"] {
            XCTAssertTrue(try mesh("difference() { \(primitive) cube(1); }").isEmpty, primitive)
            let filled = try mesh("linear_extrude(1) { square(1); \(primitive) }")
            XCTAssertEqual(filled.signedVolume, 1, accuracy: 1e-8, primitive)
        }
    }

    func testTouchingAndCoplanarCSGAndCompoundProfile() throws {
        for (source, expected) in [
            ("union(){cube(1);translate([1,0,0])cube(1);}", 2.0),
            ("difference(){cube(2);translate([0.5,0.5,1])cube(1);}", 7.0),
            ("linear_extrude(2)difference(){square([6,4]);translate([1,1,0])square([4,2]);}", 32.0),
        ] {
            let result = try mesh(source)
            XCTAssertTrue(result.isWatertight, source)
            XCTAssertEqual(result.signedVolume, expected, accuracy: 1e-8, source)
        }
    }

    func testHullAndMinkowski() throws {
        let hull = try mesh("hull() { cube(1); translate([2,0,0]) cube(1); }")
        XCTAssertEqual(hull.signedVolume, 3, accuracy: 0.000001)
        let sum = try mesh("minkowski() { cube(1, true); cube(1, true); }")
        XCTAssertEqual(sum.signedVolume, 8, accuracy: 0.000001)
    }

    func testImportedGeometryUsesDefaultPrimitiveNormals() throws {
        for source in ["sphere($fn=12);", "cylinder(h=2,r=1,$fn=12);"] {
            let context = EvaluationContext(source: source, delegate: nil) { false }
            let geometry = try Geometry(csgString: source, at: nil, context: context)
            XCTAssertTrue(descendants(geometry).allSatisfy { $0.smoothing == nil })
            XCTAssertTrue(geometry.build { false })
            XCTAssertTrue(geometry.merged().polygons.contains { polygon in
                polygon.vertices.contains { ($0.normal - polygon.plane.normal).length > 1e-8 }
            }, source)
        }
    }

    func testDirectCSGLoadingUsesZeroSmoothing() throws {
        let source = "sphere($fn=12);"
        let geometry = try Geometry(csgString: source, isCancelled: { false })
        let scene = try Scene(csgString: source, isCancelled: { false })
        for root in [geometry] + scene.children {
            XCTAssertTrue(descendants(root).allSatisfy { $0.smoothing == .zero })
            XCTAssertTrue(root.build { false })
            XCTAssertTrue(root.merged().polygons.allSatisfy { polygon in
                polygon.vertices.allSatisfy { ($0.normal - polygon.plane.normal).length < 1e-8 }
            })
        }
    }

    func testNestedCSGImportsInheritRootSmoothing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rootURL = directory.appendingPathComponent("root.csg")
        let childURL = directory.appendingPathComponent("child.csg")
        let source = "import(\"child.csg\");"
        try source.write(to: rootURL, atomically: true, encoding: .utf8)
        try "sphere($fn=12);".write(to: childURL, atomically: true, encoding: .utf8)

        let direct = try Scene(csgString: source, at: rootURL, isCancelled: { false })
        let smooth = try evaluate(parse("import \"\(rootURL.path)\""), delegate: nil)
        let flat = try evaluate(parse("smoothing 0\nimport \"\(rootURL.path)\""), delegate: nil)
        for (scene, smoothing) in [(direct, Angle?.some(.zero)), (smooth, nil), (flat, .some(.zero))] {
            XCTAssertTrue(scene.children.flatMap(descendants).allSatisfy { $0.smoothing == smoothing })
            XCTAssertTrue(scene.build { false })
            let hasSmoothNormals = scene.geometry.merged().polygons.contains { polygon in
                polygon.vertices.contains { ($0.normal - polygon.plane.normal).length > 1e-8 }
            }
            XCTAssertEqual(hasSmoothNormals, smoothing == nil)
        }
    }

    func testCSGSmoothingIsAppliedAfterGeometryGeneration() throws {
        let smoothings: [Angle?] = [nil, .zero, .degrees(45)]
        for smoothing in smoothings {
            let context = EvaluationContext(source: "", delegate: nil) { false }
            context.state.smoothing = smoothing
            for source in [
                "sphere($fn=12);",
                "union() { sphere($fn=12); cube(1); }",
                "%sphere($fn=12);",
                "multmatrix([[1,1,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]) sphere($fn=12);",
            ] {
                let geometry = try Geometry(csgString: source, at: nil, context: context)
                XCTAssertTrue(descendants(geometry).allSatisfy { $0.smoothing == nil }, source)
                let copy = geometry.with(
                    transform: .identity, material: nil, smoothing: smoothing, sourceLocation: { nil }
                )
                XCTAssertTrue(descendants(copy).allSatisfy { $0.smoothing == smoothing }, source)
                XCTAssertTrue(descendants(geometry).allSatisfy { $0.smoothing == nil }, source)
            }
        }
    }

    func testRepeatedCSGImportsRespectChangesToSmoothing() throws {
        final class Delegate: EvaluationDelegate {
            var importCount = 0
            func resolveURL(for path: String) -> URL { URL(fileURLWithPath: path) }
            func importGeometry(for _: URL) throws -> Geometry? {
                importCount += 1
                return nil
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sphere.csg")
        try "sphere($fn=12);".write(to: url, atomically: true, encoding: .utf8)
        let delegate = Delegate()
        let scene = try evaluate(parse("""
        smoothing 0
        import "\(url.path)"
        smoothing -1
        import "\(url.path)"
        smoothing 0
        import "\(url.path)"
        """), delegate: delegate)
        XCTAssertEqual(delegate.importCount, 1)
        XCTAssertEqual(scene.children.count, 3)
        XCTAssertTrue(scene.build { false })
        for (geometry, smoothing) in zip(scene.children, [Angle?.some(.zero), nil, .some(.zero)]) {
            XCTAssertTrue(descendants(geometry).allSatisfy { $0.smoothing == smoothing })
            let hasSmoothNormals = geometry.merged().polygons.contains { polygon in
                polygon.vertices.contains { ($0.normal - polygon.plane.normal).length > 1e-8 }
            }
            XCTAssertEqual(hasSmoothNormals, smoothing == nil)
        }
    }

    func testExplicitZeroSmoothingProducesFlatNormals() throws {
        for source in [
            "cube(1);",
            "sphere($fn=12);",
            "cylinder(h=2,r=1,$fn=12);",
            "hull() { cube(1); translate([2,1,1]) cube(1); }",
            "hull() { sphere($fn=12); translate([2,0,0]) sphere($fn=12); }",
            "minkowski() { cube(1); cube(1); }",
            "difference() { sphere($fn=12); cube(1); }",
            "multmatrix([[1,1,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]) " +
                "hull() { cube(1); translate([2,1,1]) cube(1); }",
        ] {
            let context = EvaluationContext(source: source, delegate: nil) { false }
            context.state.smoothing = .zero
            let geometry = try Geometry(csgString: source, at: nil, context: context).with(
                transform: .identity, material: nil, smoothing: .zero, sourceLocation: { nil }
            )
            XCTAssertTrue(geometry.build { false }, source)
            let mesh = geometry.merged()
            XCTAssertFalse(mesh.isEmpty, source)
            XCTAssertTrue(mesh.polygons.allSatisfy { polygon in
                polygon.vertices.allSatisfy { ($0.normal - polygon.plane.normal).length < 1e-8 }
            }, source)
        }
    }

    func testNativeGeometryStillPreservesSmoothNormals() throws {
        let scene = try evaluate(parse("sphere"), delegate: nil)
        XCTAssertTrue(scene.build { false })
        XCTAssertTrue(scene.geometry.merged().polygons.contains { polygon in
            polygon.vertices.contains { ($0.normal - polygon.plane.normal).length > 1e-8 }
        })
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

    func testLinearExtrusionTapersTheUnionOfItsChildren() throws {
        let scene = try Scene(
            csgString: """
            linear_extrude(height=2, scale=0.5, center=true) {
                square(2);
                translate([1,0,0]) square(2);
            }
            """,
            isCancelled: { false }
        )
        XCTAssertTrue(scene.warnings.isEmpty)
        XCTAssertTrue(scene.build { false })
        let result = scene.geometry.merged()
        XCTAssertEqual(result.bounds, Bounds([0, 0, -1], [3, 2, 1]))
        XCTAssertEqual(result.signedVolume, 7, accuracy: 1e-8)
        XCTAssertTrue(result.isWatertight)
    }

    func testLinearExtrusionAppliesAnisotropicScaleAfterClockwiseTwist() throws {
        let result = try mesh("""
        linear_extrude(height=2, scale=[0.5,0.75], twist=90, slices=1)
            translate([2,0,0]) square(1,true);
        """)
        let top = result.polygons.flatMap(\.vertices).map(\.position).filter { $0.z == 2 }
        XCTAssertEqual(Bounds(top), Bounds([-0.25, -1.875, 2], [0.25, -1.125, 2]))
        XCTAssertTrue(result.isWatertight)
        XCTAssertEqual(result.signedVolume, 11 / 12, accuracy: 1e-8)
    }

    func testLinearExtrusionCanTaperToAPointOrAnEdge() throws {
        for (scale, volume) in [("0", 8.0), ("[0,0.75]", 11.0)] {
            let result = try mesh("""
            linear_extrude(height=2, scale=\(scale), slices=4)
                difference() { square(4,true); square(2,true); }
            """)
            XCTAssertTrue(result.isWatertight, scale)
            XCTAssertEqual(result.signedVolume, volume, accuracy: 1e-8, scale)
            let top = result.polygons.flatMap(\.vertices).map(\.position).filter { $0.z == 2 }
            XCTAssertEqual(Bounds(top).size.y, scale == "0" ? 0 : 3, accuracy: 1e-8, scale)
            XCTAssertTrue(top.allSatisfy { $0.x == 0 }, scale)
        }
        let pyramid = try mesh("linear_extrude(height=2, scale=-1) square(2,true);")
        XCTAssertTrue(pyramid.isWatertight)
        XCTAssertEqual(pyramid.signedVolume, 8 / 3, accuracy: 1e-8)
        let wedge = try mesh("linear_extrude(height=2, scale=[0,0.75], slices=1) rotate(30) square(2,true);")
        XCTAssertTrue(wedge.isWatertight)
        XCTAssertEqual(wedge.signedVolume, 4.532692365, accuracy: 1e-6)
    }

    func testLinearExtrusionUsesDefaultSlicesForAnisotropicTaper() throws {
        let standard = try mesh("linear_extrude(height=4, scale=[0.5,1], $fn=4) rotate(30) square(2);")
        let explicit = try mesh("linear_extrude(height=4, scale=[0.5,1], slices=4, $fn=4) rotate(30) square(2);")
        XCTAssertEqual(standard, explicit)
        XCTAssertTrue(standard.isWatertight)
    }

    func test2DBooleansProducePathsAndExtrudeWithoutWarnings() throws {
        for (operation, area) in [("union", 6.0), ("difference", 2.0), ("intersection", 2.0)] {
            let source = "\(operation)() { square(2); translate([1,0,0]) square(2); }"
            let scene = try Scene(csgString: source, isCancelled: { false })
            let geometry = try XCTUnwrap(scene.children.first)
            let path = try XCTUnwrap(geometry.path())
            XCTAssertTrue(path.isClosed)
            XCTAssertEqual(Mesh.fill(path, faces: .front).surfaceArea, area, accuracy: 1e-8)
            XCTAssertTrue(scene.warnings.isEmpty, scene.warnings.joined(separator: "\n"))
            let extruded = try mesh("linear_extrude(height=3) \(source)")
            XCTAssertEqual(extruded.signedVolume, area * 3, accuracy: 1e-8)
            XCTAssertTrue(extruded.isWatertight)
        }
    }

    func test2DBooleanGroupsAreSingleOperands() throws {
        let group = "group() { square(2); translate([1,0,0]) square(2); }"
        for (operation, cutter, area) in [
            ("difference", "translate([2,0,0]) square(1);", 5.0),
            ("intersection", "translate([2,0,0]) square(2);", 2.0),
        ] {
            let result = try mesh("linear_extrude(height=1) \(operation)() { \(group) \(cutter) }")
            XCTAssertEqual(result.signedVolume, area, accuracy: 1e-8)
        }
    }

    func test2DHullAndMinkowskiProduceExtrudablePaths() throws {
        for (operation, area) in [("hull", 10.0), ("minkowski", 16.0)] {
            let source = "\(operation)() { square(2,true); translate([3,0,0]) square(2,true); }"
            let scene = try Scene(csgString: source, isCancelled: { false })
            XCTAssertTrue(scene.warnings.isEmpty, scene.warnings.joined(separator: "\n"))
            let path = try XCTUnwrap(scene.children.first?.path())
            XCTAssertEqual(Mesh.fill(path, faces: .front).surfaceArea, area, accuracy: 1e-8)
            let result = try mesh("linear_extrude(height=2) \(source)")
            XCTAssertEqual(result.signedVolume, area * 2, accuracy: 1e-8)
            XCTAssertTrue(result.isWatertight)
        }
    }

    func testMinkowskiAcceptsConvexityHint() throws {
        for primitive in ["square(1,true);", "cube(1,true);"] {
            let scene = try Scene(
                csgString: "minkowski(convexity=10) { \(primitive) \(primitive) }", isCancelled: { false }
            )
            XCTAssertTrue(scene.warnings.isEmpty)
            if let path = scene.children.first?.path() {
                XCTAssertEqual(Mesh.fill(path, faces: .front).surfaceArea, 4, accuracy: 1e-8)
            } else {
                XCTAssertTrue(scene.build { false })
                XCTAssertEqual(scene.geometry.merged().signedVolume, 8, accuracy: 1e-8)
            }
        }
        XCTAssertThrowsError(try Geometry(csgString: "minkowski(convexcity=10) square(1);", isCancelled: { false }))
    }

    func test2DHullAndMinkowskiWithConcavitiesAndHoles() throws {
        let lShape = "polygon([[0,0],[2,0],[2,1],[1,1],[1,2],[0,2]]);"
        XCTAssertEqual(try mesh("linear_extrude(height=1) hull() { \(lShape) }").signedVolume, 3.5, accuracy: 1e-8)
        XCTAssertEqual(
            try mesh("linear_extrude(height=1) minkowski() { \(lShape) square(1,true); }").signedVolume,
            8, accuracy: 1e-8
        )
        let ring = "difference() { square(4,true); square(2,true); }"
        XCTAssertEqual(
            try mesh("linear_extrude(height=1) minkowski() { \(ring) square(1,true); }").signedVolume,
            24, accuracy: 1e-8
        )
        let grouped = "group() { square(1); translate([3,0,0]) square(1); }"
        XCTAssertEqual(
            try mesh("linear_extrude(height=1) minkowski() { \(grouped) square(1); }").signedVolume,
            8, accuracy: 1e-8
        )
    }

    func test2DOperationsUseTheXYPartOfAnImportedMatrix() throws {
        for (operation, area) in [
            ("union", 5.0), ("difference", 3.0), ("intersection", 1.0), ("hull", 5.0), ("minkowski", 12.0),
        ] {
            let scene = try Scene(
                csgString: """
                \(operation)() {
                    square(2,true);
                    multmatrix([[0.5,0,0.866025,1],[0,1,0,0],[-0.866025,0,0.5,3],[0,0,0,1]]) square(2,true);
                }
                """,
                isCancelled: { false }
            )
            XCTAssertTrue(scene.warnings.isEmpty, operation)
            let path = try XCTUnwrap(scene.children.first?.path())
            XCTAssertEqual(path.bounds.min.z, 0, operation)
            XCTAssertEqual(path.bounds.max.z, 0, operation)
            XCTAssertEqual(Mesh.fill(path, faces: .front).surfaceArea, area, accuracy: 1e-8, operation)
        }
    }

    func test2DBooleanHolesAndDisconnectedRegions() throws {
        let ring = "difference() { square(4,true); square(2,true); }"
        let geometry = try Geometry(csgString: ring, isCancelled: { false })
        XCTAssertEqual(try XCTUnwrap(geometry.path()).subpaths.count, 2)
        XCTAssertEqual(try mesh("linear_extrude(height=2) \(ring)").signedVolume, 24, accuracy: 1e-8)
        XCTAssertEqual(
            try mesh("linear_extrude(height=1) union() { \(ring) square(2,true); }").signedVolume,
            16, accuracy: 1e-8
        )
        let disconnected = try Geometry(
            csgString: "union() { square(1); translate([3,0,0]) square(1); }", isCancelled: { false }
        )
        XCTAssertEqual(try XCTUnwrap(disconnected.path()).subpaths.count, 2)
    }

    func test2DBooleanEmptyOperandsAndHiddenModifiers() throws {
        let empty = "intersection() { square(1); translate([3,0,0]) square(1); }"
        for source in [
            "difference() { \(empty) square(2); }",
            "intersection() { square(2); group(); }",
            "intersection() { square(2); \(empty) }",
            "difference() { group(); square(2); }",
        ] {
            XCTAssertTrue(try mesh("linear_extrude(height=1) \(source)").isEmpty, source)
        }
        for modifier in ["%", "*"] {
            XCTAssertTrue(try mesh("linear_extrude(height=1) difference() { \(modifier)square(2); square(1); }")
                .isEmpty)
            for operation in ["union", "difference", "intersection"] {
                let result = try mesh("linear_extrude(height=1) \(operation)() { square(2); \(modifier)square(1); }")
                XCTAssertEqual(result.signedVolume, 4, accuracy: 1e-8)
            }
        }
    }

    func test2DBooleanTransformsColoursAndModifiers() throws {
        let source = "difference() { color([1,0,0]) square(4,true); #square(2,true); }"
        let geometry = try Geometry(csgString: source, isCancelled: { false })
        XCTAssertTrue(geometry.childDebug)
        let extruded = try mesh("linear_extrude(height=2) \(source)")
        XCTAssertEqual(extruded.signedVolume, 24, accuracy: 1e-8)
        XCTAssertTrue(extruded.polygons.contains { polygon in
            (polygon.material as? Material)?.color == .red || polygon.vertices.contains { $0.color == .red }
        })
        let tilted = try Geometry(
            csgString: "union() { rotate([45,0,0]) square(2); rotate([45,0,0]) translate([1,0,0]) square(2); }",
            isCancelled: { false }
        )
        XCTAssertEqual(try Mesh.fill(XCTUnwrap(tilted.path()), faces: .front).surfaceArea, 3 * sqrt(2), accuracy: 1e-8)
        let mirrored =
            try mesh("linear_extrude(height=1) difference() { mirror([1,0,0]) square(4,true); square(2,true); }")
        XCTAssertEqual(mirrored.signedVolume, 12, accuracy: 1e-8)
    }

    func testEach2DTransformActsInTheXYPlane() throws {
        let scene = try Scene(
            csgString: "rotate([0,-60,0]) translate([0,0,5]) rotate([0,60,0]) square(4,true);",
            isCancelled: { false }
        )
        XCTAssertTrue(scene.warnings.isEmpty)
        let path = try XCTUnwrap(scene.children.first?.path())
        XCTAssertEqual(path.bounds.center, .zero)
        XCTAssertEqual(path.bounds.size.x, 1, accuracy: 1e-8)
        XCTAssertEqual(path.bounds.size.y, 4)
        XCTAssertEqual(path.bounds.size.z, 0)
    }

    func testOffsetFillAndResizeUseXYProfiles() throws {
        for (source, area) in [
            ("offset(delta=1) rotate([0,60,0]) square(2,true);", 12.0),
            ("fill() difference() { rotate([0,60,0]) square(4,true); square(1,true); }", 8.0),
            ("resize([6,0,0],auto=true) rotate([0,60,0]) square(2,true);", 72.0),
        ] {
            let scene = try Scene(csgString: source, isCancelled: { false })
            XCTAssertTrue(scene.warnings.isEmpty, source)
            let path = try XCTUnwrap(scene.children.first?.path())
            XCTAssertEqual(Mesh.fill(path, faces: .front).surfaceArea, area, accuracy: 1e-8, source)
        }
    }

    func testShearAfter2DTiltAndRotation() throws {
        let geometry = try Geometry(
            csgString: """
            multmatrix([[1,0.5,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]])
                rotate([0,60,0]) rotate(90) square([2,4]);
            """,
            isCancelled: { false }
        )
        let bounds = try XCTUnwrap(geometry.path()).bounds
        XCTAssertLessThan((bounds.min - Vector(-2, 0, 0)).length, 1e-8)
        XCTAssertLessThan((bounds.max - Vector(1, 2, 0)).length, 1e-8)
    }

    func testExtrusionPreservesTheOrderOf2DTransforms() throws {
        let result = try mesh("linear_extrude(height=1) rotate([0,60,0]) rotate(90) square([2,4]);")
        XCTAssertLessThan((result.bounds.min - Vector(-2, 0, 0)).length, 1e-8)
        XCTAssertLessThan((result.bounds.max - Vector(0, 2, 1)).length, 1e-8)
    }

    func testSmall2DScalesRetainTheirArea() throws {
        let result = try mesh("linear_extrude(height=1) scale([1.25e-8,1.25e-8,1]) square(8e7);")
        XCTAssertEqual(result.signedVolume, 1, accuracy: 1e-8)
    }

    func test2DBooleanResultCanBeOffsetAndImportedAsAProfile() throws {
        let source = "union() { square(2); translate([1,0,0]) square(2); }"
        let offset = try mesh("linear_extrude(height=1) offset(delta=1) \(source)")
        XCTAssertEqual(offset.signedVolume, 20, accuracy: 1e-8)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try source.write(to: directory.appendingPathComponent("profile.csg"), atomically: true, encoding: .utf8)
        let scene = try evaluate(parse("extrude import \"profile.csg\""), delegate: TestDelegate(directory: directory))
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(scene.geometry.merged().signedVolume, 6, accuracy: 1e-8)
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

    func testCachedFinalMeshSkipsOperandsButPreservesDebugOverlays() throws {
        let cache = GeometryCache(diskCache: nil)
        let source = "difference() { cube(4,true); sphere(r=2,$fn=8); }"
        let first = try Scene(csgString: source, cache: cache, isCancelled: { false })
        XCTAssertTrue(first.build { false })
        let second = try Scene(csgString: source, cache: cache, isCancelled: { false })
        let difference = try XCTUnwrap(second.children.first?.children.first)
        let progress = RenderProgress()
        XCTAssertTrue(second.build(progress: progress))
        XCTAssertTrue(progress.isFinished)
        XCTAssertEqual(progress.fractionCompleted, 1)
        XCTAssertTrue(difference.children.allSatisfy { $0.cachedMesh == nil })
        XCTAssertTrue(second.geometry.hasBuiltMeshes)
        XCTAssertEqual(first.geometry.merged(), second.geometry.merged())

        let debug = try Scene(
            csgString: source.replacingOccurrences(of: "sphere", with: "#sphere"),
            cache: cache,
            isCancelled: { false }
        )
        let debugDifference = try XCTUnwrap(debug.children.first?.children.first)
        XCTAssertTrue(debug.build { false })
        XCTAssertTrue(debugDifference.children.allSatisfy { $0.cachedMesh != nil })
        XCTAssertTrue(debugDifference.childDebug)
        XCTAssertFalse(debugDifference.renderedChildren.isEmpty)
    }

    func testPlanarBooleanProfilesAreNotEvaluatedBeforeBuildOrOnCacheHit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        func makeCache() -> GeometryCache {
            GeometryCache(
                diskCache: DiskCache(capacity: 10_000_000, directory: directory),
                diskWritePolicy: .init { _ in -.infinity }
            )
        }
        let source = """
        linear_extrude(height=2) translate([1,2,0]) difference() {
            polygon([[0,0],[0,4],[4,4],[4,0]]);
            translate([1,1,0]) square(2);
        }
        """
        func difference(in geometry: Geometry) -> Geometry? {
            if geometry.type == .difference { return geometry }
            return geometry.children.lazy.compactMap { difference(in: $0) }.first
        }
        let cache = makeCache()
        let first = try Scene(csgString: source, cache: cache, isCancelled: { false })
        let profile = try XCTUnwrap(difference(in: first.geometry))
        XCTAssertTrue(profile.cachedPath == nil)
        XCTAssertTrue(first.build { false })
        XCTAssertTrue(profile.cachedPath != nil)
        let expected = first.geometry.merged()
        XCTAssertEqual(expected.signedVolume, 24, accuracy: 0.000001)
        XCTAssertTrue(expected.isWatertight)
        cache.flushPendingDiskWrites()

        for cache in [cache, makeCache()] {
            let reopened = try Scene(csgString: source, cache: cache, isCancelled: { false })
            let profile = try XCTUnwrap(difference(in: reopened.geometry))
            XCTAssertTrue(profile.cachedPath == nil)
            XCTAssertTrue(reopened.build { false })
            XCTAssertTrue(profile.cachedPath == nil, "Cache hits must not evaluate the profile")
            XCTAssertEqual(reopened.geometry.merged(), expected)
        }
    }

    func testDeferredProfilesUseMeshCache() throws {
        let source = "linear_extrude(height=2) difference() { square(4,true); offset(delta=-0.5) square(4,true); }"
        let cache = GeometryCache(diskCache: nil)
        let scene = try Scene(csgString: source, cache: cache, isCancelled: { false })
        let geometry = try XCTUnwrap(scene.children.first?.children.first)
        guard case let .extrude(paths, _) = geometry.type else { return XCTFail("Expected extrusion") }
        XCTAssertTrue(paths.isEmpty)
        XCTAssertFalse(geometry.children.isEmpty)
        XCTAssertNil(geometry.cachedMesh)
        XCTAssertEqual(cache.count, 0)
        let encoded = try JSONEncoder().encode(geometry.type)
        XCTAssertEqual(try JSONDecoder().decode(GeometryType.self, from: encoded), geometry.type)

        XCTAssertTrue(scene.build { false })
        let expected = try XCTUnwrap(geometry.cachedMesh)
        let reload = try Scene(csgString: source, cache: cache, isCancelled: { false })
        let reloaded = try XCTUnwrap(reload.children.first?.children.first)
        XCTAssertEqual(geometry.cacheKey, reloaded.cacheKey)
        XCTAssertTrue(reload.build { false })
        XCTAssertEqual(reloaded.cachedMesh, expected)
        let changed = try Scene(
            csgString: source.replacingOccurrences(of: "-0.5", with: "-1"),
            cache: cache,
            isCancelled: { false }
        )
        let different = try XCTUnwrap(changed.children.first?.children.first)
        XCTAssertNotEqual(geometry.cacheKey, different.cacheKey)
        XCTAssertNil(cache[mesh: different])
    }

    func testExtrudedProfilesPersistAcrossCacheInstances() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = DiskCache(capacity: 10_000_000, directory: directory)
        let cache = GeometryCache(diskCache: disk, diskWritePolicy: .init { _ in -.infinity })
        let source = "linear_extrude(height=2) difference() { square(4,true); offset(delta=-0.5) square(4,true); }"
        let scene = try Scene(csgString: source, cache: cache, isCancelled: { false })
        XCTAssertTrue(scene.build { false })
        cache.flushPendingDiskWrites()
        let reopenedCache = GeometryCache(diskCache: DiskCache(capacity: 10_000_000, directory: directory))
        let reopened = try Scene(csgString: source, cache: reopenedCache, isCancelled: { false })
        let geometry = try XCTUnwrap(reopened.children.first?.children.first)
        XCTAssertNil(geometry.cachedMesh)
        XCTAssertNotNil(reopenedCache[mesh: geometry])
        XCTAssertTrue(reopened.build { false })
        XCTAssertEqual(scene.geometry.merged(), reopened.geometry.merged())
    }

    func testExtrusionBoundsContainSharpOffsets() throws {
        for source in [
            "linear_extrude(height=2) offset(delta=1) polygon([[0,0],[10,0],[0.1,0.1]]);",
            "linear_extrude(height=2,twist=90,slices=8) difference() { square(4,true); offset(delta=-0.5) square(4,true); }",
            "rotate_extrude($fn=16) translate([5,0,0]) offset(delta=0.5) square(1);",
        ] {
            let scene = try Scene(csgString: source, isCancelled: { false })
            let bounds = scene.geometry.overestimatedBounds
            XCTAssertTrue(scene.build { false })
            let result = scene.geometry.merged()
            XCTAssertTrue(
                result.polygons.flatMap(\.vertices).allSatisfy { bounds.intersects(Bounds($0.position, $0.position)) },
                source
            )
        }
    }

    func testDeferredRevolutionUsesEvaluatedRadiusForAutomaticDetail() throws {
        let profile = "difference() { square([20,3]); translate([2,-1,0]) square([30,5]); }"
        let deferred = try mesh("rotate_extrude() \(profile)")
        let eager = try mesh("rotate_extrude() #\(profile)")
        XCTAssertEqual(deferred, eager)
    }

    func testTransformsDoNotBuildTheirOperandsDuringImport() throws {
        for transform in [
            "translate([2,3,4])",
            "rotate([20,30,40])",
            "scale([2,3,4])",
            "mirror([1,2,3])",
        ] {
            for modifier in ["", "#", "%", "!"] {
                let scene = try Scene(
                    csgString: "\(transform) \(modifier)hull() { sphere($fn=8); translate([3,0,0]) sphere($fn=8); }",
                    cache: GeometryCache(diskCache: nil),
                    isCancelled: { false }
                )
                func check(_ geometry: Geometry) {
                    XCTAssertNil(geometry.cachedMesh, "\(transform) \(modifier)")
                    geometry.children.forEach(check)
                }
                check(scene.geometry)
                XCTAssertTrue(scene.build { false })
                XCTAssertEqual(scene.geometry.merged().isEmpty, modifier == "%")
            }
        }
    }

    func testShearIsBakedDuringImport() throws {
        func imported(_ shear: Double) throws -> Scene {
            try Scene(
                csgString: "multmatrix([[1,\(shear),0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]) cube(1);",
                isCancelled: { false }
            )
        }
        let first = try imported(0.5)
        let second = try imported(0.75)
        let geometry = try XCTUnwrap(first.children.first?.children.first)
        guard case .mesh = geometry.type else {
            return XCTFail("Shear should be baked into a mesh during import")
        }
        XCTAssertNotNil(geometry.cachedMesh)
        XCTAssertNotEqual(
            first.children.first?.children.first?.cacheKey,
            second.children.first?.children.first?.cacheKey
        )
        XCTAssertTrue(first.build { false })
        XCTAssertEqual(first.geometry.merged().bounds.max.x, 1.5, accuracy: 0.000001)
        XCTAssertEqual(first.geometry.merged().signedVolume, 1, accuracy: 0.000001)
    }

    func testShearedProfileUsesDeferredExtrusion() throws {
        let scene = try Scene(
            csgString: """
            linear_extrude(height=2)
            multmatrix([[-1,0.5,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]])
            difference() { square(4,true); square(2,true); }
            """,
            isCancelled: { false }
        )
        let geometry = try XCTUnwrap(scene.children.first?.children.first)
        guard case let .extrude(paths, _) = geometry.type,
              paths.isEmpty
        else {
            return XCTFail("Sheared profiles should remain extrusion children")
        }
        XCTAssertNil(geometry.cachedMesh)
        XCTAssertTrue(scene.build { false })
        let result = scene.geometry.merged()
        XCTAssertEqual(result.signedVolume, 24, accuracy: 0.000001)
        XCTAssertEqual(result.bounds.min.x, -3, accuracy: 0.000001)
        XCTAssertEqual(result.bounds.max.x, 3, accuracy: 0.000001)
        XCTAssertTrue(result.isWatertight)
    }

    func testExtrusionAndRevolutionAreDeferredAndCached() throws {
        for source in [
            "linear_extrude(height=4, twist=90, slices=4) square(1);",
            "linear_extrude(height=4, twist=30, slices=4, segments=8) square(1);",
            "rotate_extrude($fn=16) translate([2,0,0]) square(1);",
            "rotate_extrude(angle=100, start=30, $fn=16) translate([2,0,0]) square(1);",
            "cylinder(h=3, r1=2, r2=1, $fn=16);",
        ] {
            let cache = GeometryCache(diskCache: nil)
            let first = try Scene(csgString: source, cache: cache, isCancelled: { false })
            let geometry = try XCTUnwrap(first.children.first?.children.first)
            XCTAssertNil(geometry.cachedMesh, source)
            XCTAssertEqual(cache.count, 0)
            XCTAssertTrue(first.build { false })
            XCTAssertGreaterThan(cache.count, 0)
            let second = try Scene(csgString: source, cache: cache, isCancelled: { false })
            let reloaded = try XCTUnwrap(second.children.first?.children.first)
            XCTAssertNil(reloaded.cachedMesh, source)
            XCTAssertEqual(geometry.cacheKey, reloaded.cacheKey)
            XCTAssertNotNil(cache[mesh: reloaded])
            XCTAssertTrue(second.build { false })
            XCTAssertEqual(first.geometry.merged(), second.geometry.merged(), source)
        }
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

    func testExtrusionSegmentsSubdivideOutlinesIndependentlyOfSlices() throws {
        for (arguments, profile, count) in [
            ("segments=8", "square(10);", 8),
            ("segments=6", "square(10);", 4),
            ("segments=8, twist=35, $fn=512", "square([10,2]);", 8),
            ("segments=0, twist=35", "square(10);", 4),
            ("segments=4", "circle(5,$fn=12);", 12),
            ("segments=8", "difference(){square(10,true);square(4,true);}", 16),
            ("segments=8, scale=[0.5,1], twist=35", "difference(){square(10,true);square(4,true);}", 16),
        ] {
            let result = try mesh("linear_extrude(height=10, slices=2, \(arguments)) \(profile)")
            let vertices = result.polygons.flatMap { $0.vertices.map(\.position) }
            XCTAssertEqual(Set(vertices.map(\.z)), [0, 5, 10], arguments)
            XCTAssertEqual(Set(vertices.filter { $0.z == 5 }).count, count, arguments)
            XCTAssertTrue(result.isWatertight, arguments)
        }
    }

    func testCSGExtrusionPreservesHighFragmentCounts() throws {
        let result = try mesh("linear_extrude(height=2) circle(1,$fn=320);")
        XCTAssertEqual(Set(result.polygons.flatMap { $0.vertices.map(\.position) }).count, 640)
        XCTAssertTrue(result.isWatertight)
    }

    func testAutomaticExtrusionSegmentsInCurrentExports() throws {
        for (arguments, profile, count) in [
            ("twist=35, $fn=8.9, $fa=12, $fs=2", "square([10,2]);", 8),
            ("twist=35, $fn=0, $fa=12, $fs=3", "square([10,2]);", 10),
            ("twist=35, $fn=0, $fa=45, $fs=0.5", "square([10,2]);", 8),
            ("twist=35, $fn=0, $fa=26, $fs=1", "square([2.999,3.001]);", 12),
            ("twist=35, $fn=0, $fa=45, $fs=1.5", "difference(){square(10,true);square(1,true);}", 12),
            ("twist=35, segments=0, $fn=8, $fa=12, $fs=2", "square([10,2]);", 4),
            ("scale=1.1, $fn=8, $fa=12, $fs=2", "square([10,2]);", 4),
            ("scale=[2,1], $fn=0, $fa=12, $fs=3", "square([10,2]);", 16),
            ("twist=35, $fn=8, $fa=12, $fs=2", "difference(){square(10,true);square(4,true);}", 16),
            ("scale=[2,0.75], twist=110, $fn=0, $fa=12, $fs=3", "difference(){square(10,true);square(4,true);}", 32),
            (
                "scale=[2,0.7], twist=-85, $fn=0, $fa=30, $fs=1.1",
                "difference(){square(10,true);rotate(23)square([2.4,1.1],true);}",
                22
            ),
        ] {
            let result = try mesh("linear_extrude(height=10, slices=2, \(arguments)) \(profile)")
            let vertices = result.polygons.flatMap { $0.vertices.map(\.position) }
            XCTAssertEqual(Set(vertices.map(\.z)), [0, 5, 10], arguments)
            XCTAssertEqual(Set(vertices.filter { $0.z == 5 }).count, count, arguments)
            XCTAssertTrue(result.isWatertight, arguments)
        }
    }

    func testExtrusionUsesOpenSCADDefaultSlices() throws {
        for (arguments, count) in [
            ("scale=1.5, $fn=16, $fa=12, $fs=2", 1),
            ("twist=90, $fn=16, $fa=12, $fs=2", 4),
            ("twist=90, $fn=30", 8),
            ("twist=-135, $fn=7.5, $fa=12, $fs=2", 3),
            ("twist=-110, segments=0, $fn=16, $fa=12, $fs=2", 5),
            ("twist=120, $fn=0, $fa=45, $fs=0.1", 3),
            ("twist=120, $fn=0, $fa=12, $fs=2", 4),
            ("twist=120, scale=0.25, $fn=0, $fa=12, $fs=2", 3),
            ("twist=-120, scale=4, $fn=0, $fa=12, $fs=2", 3),
            ("twist=45, scale=0, $fn=0, $fa=5, $fs=1.5", 3),
            ("twist=45, scale=[0.1,1], $fn=16.5, $fa=12, $fs=2", 16),
            ("scale=[2,1], $fn=0, $fa=120, $fs=2", 2),
            ("twist=90, slices=2, $fn=16, $fa=12, $fs=2", 2),
            ("twist=90, slices=undef, $fn=16, $fa=12, $fs=2", 4),
        ] {
            let result = try mesh("linear_extrude(height=3, \(arguments)) square(size=[4,4], center=true);")
            let heights = Set(result.polygons.flatMap { $0.vertices.map(\.position.z) })
            XCTAssertEqual(heights.count, count + 1, arguments)
            XCTAssertTrue(result.isWatertight, arguments)
        }
    }

    func testExtrusionTessellationMatchesCurrentOpenSCADForOldExports() throws {
        let profile = "square(size=[4,4], center=true);"
        let exports = [
            "height=3, center=false, convexity=1, twist=90, scale=[1,1], $fn=16, $fa=12, $fs=2",
            "height=3, twist=90, $fn=16, $fa=12, $fs=2",
            "height=3, twist=90, $fn=16",
        ]
        let expected = try mesh("linear_extrude(\(exports[0])) \(profile)")
        for arguments in exports.dropFirst() {
            XCTAssertEqual(try mesh("linear_extrude(\(arguments)) \(profile)"), expected)
        }
        let positions = Set(expected.polygons.flatMap(\.vertices).map(\.position))
        XCTAssertEqual(Set(positions.map(\.z)), [0, 0.75, 1.5, 2.25, 3])
        XCTAssertEqual(positions.count, 80)
    }

    func testTwistUsesOpenSCADClockwiseConvention() throws {
        let result = try mesh("linear_extrude(height=4, twist=90, slices=4) translate([2,0,0]) square(1, true);")
        let top = result.polygons.flatMap(\.vertices).filter { abs($0.position.z - 4) < 0.000001 }
        XCTAssertFalse(top.isEmpty)
        XCTAssertTrue(top.allSatisfy { $0.position.y < -1 })
    }

    func testCoarseTwistPreservesOpenSCADVertexCorrespondence() throws {
        let result = try mesh("linear_extrude(height=2, twist=120, slices=1) square(2,true);")
        XCTAssertTrue(result.isWatertight)
        XCTAssertEqual(result.signedVolume, 6.309401077, accuracy: 1e-8)
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

    func testRoundedOffsetErodesProfilesAndRemovesCollapsedRegions() throws {
        let eroded = try mesh("linear_extrude(2) offset(r=-1, $fn=8) square([6,7]);")
        XCTAssertTrue(eroded.isWatertight)
        XCTAssertEqual(eroded.bounds, Bounds([1, 1, 0], [5, 6, 2]))
        XCTAssertEqual(eroded.signedVolume, 40, accuracy: 1e-8)
        XCTAssertTrue(try mesh("linear_extrude(1) offset(r=-1) square(1);").isEmpty)
        let unchanged = try mesh("linear_extrude(1) offset(r=0, delta=3) square(2);")
        XCTAssertEqual(unchanged.bounds, Bounds([0, 0, 0], [2, 2, 1]))
        XCTAssertEqual(unchanged.signedVolume, 4, accuracy: 1e-8)
    }

    func testRoundedOffsetCornerArcsFollowAdjacentEdges() throws {
        let defaultMesh = try mesh("linear_extrude(1) offset() square(2,true);")
        let defaultCorner = Vector(1 + cos(2 * .pi / 5), 1 + sin(2 * .pi / 5), 0)
        let rotated = try mesh("linear_extrude(1) offset(r=1, $fn=8) rotate(30) square(2,true);")
        let rotatedCorner = Vector((sqrt(3) - 1) / 2 + cos(5 * .pi / 12), (sqrt(3) + 1) / 2 + sin(5 * .pi / 12), 0)
        let inset = try mesh("""
        linear_extrude(1) offset(r=-1,$fn=8) polygon([[0,0],[8,0],[8,4],[4,4],[4,8],[0,8]]);
        """)
        let insetCorner = Vector(4 - sqrt(0.5), 4 - sqrt(0.5), 0)
        for (mesh, corner, count) in [
            (defaultMesh, defaultCorner, 12),
            (rotated, rotatedCorner, 12),
            (inset, insetCorner, 8),
        ] {
            let base = Set(mesh.polygons.flatMap(\.vertices).map(\.position).filter { $0.z == 0 })
            XCTAssertEqual(base.count, count)
            XCTAssertTrue(base.contains { ($0 - corner).length < 1e-8 })
            XCTAssertTrue(mesh.isWatertight)
        }
    }

    func testRoundedOffsetKeepsHolesAndJoinsExpandingRegions() throws {
        let ring = try mesh("""
        linear_extrude(1) offset(r=0.5, $fn=8) {
            difference() { square(4,true); square(2,true); }
        }
        """)
        XCTAssertTrue(ring.isWatertight)
        XCTAssertEqual(ring.signedVolume, 23 + sqrt(2) / 2, accuracy: 1e-8)
        let islands = try mesh("""
        linear_extrude(1) offset(r=0.75, $fn=8) {
            square(1);
            translate([2,0,0]) square(1);
        }
        """)
        XCTAssertTrue(islands.isWatertight)
        XCTAssertEqual(islands.submeshes.count, 1)
    }

    func testChamferedOffsetsMapToPathInset() throws {
        let cut = 2 - sqrt(2.0)
        for (source, volume) in [
            ("offset(delta=1, chamfer=true) square(4,true);", 36 - 2 * cut * cut),
            ("offset(delta=-1, chamfer=true) polygon([[0,0],[8,0],[8,4],[4,4],[4,8],[0,8]]);", 20 + cut * cut / 2),
        ] {
            let scene = try Scene(csgString: "linear_extrude(height=1) \(source)", isCancelled: { false })
            XCTAssertTrue(scene.warnings.isEmpty, source)
            XCTAssertTrue(scene.build { false }, source)
            let mesh = scene.geometry.merged()
            XCTAssertTrue(mesh.isWatertight, source)
            XCTAssertEqual(mesh.signedVolume, volume, accuracy: 1e-8, source)
        }
    }

    func testExtrusionsSkipEdgeOnProfiles() throws {
        let edgeOn = "rotate([90,0,0]) translate([2,0,0]) square(1);"
        let scene = try Scene(csgString: edgeOn, isCancelled: { false })
        XCTAssertTrue(scene.warnings.isEmpty)
        XCTAssertTrue(try XCTUnwrap(scene.children.first?.path()).isEmpty)
        XCTAssertTrue(try mesh("linear_extrude(height=1) intersection() { square(3); \(edgeOn) }").isEmpty)
        XCTAssertTrue(try mesh("linear_extrude(height=1) \(edgeOn)").isEmpty)
        XCTAssertTrue(try mesh("rotate_extrude() \(edgeOn)").isEmpty)
        let result = try mesh("linear_extrude(height=1) { square(1); \(edgeOn) }")
        XCTAssertTrue(result.isWatertight)
        XCTAssertEqual(result.signedVolume, 1, accuracy: 1e-8)
    }

    func testOffsetUnionsChildrenBeforeShrinking() throws {
        let children = "square(3); translate([2,0,0]) square(3);"
        for body in [children, "group() { \(children) }"] {
            let scene = try Scene(
                csgString: "offset(delta=-0.75) { \(body) }",
                isCancelled: { false }
            )
            XCTAssertTrue(scene.warnings.isEmpty)
            let path = try XCTUnwrap(scene.geometry.path())
            XCTAssertEqual(path.subpaths.count, 1)
            XCTAssertEqual(path.bounds, Bounds([0.75, 0.75, 0], [4.25, 2.25, 0]))
        }
    }

    func testOffsetMergesExpandingRegionsAndPreservesHoles() throws {
        let merged = try mesh("""
        linear_extrude(height=1) offset(delta=1) {
            square(1);
            translate([2,0,0]) square(1);
        }
        """)
        XCTAssertTrue(merged.isWatertight)
        XCTAssertEqual(merged.signedVolume, 15, accuracy: 1e-8)
        let ring = try mesh("""
        linear_extrude(height=1) offset(delta=0.25) difference() {
            square(4,true);
            square(2,true);
        }
        """)
        XCTAssertTrue(ring.isWatertight)
        XCTAssertEqual(ring.signedVolume, 18, accuracy: 1e-8)
    }

    func testFillRemovesHolesAndKeepsConcaveAndDisjointRegions() throws {
        let source = """
        fill() {
            difference() {
                union() {
                    square([6,3]);
                    square([3,6]);
                }
                translate([0.5,0.5,0]) square(1.5);
            }
            translate([0.75,0.75,0]) square(0.5);
            translate([8,0,0]) square(2);
        }
        """
        let scene = try Scene(csgString: source, isCancelled: { false })
        XCTAssertTrue(scene.warnings.isEmpty)
        let path = try XCTUnwrap(scene.geometry.path())
        XCTAssertEqual(path.subpaths.count, 2)
        XCTAssertEqual(Mesh.fill(path, faces: .front).surfaceArea, 31, accuracy: 1e-8)
        let result = try mesh("linear_extrude(height=2) \(source)")
        XCTAssertTrue(result.isWatertight)
        XCTAssertEqual(result.signedVolume, 62, accuracy: 1e-8)
    }

    func testFillReturnsAnEmptyProfileWithNo2DChildren() throws {
        let empty = try Scene(csgString: "linear_extrude(height=2) fill() {}", isCancelled: { false })
        XCTAssertTrue(empty.warnings.isEmpty)
        XCTAssertTrue(empty.build { false })
        XCTAssertTrue(empty.geometry.merged().isEmpty)
        let solid = try Scene(csgString: "fill() cube(1);", isCancelled: { false })
        XCTAssertTrue(solid.warnings.contains { $0.contains("'fill' requires 2D children") })
        XCTAssertTrue(solid.build { false })
        XCTAssertTrue(solid.geometry.merged().isEmpty)
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
        XCTAssertNotNil(geometry.path())
        XCTAssertFalse(geometry.paths(pretransformed: true).isEmpty)
        let result = try mesh("linear_extrude(height=1) text(\"Hi\", font=\"Helvetica\");")
        XCTAssertFalse(result.isEmpty)
        #endif
    }

    func testUnsupportedOperationsAndOptionsHaveLocations() throws {
        for source in [
            "surface(file=\"a.dat\");",
            "rotate_extrude(angle=90) square(1,true);",
            "hull() { square(2); cube(2); }",
        ] {
            let scene = try Scene(csgString: "\n\(source)", isCancelled: { false })
            XCTAssertFalse(scene.warnings.isEmpty, source)
            XCTAssertTrue(scene.warnings.allSatisfy { $0.contains("line 2") }, source)
            XCTAssertTrue(scene.build { false }, source)
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
            "linear_extrude(height=1,slices=2,segments=1000000) square(1);",
            "offset(r=1,$fn=40000) square(1);",
        ] {
            XCTAssertThrowsError(try mesh(source))
        }
    }

    func testEvaluationProgressTracksNestedCSGImports() throws {
        final class Delegate: EvaluationDelegate {
            let progress: EvaluationProgress
            var fractions = [Double?]()
            var cancelOnImport = false
            init(progress: EvaluationProgress) { self.progress = progress }
            func resolveURL(for path: String) -> URL { URL(fileURLWithPath: path) }
            func importGeometry(for url: URL) throws -> Geometry? {
                guard url.pathExtension == "stl" else { return nil }
                fractions.append(progress.fractionCompleted)
                XCTAssertFalse(progress.isFinished)
                if cancelOnImport { progress.cancel() }
                return try Geometry(csgString: "cube(1);", isCancelled: { false })
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for file in ["a.stl", "b.stl", "c.stl"] {
            try "delegate model".write(
                to: directory.appendingPathComponent(file), atomically: true, encoding: .utf8
            )
        }
        try "import(\"a.stl\"); import(\"b.stl\");".write(
            to: directory.appendingPathComponent("nested.csg"), atomically: true, encoding: .utf8
        )
        let source = "import(\"nested.csg\"); import(\"c.stl\");"
        let url = directory.appendingPathComponent("main.csg")
        try source.write(to: url, atomically: true, encoding: .utf8)

        for fromScript in [false, true] {
            let progress = EvaluationProgress()
            let delegate = Delegate(progress: progress)
            if fromScript {
                _ = try evaluate(
                    parse("import \"\(url.path)\""), delegate: delegate, progress: progress
                )
            } else {
                _ = try Scene(
                    csgString: source, at: url, delegate: delegate, progress: progress, isCancelled: { false }
                )
            }
            let total = fromScript ? 6.0 : 5.0
            XCTAssertEqual(delegate.fractions, [0, 1 / total, 3 / total])
            XCTAssertEqual(progress.fractionCompleted, 1)
            XCTAssertTrue(progress.isFinished)
        }

        let cancelled = EvaluationProgress()
        let delegate = Delegate(progress: cancelled)
        delegate.cancelOnImport = true
        XCTAssertThrowsError(try Scene(
            csgString: source, at: url, delegate: delegate, progress: cancelled, isCancelled: { false }
        )) { XCTAssertTrue($0 is CancellationError, String(describing: $0)) }
        XCTAssertEqual(delegate.fractions.count, 1)
        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertFalse(cancelled.isFinished)
    }

    func testCSGEvaluationProgressDoesNotFinishOnFailure() {
        let progress = EvaluationProgress()
        XCTAssertThrowsError(try Scene(csgString: "cube(", progress: progress, isCancelled: { false }))
        XCTAssertEqual(progress.fractionCompleted, 0)
        XCTAssertFalse(progress.isFinished)
    }

    func testModelImportsUseRelativePathsTransformsAndMaterials() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rootURL = directory.appendingPathComponent("main.csg")
        for ext in ["stl", "obj", "off"] {
            let url = directory.appendingPathComponent("part.\(ext)")
            try Mesh.cube(size: 2).write(to: url)
            let source = """
            color([1,0,0]) translate([10,0,0]) import("part.\(ext)", convexity=10);
            """
            try source.write(to: rootURL, atomically: true, encoding: .utf8)
            let scene = try Scene(csgString: source, at: rootURL, isCancelled: { false })
            XCTAssertTrue(scene.build { false })
            let mesh = scene.geometry.merged()
            XCTAssertEqual(mesh.signedVolume, 8, accuracy: 1e-6)
            XCTAssertEqual(mesh.bounds.center, Vector(10, 0, 0))
            func importedMeshes(in geometry: Geometry) -> [Geometry] {
                if case .mesh = geometry.type { return [geometry] }
                return geometry.children.flatMap { importedMeshes(in: $0) }
            }
            let imported = try XCTUnwrap(importedMeshes(in: scene.geometry).first)
            XCTAssertEqual(imported.material.color, .red)
        }
    }

    func testOFFImportsIgnoreVertexAttributesButKeepFaceColors() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rootURL = directory.appendingPathComponent("main.csg")
        let faceColor = Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.4)
        for ext in ["off", "coff"] {
            for faceMaterial: Color? in [nil, faceColor] {
                let mesh = try Mesh(Mesh.cube().polygons.map { polygon in
                    try XCTUnwrap(Polygon(
                        polygon.vertices.map {
                            $0.withColor($0.position.y > 0 ? .clear : .red).withNormal($0.position.normalized())
                        },
                        material: faceMaterial
                    ))
                })
                let url = directory.appendingPathComponent("part.\(ext)")
                try mesh.offString(options: .init(
                    vertexNormals: true, vertexColors: true, textureCoordinates: true
                )).write(to: url, atomically: true, encoding: .utf8)
                let source = "translate([2,0,0]) import(\"part.\(ext)\");"
                let context = EvaluationContext(source: source, fileURL: rootURL, delegate: nil)
                // Populate the shared import cache before loading the same mesh through CSG.
                guard case let .mesh(original) = try context.importFile(at: url, named: url.lastPathComponent) else {
                    return XCTFail("Expected a mesh import")
                }
                let geometry = try Geometry(csgString: source, at: rootURL, context: context)
                XCTAssertTrue(geometry.build { false })
                let imported = geometry.merged()
                XCTAssertEqual(imported.bounds.center, Vector(2, 0, 0))
                XCTAssertEqual(imported.signedVolume, 1, accuracy: 1e-6)
                XCTAssertTrue(imported.polygons.flatMap(\.vertices).allSatisfy { $0.color == .white })
                XCTAssertTrue(imported.polygons.flatMap(\.vertices).allSatisfy { $0.texcoord == .zero })
                XCTAssertTrue(imported.polygons.allSatisfy { polygon in
                    polygon.vertices.allSatisfy { $0.normal == polygon.plane.normal }
                })
                if let faceMaterial {
                    XCTAssertTrue(imported.polygons.allSatisfy { ($0.material as? Material)?.color == faceMaterial })
                } else {
                    XCTAssertTrue(imported.polygons.allSatisfy {
                        let color = ($0.material as? Material)?.color
                        return color == nil || color == .white
                    })
                }
                XCTAssertTrue(original.build { false })
                XCTAssertTrue(original.merged().hasVertexColors)
                XCTAssertTrue(original.merged().polygons.flatMap(\.vertices).contains { $0.texcoord != .zero })
                XCTAssertTrue(original.merged().polygons.contains { polygon in
                    polygon.vertices.contains { $0.normal != polygon.plane.normal }
                })
                XCTAssertTrue(original.merged().polygons.flatMap(\.vertices).contains { $0.color.alpha == 0 })
            }
        }
    }

    func testImportedMeshCanBeUsedAsSubtractionOperand() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Mesh.cube(size: 1).write(to: directory.appendingPathComponent("part.stl"))
        let source = """
        difference() {
            cube([2,2,2], center=true);
            import("part.stl");
        }
        """
        let url = directory.appendingPathComponent("main.csg")
        try source.write(to: url, atomically: true, encoding: .utf8)
        let cache = GeometryCache(diskCache: nil)
        for _ in 0 ..< 2 {
            let scene = try Scene(
                csgString: source, at: url,
                cache: cache, isCancelled: { false }
            )
            XCTAssertTrue(scene.build { false })
            XCTAssertEqual(scene.geometry.merged().signedVolume, 7, accuracy: 1e-6)
        }
    }

    func testNestedCSGImportsResolveRelativeToTheirOwnFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let subdirectory = directory.appendingPathComponent("parts", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Mesh.cube(size: 2).write(to: subdirectory.appendingPathComponent("part.stl"))
        try "import(\"part.stl\");".write(
            to: subdirectory.appendingPathComponent("nested.csg"), atomically: true, encoding: .utf8
        )
        let source = "import(\"parts/nested.csg\");"
        let rootURL = directory.appendingPathComponent("main.csg")
        try source.write(to: rootURL, atomically: true, encoding: .utf8)
        let scene = try Scene(csgString: source, at: rootURL, isCancelled: { false })
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(scene.geometry.merged().signedVolume, 8, accuracy: 1e-6)

        // The same chain must also work when entered from a ShapeScript import.
        let script = try evaluate(
            parse("import \"\(rootURL.path)\""), delegate: nil
        )
        XCTAssertTrue(script.build { false })
        XCTAssertEqual(script.geometry.merged().signedVolume, 8, accuracy: 1e-6)
    }

    func testCSGImportsUseDelegateAndReuseLoadedGeometry() throws {
        final class Delegate: EvaluationDelegate {
            var imports = [URL]()
            var denyAccess = false
            func resolveURL(for path: String) -> URL { URL(fileURLWithPath: path) }
            func importGeometry(for url: URL) throws -> Geometry? {
                imports.append(url)
                if denyAccess {
                    throw RuntimeErrorType.fileAccessRestricted(for: url.path, at: url.deletingLastPathComponent())
                }
                return try Geometry(csgString: "cube(1);", isCancelled: { false })
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let partURL = directory.appendingPathComponent("part.stl")
        try "loaded by delegate".write(to: partURL, atomically: true, encoding: .utf8)
        let rootURL = directory.appendingPathComponent("main.csg")
        let source = """
        import("part.stl");
        translate([2,0,0]) import("part.stl");
        """
        try source.write(to: rootURL, atomically: true, encoding: .utf8)
        let delegate = Delegate()
        let scene = try Scene(csgString: source, at: rootURL, delegate: delegate, isCancelled: { false })
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(scene.geometry.merged().signedVolume, 2, accuracy: 1e-6)
        XCTAssertEqual(delegate.imports, [partURL])

        delegate.denyAccess = true
        XCTAssertThrowsError(try Scene(csgString: source, at: rootURL, delegate: delegate, isCancelled: { false })) {
            XCTAssertEqual(ProgramError($0).type, .fileAccess)
        }
    }

    func testImportedCSGProfilesCanBeExtrudedAndForwardWarnings() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "roof() square(2);".write(
            to: directory.appendingPathComponent("profile.csg"), atomically: true, encoding: .utf8
        )
        let rootURL = directory.appendingPathComponent("main.csg")
        let source = "linear_extrude(height=3) import(\"profile.csg\");"
        try source.write(to: rootURL, atomically: true, encoding: .utf8)
        let scene = try Scene(csgString: source, at: rootURL, isCancelled: { false })
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(scene.geometry.merged().signedVolume, 12, accuracy: 1e-6)
        XCTAssertEqual(scene.warnings, [
            "profile.csg: Unsupported CSG operation 'roof' on line 1.",
        ])
    }

    func testCSGImportFailuresRemainErrorsWithSourceLocations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rootURL = directory.appendingPathComponent("main.csg")
        for name in ["unsupported.foo", "unsupported.dxf", "script.shape"] {
            try "not a model".write(
                to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8
            )
        }
        for name in ["unsupported.foo", "unsupported.dxf", "script.shape", "missing.stl"] {
            let source = "\nimport(\"\(name)\");"
            try source.write(to: rootURL, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try Scene(csgString: source, at: rootURL, isCancelled: { false })) {
                let error = ProgramError($0)
                XCTAssertTrue(error.message.contains(name), error.message)
                XCTAssertTrue(error.messageAndLocation(with: source).contains("on line 2"))
                if name == "missing.stl" {
                    XCTAssertTrue(error.message.contains("not found"))
                } else {
                    XCTAssertTrue(
                        error.hint?.contains("unsupported") == true ||
                            error.hint?.contains("not supported") == true,
                        error.hint ?? "Missing hint"
                    )
                }
            }
        }
    }

    func testCircularCSGImportsAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("loop.csg")
        let source = "import(\"loop.csg\");"
        try source.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Scene(csgString: source, at: url, isCancelled: { false })) {
            XCTAssertTrue(ProgramError($0).message.contains("Circular import"), String(describing: $0))
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
        try "cube([1,2]);".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try evaluate(
            parse("import \"part.csg\""),
            delegate: TestDelegate(directory: directory)
        )) { error in
            let error = ProgramError(error)
            XCTAssertTrue(error.message.contains("Expected a CSG vector with 3 components"))
            XCTAssertEqual(error.shapeFileURL(relativeTo: directory.appendingPathComponent("main.shape")), url)
        }
    }

    func testImportedErrorsPointToTheOriginalCSGFileAndRange() throws {
        final class Delegate: EvaluationDelegate {
            let directory: URL
            init(directory: URL) {
                self.directory = directory
            }

            func resolveURL(for path: String) -> URL {
                path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path)
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("part.CSG")
        try "\n\nimport \"part.CSG\"".write(
            to: directory.appendingPathComponent("parent.shape"),
            atomically: true,
            encoding: .utf8
        )
        let mainURL = directory.appendingPathComponent("main.shape")
        for badLine in ["cubee(1);", "cube(size=\"big\");", "@"] {
            let csgSource = "// 🐱\n\n    \(badLine)"
            try csgSource.write(to: fileURL, atomically: true, encoding: .utf8)
            for script in ["\nimport \"part.CSG\"", "\nimport \"parent.shape\""] {
                XCTAssertThrowsError(try evaluate(parse(script), delegate: Delegate(directory: directory))) {
                    let error = ProgramError($0)
                    XCTAssertEqual(error.type, .evaluation)
                    XCTAssertEqual(error.shapeFileURL(relativeTo: mainURL), fileURL, String(reflecting: error))
                    guard let (range, source) = error.rangeAndSource(with: script) else {
                        return XCTFail("Missing imported error range")
                    }
                    XCTAssertEqual(source, csgSource)
                    let position = source.lineAndColumn(at: range.lowerBound)
                    XCTAssertEqual(position.line, 3)
                    XCTAssertEqual(position.column, 5)
                    XCTAssertTrue(error.messageAndLocation(with: script).contains("on line 3"))
                }
            }
        }
    }
}
