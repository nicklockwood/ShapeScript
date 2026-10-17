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
            "resize([1,2]) cube(1);", "resize([1,2,3], auto=\"yes\") cube(1);",
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
            csgString: "union() { resize([4,4,4]) cube(2,true); surface(file=\"missing.dat\"); }",
            isCancelled: { false }
        )
        XCTAssertEqual(scene.warnings.count, 2)
        XCTAssertTrue(scene.warnings.contains { $0.contains("geometry skipped") })
        XCTAssertTrue(scene.warnings.contains { $0.contains("using children") })
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(scene.geometry.merged().signedVolume, 8, accuracy: 1e-8)
    }

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
                "Unsupported CSG operation 'roof'; using children without this operation (line 1, column 1)"
            )
            XCTAssertEqual(scene.geometry, expected.geometry)
            XCTAssertTrue(scene.build { false })
        }
        let empty = try Scene(csgString: "roof(); cube(1);", isCancelled: { false })
        XCTAssertTrue(empty.warnings.contains { $0.contains("geometry skipped") })
        XCTAssertTrue(empty.build { false })
        XCTAssertEqual(empty.geometry.merged().signedVolume, 1, accuracy: 1e-8)
    }

    func testUnsupportedExtrusionOptionsHaveExplicitFallbacks() throws {
        let tapered = try Scene(csgString: "linear_extrude(height=2, scale=0.5) square(1);", isCancelled: { false })
        XCTAssertEqual(tapered.warnings.count, 1)
        XCTAssertTrue(tapered.warnings[0].contains("untapered"))
        XCTAssertTrue(tapered.build { false })
        XCTAssertEqual(tapered.geometry.merged().signedVolume, 2, accuracy: 1e-8)
        let partial = try Scene(
            csgString: "rotate_extrude(angle=90, start=30, $fn=16) translate([2,0,0]) square(1);",
            isCancelled: { false }
        )
        XCTAssertEqual(partial.warnings.count, 1)
        XCTAssertTrue(partial.warnings[0].contains("full revolution"))
        XCTAssertTrue(partial.build { false })
        XCTAssertEqual(partial.geometry.merged(), try mesh("rotate_extrude($fn=16) translate([2,0,0]) square(1);"))
    }

    func testUnsupportedOffsetOptionsHaveExplicitFallbacks() throws {
        let rounded = try Scene(csgString: "offset(r=1, chamfer=true) square(2,true);", isCancelled: { false })
        XCTAssertEqual(rounded.warnings.count, 1)
        XCTAssertTrue(rounded.warnings[0].contains("sharp offset"))
        XCTAssertEqual(rounded.geometry.overestimatedBounds, Bounds([-2, -2, 0], [2, 2, 0]))
        let multiple = try Scene(
            csgString: "offset(delta=1) group() { square(1); translate([4,0,0]) square(1); }",
            isCancelled: { false }
        )
        XCTAssertTrue(multiple.warnings.contains { $0.contains("separately") })
        XCTAssertEqual(try XCTUnwrap(multiple.children.first?.path).subpaths.count, 2)
    }

    func testUnsupportedMatrixOptionsWarnWithoutLosingOtherGeometry() throws {
        let projective = try Scene(
            csgString: "multmatrix([[1,0,0,2],[0,1,0,0],[0,0,1,0],[0,0,0.1,1]]) cube(1);",
            isCancelled: { false }
        )
        XCTAssertTrue(projective.warnings.contains { $0.contains("affine part") })
        XCTAssertTrue(projective.build { false })
        XCTAssertEqual(projective.geometry.merged().bounds, Bounds([2, 0, 0], [3, 1, 1]))
        let singular = try Scene(csgString: "cube(1); scale([0,1,1]) cube(4);", isCancelled: { false })
        XCTAssertTrue(singular.warnings.contains { $0.contains("Singular") })
        XCTAssertTrue(singular.build { false })
        XCTAssertEqual(singular.geometry.merged().signedVolume, 1, accuracy: 1e-8)
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
            csgString: "cube(1); linear_extrude(height=1) projection() cube(1);",
            isCancelled: { false }
        )
        XCTAssertEqual(incompatible.warnings.count, 2)
        XCTAssertTrue(incompatible.build { false })
        XCTAssertEqual(incompatible.geometry.merged().signedVolume, 1, accuracy: 1e-8)
    }

    #if canImport(CoreText)
    func testUnsupportedTextOptionsWarnAndUseDefaults() throws {
        let source = "text(\"Hi\", font=\"Helvetica\", halign=\"center\", spacing=2, language=\"fr\");"
        let scene = try Scene(csgString: source, isCancelled: { false })
        XCTAssertEqual(scene.warnings.count, 1)
        XCTAssertFalse(scene.warnings[0].contains("halign"))
        XCTAssertTrue(scene.warnings[0].contains("spacing"))
        XCTAssertTrue(scene.warnings[0].contains("language"))
        XCTAssertTrue(scene.warnings[0].contains("line 1, column 1"))
        let fallback = try Scene(
            csgString: "text(\"Hi\", font=\"Helvetica\", halign=\"center\");",
            isCancelled: { false }
        )
        XCTAssertEqual(scene.geometry, fallback.geometry)
        XCTAssertTrue(fallback.warnings.isEmpty)
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
                    let geometry = try Geometry(
                        csgString: """
                        text("\(text)", size=3, font="Helvetica", $fn=32, halign="\(halign)", valign="\(valign)");
                        """,
                        onWarning: { XCTFail($0) },
                        isCancelled: { false }
                    )
                    let actual = Bounds(geometry.paths(pretransformed: true))
                    let expected = Bounds(original.translated(by: [x, y, 0]).scaled(by: 3))
                    XCTAssertEqual(actual.min.x, expected.min.x, accuracy: 1e-8)
                    XCTAssertEqual(actual.min.y, expected.min.y, accuracy: 1e-8)
                    XCTAssertEqual(actual.max.x, expected.max.x, accuracy: 1e-8)
                    XCTAssertEqual(actual.max.y, expected.max.y, accuracy: 1e-8)
                }
            }
        }
    }

    func testEmptyAlignedText() throws {
        for text in ["", "   "] {
            let geometry = try Geometry(
                csgString: "text(\"\(text)\", halign=\"center\", valign=\"center\");",
                onWarning: { XCTFail($0) },
                isCancelled: { false }
            )
            XCTAssertTrue(geometry.paths(pretransformed: true).allSatisfy(\.isEmpty))
        }
    }

    func testUnsupportedFontStyleWarnsAndUsesBaseFont() throws {
        let scene = try Scene(csgString: "text(\"Hi\", font=\"Helvetica:style=Bold\");", isCancelled: { false })
        XCTAssertEqual(scene.warnings.count, 1)
        XCTAssertTrue(scene.warnings[0].contains("base font"))
        let fallback = try Scene(csgString: "text(\"Hi\", font=\"Helvetica\");", isCancelled: { false })
        XCTAssertEqual(scene.geometry, fallback.geometry)
    }
    #endif

    func testNamedColorWarnsAndUsesInheritedColor() throws {
        let scene = try Scene(csgString: "color([1,0,0]) color(\"blue\") cube(1);", isCancelled: { false })
        XCTAssertEqual(scene.warnings.count, 1)
        XCTAssertTrue(scene.warnings[0].contains("inherited color"))
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
        try "color(\"red\") cube(1);".write(to: url, atomically: true, encoding: .utf8)
        let importStatement = "import \"warning.csg\""
        let delegate = TestDelegate(directory: directory)
        let scene = try evaluate(parse("group { \(importStatement) }\n\(importStatement)"), delegate: delegate)
        XCTAssertEqual(scene.warnings.count, 1)
        XCTAssertTrue(scene.warnings[0].hasPrefix("warning.csg:"))
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

    func testImportedGeometryUsesFlatNormals() throws {
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
            let mesh = try mesh(source)
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

    func test2DBooleansProducePathsAndExtrudeWithoutWarnings() throws {
        for (operation, area) in [("union", 6.0), ("difference", 2.0), ("intersection", 2.0)] {
            let source = "\(operation)() { square(2); translate([1,0,0]) square(2); }"
            var warnings = [String]()
            let geometry = try Geometry(csgString: source, onWarning: { warnings.append($0) }, isCancelled: { false })
            let path = try XCTUnwrap(geometry.path)
            XCTAssertTrue(path.isClosed)
            XCTAssertEqual(Mesh.fill(path, faces: .front).surfaceArea, area, accuracy: 1e-8)
            XCTAssertTrue(warnings.isEmpty, warnings.joined(separator: "\n"))
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
            let path = try XCTUnwrap(scene.children.first?.path)
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
            if let path = scene.children.first?.path {
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

    func testNonCoplanar2DHullAndMinkowskiWarn() throws {
        for operation in ["hull", "minkowski"] {
            let scene = try Scene(
                csgString: "\(operation)() { square(2); translate([0,0,1]) square(2); }", isCancelled: { false }
            )
            XCTAssertEqual(scene.warnings.count, 1)
            XCTAssertTrue(scene.warnings[0].contains("Non-coplanar 2D '\(operation)'"))
            XCTAssertEqual(try XCTUnwrap(scene.children.first?.path).subpaths.count, 2)
        }
    }

    func test2DBooleanHolesAndDisconnectedRegions() throws {
        let ring = "difference() { square(4,true); square(2,true); }"
        let geometry = try Geometry(csgString: ring, isCancelled: { false })
        XCTAssertEqual(try XCTUnwrap(geometry.path).subpaths.count, 2)
        XCTAssertEqual(try mesh("linear_extrude(height=2) \(ring)").signedVolume, 24, accuracy: 1e-8)
        XCTAssertEqual(
            try mesh("linear_extrude(height=1) union() { \(ring) square(2,true); }").signedVolume,
            16, accuracy: 1e-8
        )
        let disconnected = try Geometry(
            csgString: "union() { square(1); translate([3,0,0]) square(1); }", isCancelled: { false }
        )
        XCTAssertEqual(try XCTUnwrap(disconnected.path).subpaths.count, 2)
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
        XCTAssertEqual(try Mesh.fill(XCTUnwrap(tilted.path), faces: .front).surfaceArea, 6, accuracy: 1e-8)
        let mirrored =
            try mesh("linear_extrude(height=1) difference() { mirror([1,0,0]) square(4,true); square(2,true); }")
        XCTAssertEqual(mirrored.signedVolume, 12, accuracy: 1e-8)
    }

    func testNonCoplanar2DBooleansWarnAndKeepProfiles() throws {
        let scene = try Scene(
            csgString: "union() { square(2); translate([0,0,1]) square(2); }", isCancelled: { false }
        )
        XCTAssertEqual(scene.warnings.count, 1)
        XCTAssertTrue(scene.warnings[0].contains("Non-coplanar 2D 'union'"))
        let path = try XCTUnwrap(scene.children.first?.path)
        XCTAssertEqual(path.subpaths.count, 2)
        XCTAssertEqual(path.bounds.size, Vector(2, 2, 1))
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

    func testEvaluatedProfilesUseDeferredMeshCache() throws {
        let source = "linear_extrude(height=2) difference() { square(4,true); offset(delta=-0.5) square(4,true); }"
        let cache = GeometryCache(diskCache: nil)
        let scene = try Scene(csgString: source, cache: cache, isCancelled: { false })
        let geometry = try XCTUnwrap(scene.children.first?.children.first)
        guard case let .extrude(paths, _) = geometry.type else { return XCTFail("Expected extrusion") }
        XCTAssertFalse(paths.isEmpty)
        XCTAssertNil(geometry.mesh)
        XCTAssertEqual(cache.count, 0)
        let encoded = try JSONEncoder().encode(geometry.type)
        XCTAssertEqual(try JSONDecoder().decode(GeometryType.self, from: encoded), geometry.type)

        XCTAssertTrue(scene.build { false })
        let expected = try XCTUnwrap(geometry.mesh)
        let reload = try Scene(csgString: source, cache: cache, isCancelled: { false })
        let reloaded = try XCTUnwrap(reload.children.first?.children.first)
        XCTAssertEqual(geometry.cacheKey, reloaded.cacheKey)
        XCTAssertTrue(reload.build { false })
        XCTAssertEqual(reloaded.mesh, expected)
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
        XCTAssertNil(geometry.mesh)
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

    func testShearedProfileIsEvaluatedBeforeExtrusion() throws {
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
              !paths.isEmpty
        else {
            return XCTFail("Sheared profiles should be evaluated during import")
        }
        XCTAssertNil(geometry.mesh)
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
            "rotate_extrude($fn=16) translate([2,0,0]) square(1);",
            "cylinder(h=3, r1=2, r2=1, $fn=16);",
        ] {
            let cache = GeometryCache(diskCache: nil)
            let first = try Scene(csgString: source, cache: cache, isCancelled: { false })
            let geometry = try XCTUnwrap(first.children.first?.children.first)
            XCTAssertNil(geometry.mesh, source)
            XCTAssertEqual(cache.count, 0)
            XCTAssertTrue(first.build { false })
            XCTAssertGreaterThan(cache.count, 0)
            let second = try Scene(csgString: source, cache: cache, isCancelled: { false })
            let reloaded = try XCTUnwrap(second.children.first?.children.first)
            XCTAssertNil(reloaded.mesh, source)
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
            "rotate_extrude(angle=90) square(1);",
            "hull() { square(2); translate([0,0,1]) square(2); }",
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

            func debugLog(_: [AnyHashable]) {}
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
