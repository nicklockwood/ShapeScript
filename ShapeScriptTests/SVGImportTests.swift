//
//  SVGImportTests.swift
//  ShapeScriptTests
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

@testable import Euclid
@testable import ShapeScript
import Foundation
import XCTest

final class SVGImportTests: XCTestCase {
    private func svg(
        _ body: String,
        attributes: String = "width=\"100mm\" height=\"100mm\" viewBox=\"0 0 100 100\""
    ) -> String {
        "<svg xmlns=\"http://www.w3.org/2000/svg\" \(attributes)>\(body)</svg>"
    }

    private func load(_ source: String, options: SVGImportOptions = .init()) throws -> Geometry {
        try SVGDocument(data: Data(source.utf8), isCancelled: { false }).geometry(
            options: options, isCancelled: { false }, warn: { _, _ in }
        )
    }

    private func withSVG(_ source: String, _ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("drawing.svg")
        try source.write(to: url, atomically: true, encoding: .utf8)
        try body(url)
    }

    func testPrimitiveShapesAndOpenPaths() throws {
        let geometry = try load(svg("""
        <rect id="box" x="10" y="20" width="30" height="40"/>
        <circle id="circle" cx="50" cy="50" r="5"/>
        <ellipse id="ellipse" cx="20" cy="30" rx="4" ry="2"/>
        <polygon id="polygon" points="0,0 10,0 10,10"/>
        <polyline id="polyline" points="0,0 10,0 10,10"/>
        <line id="line" x1="2" y1="3" x2="5" y2="7"/>
        <path id="curve" d="M 0 0 C 0 10 10 10 10 0"/>
        """))
        XCTAssertEqual(
            geometry.children.map(\.name),
            ["box", "circle", "ellipse", "polygon", "polyline", "line", "curve"]
        )
        XCTAssertEqual(geometry.children.map { $0.path()?.isClosed }, [true, true, true, true, false, false, false])
        let box = try XCTUnwrap(geometry.children.first?.path())
        XCTAssertEqual(box.bounds.min, [10, 40, 0])
        XCTAssertEqual(box.bounds.max, [40, 80, 0])
    }

    func testGroupNamesAndSelectionPreserveAncestorTransforms() throws {
        let source = svg("""
        <g id="assembly" transform="translate(10 20)">
          <g id="part" transform="scale(2)"><rect id="box" width="3" height="4"/></g>
          <circle id="other" r="2"/>
        </g>
        """)
        let geometry = try load(source, options: .init(id: "box"))
        XCTAssertEqual(geometry.name, "box")
        XCTAssertTrue(geometry.children.isEmpty)
        XCTAssertEqual(geometry.transform, .identity)
        let group = try load(source, options: .init(id: "part"))
        XCTAssertEqual(group.name, "part")
        XCTAssertEqual(group.children.map(\.name), ["box"])
        XCTAssertEqual(Bounds(group.paths(pretransformed: true)), Bounds(geometry.paths(pretransformed: true)))
        let document = try load(source)
        XCTAssertEqual(document.children.first?.name, "assembly")
        XCTAssertEqual(document.children.first?.children.first?.name, "part")
        let paths = geometry.paths(pretransformed: true)
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(Bounds(paths).min, [10, 72, 0])
        XCTAssertEqual(Bounds(paths).max, [16, 80, 0])
        XCTAssertEqual(try load(source, options: .init(id: "assembly")).paths(pretransformed: true).count, 2)
    }

    func testMatricesSkewAndTransformOrder() throws {
        let geometry = try load(svg("""
        <path d="M1 2 L3 4" transform="translate(10 20) scale(2 3) skewX(45)"/>
        """))
        let path = try XCTUnwrap(geometry.paths(pretransformed: true).first)
        XCTAssertEqual(try XCTUnwrap(path.points.first?.position), [16, 74, 0], accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(path.points.last?.position), [24, 68, 0], accuracy: 1e-8)
    }

    func testUseResolvesForwardReferencesWithoutRenderingDefinitions() throws {
        let source = svg("""
        <use id="instance" href="#part" x="10" y="20"/>
        <defs><g id="part"><rect width="3" height="4"/></g></defs>
        """)
        let geometry = try load(source)
        XCTAssertEqual(geometry.children.map(\.name), ["instance"])
        XCTAssertEqual(Bounds(geometry.paths(pretransformed: true)).min, [10, 76, 0])
        XCTAssertEqual(Bounds(geometry.paths(pretransformed: true)).max, [13, 80, 0])
        let selected = try load(source, options: .init(id: "part"))
        XCTAssertEqual(selected.name, "part")
        XCTAssertEqual(selected.paths(pretransformed: true).count, 1)
        let instance = try load(source, options: .init(id: "instance"))
        XCTAssertEqual(instance.name, "instance")
        XCTAssertEqual(instance.children.first?.name, "part")
        XCTAssertEqual(Bounds(instance.paths(pretransformed: true)).min, [10, 76, 0])
    }

    func testCircularUseFails() {
        XCTAssertThrowsError(try load(svg("<defs><g id=\"a\"><use href=\"#a\"/></g></defs><use href=\"#a\"/>")))
    }

    func testPhysicalUnitsViewBoxAndAspectRatio() throws {
        let source = svg(
            "<rect width=\"100\" height=\"100\"/>",
            attributes: "width=\"2in\" height=\"1in\" viewBox=\"0 0 100 100\""
        )
        let bounds = try Bounds(load(source).paths(pretransformed: true))
        XCTAssertEqual(bounds.min, [12.7, 0, 0], accuracy: 1e-8)
        XCTAssertEqual(bounds.max, [38.1, 25.4, 0], accuracy: 1e-8)
        let stretched = source.replacingOccurrences(of: "<svg ", with: "<svg preserveAspectRatio=\"none\" ")
        XCTAssertEqual(try Bounds(load(stretched).paths(pretransformed: true)).size, [50.8, 25.4, 0], accuracy: 1e-8)
    }

    func testDPIAndCentering() throws {
        let source = svg(
            "<rect x=\"20\" y=\"10\" width=\"40\" height=\"20\"/>",
            attributes: "width=\"100\" height=\"100\" viewBox=\"0 0 100 100\""
        )
        let a = try Bounds(load(source, options: .init(dpi: 100)).paths(pretransformed: true))
        let b = try Bounds(load(source, options: .init(center: true, dpi: 200)).paths(pretransformed: true))
        XCTAssertEqual(a.size, b.size * 2, accuracy: 1e-8)
        XCTAssertEqual(b.center, .zero, accuracy: 1e-8)
    }

    func testCSGStrokesOpenPathsAndIgnoresClosedShapeStyling() throws {
        for (cap, width) in [("butt", 10.0), ("square", 12.0), ("round", 12.0)] {
            let geometry = try load(
                svg("<path d=\"M10 10 L20 10\" stroke-width=\"2\" stroke-linecap=\"\(cap)\"/>"),
                options: .init(csg: true)
            )
            let path = try XCTUnwrap(geometry.path())
            XCTAssertTrue(path.isClosed)
            XCTAssertEqual(path.bounds.size, [width, 2, 0], accuracy: 1e-8)
        }
        let geometry = try load(
            svg("<rect width=\"10\" height=\"20\" fill=\"none\" stroke-width=\"8\"/>"),
            options: .init(csg: true)
        )
        XCTAssertEqual(geometry.path()?.bounds.size, [10, 20, 0])
    }

    func testCSGUnionsOverlappingElementsAndPreservesHoles() throws {
        let union = try load(
            svg("<rect width=\"10\" height=\"10\"/><rect x=\"5\" width=\"10\" height=\"10\"/>"),
            options: .init(csg: true)
        )
        XCTAssertEqual(union.path()?.subpaths.count, 1)
        XCTAssertEqual(union.path()?.bounds.size, [15, 10, 0])
        let hole = try load(svg("<path d=\"M0 0H10V10H0Z M2 2H8V8H2Z\"/>"), options: .init(csg: true))
        XCTAssertEqual(hole.path()?.subpaths.count, 2)
    }

    func testRoundedRectAndAllPathCommands() throws {
        let source = svg("""
        <rect id="rounded" width="10" height="20" rx="2" ry="3"/>
        <path d="M10 10 h5 v5 l5 0 q5 5 10 0 t10 0 c5 5 5 5 10 0 s5 -5 10 0 a5 3 30 0 1 10 0 z"/>
        """)
        let paths = try load(source).paths(pretransformed: true)
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths.allSatisfy(\.isClosed))
        XCTAssertGreaterThan(paths[0].points.count, 8)
    }

    #if canImport(CoreText)
    func testTextPositionSizeAndOrientation() throws {
        let original = try Bounds(load(svg("<text font-family=\"Helvetica\" font-size=\"10\">H</text>"))
            .paths(pretransformed: true))
        let moved =
            try Bounds(
                load(
                    svg("<text x=\"20\" y=\"30\" dx=\"2\" dy=\"3\" font-family=\"Helvetica\" font-size=\"10\">H</text>")
                )
                .paths(pretransformed: true)
            )
        XCTAssertGreaterThan(original.size.x, 0)
        XCTAssertGreaterThan(original.max.y, 100)
        XCTAssertEqual(moved.min, original.min + Vector(22, -33, 0), accuracy: 1e-8)
        let doubled = try Bounds(load(svg("<text font-family=\"Helvetica\" font-size=\"20\">H</text>"))
            .paths(pretransformed: true))
        XCTAssertEqual(doubled.size, original.size * 2, accuracy: 1e-8)
    }

    func testTextAnchoringAndStyledSpans() throws {
        func bounds(_ anchor: String) throws -> Bounds {
            try Bounds(load(svg("<text font-size=\"10\" text-anchor=\"\(anchor)\">Hello</text>"))
                .paths(pretransformed: true))
        }
        let start = try bounds("start"), middle = try bounds("middle"), end = try bounds("end")
        XCTAssertEqual(start.size, middle.size, accuracy: 1e-8)
        XCTAssertEqual(middle.min.x - end.min.x, start.min.x - middle.min.x, accuracy: 1e-8)
        XCTAssertLessThan(end.min.x, start.min.x)
        let plain = try load(svg("<text font-size=\"10\">AB&amp;C</text>")).paths(pretransformed: true)
        let spans = try load(svg("<text font-size=\"10\">A<tspan>B</tspan>&amp;<![CDATA[C]]></text>"))
            .paths(pretransformed: true)
        XCTAssertEqual(plain, spans)
        let styled =
            try load(
                svg("<text font-size=\"10\">A<tspan style=\"font-size: 200%; font-weight: bold\">B</tspan>C</text>")
            )
            .paths(pretransformed: true)
        XCTAssertGreaterThan(Bounds(styled).size.y, Bounds(plain).size.y)
    }

    func testTextWhitespaceVisibilityAndZeroSize() throws {
        let plain = try load(svg("<text font-size=\"10\">AB C</text>")).paths(pretransformed: true)
        let whitespace = try load(svg("<text font-size=\"10\">  A\nB  <tspan>C</tspan> </text>"))
            .paths(pretransformed: true)
        XCTAssertEqual(plain, whitespace)
        let hidden = try load(svg("<text font-size=\"10\">AB<tspan display=\"none\">hidden</tspan> C</text>"))
            .paths(pretransformed: true)
        XCTAssertEqual(plain, hidden)
        XCTAssertTrue(try load(svg("<text font-size=\"0\">Hidden</text>")).paths(pretransformed: true)
            .allSatisfy(\.isEmpty))
        XCTAssertThrowsError(try load(svg("<text font-size=\"-1\">Invalid</text>")))
    }

    func testPositionedTextSpansPreserveLineLayout() throws {
        let source = """
        <svg viewBox="0 0 500 160">
            <text x="24" y="36" font-size="24">
              <tspan x="24" dy="0">First line</tspan>
              <tspan x="24" dy="32" fill="#dc2626" font-weight="700">
                Second line in red
              </tspan>
            </text>
        </svg>
        """
        let expected = """
        <svg viewBox="0 0 500 160">
          <text x="24" y="36" font-size="24">First line</text>
          <text x="24" y="68" font-size="24" font-weight="700">Second line in red</text>
        </svg>
        """
        let document = try SVGDocument(data: Data(source.utf8), isCancelled: { false })
        var warnings = [String]()
        let result = try document.geometry(options: .init(), isCancelled: { false }) { message, _ in
            warnings.append(message)
        }
        let actual = result.paths(pretransformed: true).flatMap(\.subpaths)
        let reference = try load(expected).paths(pretransformed: true).flatMap(\.subpaths)
        XCTAssertEqual(actual, reference)
        XCTAssertTrue(warnings.isEmpty, warnings.joined(separator: "\n"))
    }

    func testTextSpanRelativePositionsAndContinuation() throws {
        let baseline = try load(svg("<text font-family=\"Helvetica\" font-size=\"10\">ABC</text>"))
            .paths(pretransformed: true).flatMap(\.subpaths)
        let moved =
            try load(
                svg("<text font-family=\"Helvetica\" font-size=\"10\">A<tspan dx=\"5\" dy=\"12\">B</tspan>C</text>")
            )
            .paths(pretransformed: true).flatMap(\.subpaths)
        XCTAssertEqual(moved.count, baseline.count)
        XCTAssertEqual(Bounds(moved.suffix(1)).min.y, Bounds(baseline.suffix(1)).min.y - 12, accuracy: 1e-8)
        XCTAssertGreaterThan(Bounds(moved).size.x, Bounds(baseline).size.x)
        let absolute =
            try load(
                svg(
                    "<text font-size=\"10\"><tspan x=\"20\" y=\"30\">A</tspan><tspan x=\"40\" y=\"50\">B</tspan></text>"
                )
            )
            .paths(pretransformed: true).flatMap(\.subpaths)
        let expected =
            try load(
                svg(
                    "<text x=\"20\" y=\"30\" font-size=\"10\">A</text><text x=\"40\" y=\"50\" font-size=\"10\">B</text>"
                )
            )
            .paths(pretransformed: true).flatMap(\.subpaths)
        XCTAssertEqual(absolute, expected)
    }

    func testPositionedSpansAnchorEachLine() throws {
        for anchor in ["middle", "end"] {
            let actual =
                try load(
                    svg(
                        "<text font-size=\"10\" text-anchor=\"\(anchor)\"><tspan x=\"50\" y=\"20\">First</tspan><tspan x=\"50\" dy=\"20\">Second</tspan></text>"
                    )
                )
                .paths(pretransformed: true).flatMap(\.subpaths)
            let expected =
                try load(
                    svg(
                        "<text x=\"50\" y=\"20\" font-size=\"10\" text-anchor=\"\(anchor)\">First</text><text x=\"50\" y=\"40\" font-size=\"10\" text-anchor=\"\(anchor)\">Second</text>"
                    )
                )
                .paths(pretransformed: true).flatMap(\.subpaths)
            XCTAssertEqual(actual, expected)
        }
    }

    func testTextCoordinateAndRotationLists() throws {
        let source = """
        <svg viewBox="0 0 500 160">
            <text x="50 82 118 156" y="80" rotate="0 -10 8 0" font-size="42">
              SVG!
            </text>
            <text x="40" y="140" dx="0 5 0 -3" font-size="28">Adjusted glyphs</text>
        </svg>
        """
        let document = try SVGDocument(data: Data(source.utf8), isCancelled: { false })
        var warnings = [String]()
        let geometry = try document.geometry(options: .init(), isCancelled: { false }) { message, _ in
            warnings.append(message)
        }
        XCTAssertFalse(geometry.paths(pretransformed: true).isEmpty)
        XCTAssertTrue(warnings.isEmpty, warnings.joined(separator: "\n"))

        let actual =
            try load(svg("<text x=\"50 82 118 156\" y=\"80\" rotate=\"0 -10 8 0\" font-size=\"42\">SVG!</text>"))
                .paths(pretransformed: true).flatMap(\.subpaths)
        let expected = try load(svg("""
        <text x="50" y="80" font-size="42">S</text>
        <text x="82" y="80" font-size="42" transform="rotate(-10 82 80)">V</text>
        <text x="118" y="80" font-size="42" transform="rotate(8 118 80)">G</text>
        <text x="156" y="80" font-size="42">!</text>
        """)).paths(pretransformed: true).flatMap(\.subpaths)
        XCTAssertEqual(actual.count, expected.count)
        for (a, b) in zip(actual, expected) {
            XCTAssertEqual(a.points.count, b.points.count)
            for (p, q) in zip(a.points, b.points) {
                XCTAssertEqual(p.position, q.position, accuracy: 1e-8)
            }
        }
    }

    func testTextRelativeListsAccumulateAndThenExpire() throws {
        func paths(_ attributes: String) throws -> [Path] {
            try load(svg("<text font-family=\"Courier\" font-size=\"20\" \(attributes)>LLLLL</text>"))
                .paths(pretransformed: true).flatMap(\.subpaths)
        }
        let baseline = try paths("")
        let adjusted = try paths("dx=\"0, 5, 0, -3\" dy=\"0 2 -1\"")
        XCTAssertEqual(baseline.count, 5)
        XCTAssertEqual(adjusted.count, 5)
        let shifts = [Vector.zero, Vector(5, -2), Vector(5, -1), Vector(2, -1), Vector(2, -1)]
        for (index, pair) in zip(baseline, adjusted).enumerated() {
            XCTAssertEqual(Bounds(pair.1).min, Bounds(pair.0).min + shifts[index], accuracy: 1e-8)
        }
    }

    func testTextPositionListsContinueThroughNestedSpans() throws {
        let actual =
            try load(
                svg(
                    "<text x=\"10 20 30 40\" y=\"20 30 40 50\" font-size=\"10\">L<tspan x=\"100\">L<tspan>L</tspan></tspan>L</text>"
                )
            )
            .paths(pretransformed: true).flatMap(\.subpaths)
        let expected = try load(svg("""
        <text x="10" y="20" font-size="10">L</text>
        <text x="100" y="30" font-size="10">L</text>
        <text x="30" y="40" font-size="10">L</text>
        <text x="40" y="50" font-size="10">L</text>
        """)).paths(pretransformed: true).flatMap(\.subpaths)
        XCTAssertEqual(actual, expected)
    }

    func testTextRotationRepeatsAndPositionUnitsAreParsed() throws {
        let actual = try load(svg("<text x=\"1in, 30mm 120px\" y=\"20\" rotate=\"0 90\" font-size=\"10\">LLL</text>"))
            .paths(pretransformed: true).flatMap(\.subpaths)
        let expected = try load(svg("""
        <text x="96" y="20" font-size="10">L</text>
        <text x="30mm" y="20" font-size="10" transform="rotate(90 113.38582677165356 20)">L</text>
        <text x="120" y="20" font-size="10" transform="rotate(90 120 20)">L</text>
        """)).paths(pretransformed: true).flatMap(\.subpaths)
        XCTAssertEqual(actual.count, expected.count)
        for (a, b) in zip(actual, expected) {
            XCTAssertEqual(Bounds(a).min, Bounds(b).min, accuracy: 1e-8)
            XCTAssertEqual(Bounds(a).max, Bounds(b).max, accuracy: 1e-8)
        }
        for attributes in ["dx=\"0 nope\"", "x=\"1 2%\"", "rotate=\"0 nan\""] {
            XCTAssertThrowsError(try load(svg("<text \(attributes)>Invalid</text>")))
        }
    }

    func testTextFragmentAndTransforms() throws {
        try withSVG(svg(
            "<g transform=\"translate(10 20)\"><text id=\"label\" font-size=\"10\">Hello</text></g>"
        )) { url in
            let context = EvaluationContext(source: "", delegate: nil)
            guard case let .mesh(geometry) = try context.importFile(at: url.path + "#label") else {
                return XCTFail("Expected imported text geometry")
            }
            XCTAssertFalse(geometry.paths(pretransformed: true).isEmpty)
            let plain = try Bounds(load(svg("<text font-size=\"10\">Hello</text>")).paths(pretransformed: true))
            XCTAssertEqual(
                Bounds(geometry.paths(pretransformed: true)).min,
                plain.min + Vector(10, -20, 0),
                accuracy: 1e-8
            )
        }
    }
    #endif

    func testCSGStillRejectsSVGText() throws {
        let document = try SVGDocument(
            data: Data(svg("<text>Hello</text><rect width=\"2\" height=\"3\"/>").utf8),
            isCancelled: { false }
        )
        var warnings = [String]()
        let geometry = try document.geometry(options: .init(csg: true), isCancelled: { false }) { message, _ in
            warnings.append(message)
        }
        XCTAssertEqual(warnings, ["Unsupported SVG element 'text'"])
        XCTAssertEqual(Bounds(geometry.paths(pretransformed: true)).size, [2, 3, 0])
    }

    func testSVGWarningsPreserveDistinctLocationsAndDeduplicateRepeatedImports() throws {
        try withSVG("""
        <svg>
          <image/><image/>
          <image/>
        </svg>
        """) { url in
            let context = EvaluationContext(source: "", delegate: nil)
            _ = try context.importFile(at: url.path)
            _ = try context.importFile(at: url.path)
            XCTAssertEqual(context.warnings, [
                "drawing.svg: Unsupported SVG element 'image' on line 2.",
                "drawing.svg: Unsupported SVG element 'image' on line 3.",
            ])
        }
    }

    #if canImport(CoreText)
    func testSVGFontWarningsOnlyAfterExhaustingFallbacks() throws {
        try withSVG("""
        <svg>
          <text font-family="MissingSVGFont123, serif">Fallback</text>
          <text font-family="MissingSVGFont123, MissingSVGFont456">Missing</text>
          <text font-family="MissingSVGFont123, MissingSVGFont456">Also missing</text>
        </svg>
        """) { url in
            let context = EvaluationContext(source: "", delegate: nil)
            _ = try context.importFile(at: url.path)
            XCTAssertEqual(context.warnings, [
                "drawing.svg: Unknown SVG font 'MissingSVGFont123, MissingSVGFont456' on line 3.",
                "drawing.svg: Unknown SVG font 'MissingSVGFont123, MissingSVGFont456' on line 4.",
            ])
        }
    }
    #endif

    func testClippingClosedAndOpenPaths() throws {
        let source = svg("""
        <defs><clipPath id="clip"><rect x="2" y="3" width="4" height="5"/></clipPath></defs>
        <rect width="10" height="10" clip-path="url(#clip)"/>
        <path d="M0 5H10" style="clip-path: url('#clip')"/>
        """)
        let paths = try load(source).paths(pretransformed: true)
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths[0].isClosed)
        XCTAssertEqual(Bounds(paths[0]).min, [2, 92, 0], accuracy: 1e-8)
        XCTAssertEqual(Bounds(paths[0]).size, [4, 5, 0], accuracy: 1e-8)
        XCTAssertFalse(paths[1].isClosed)
        XCTAssertEqual(paths[1].points.map(\.position), [Vector(2, 95), Vector(6, 95)])
    }

    func testClipChildrenUnionAndClipRuleHoles() throws {
        func area(_ definition: String) throws -> Double {
            let paths =
                try load(
                    svg(
                        "<defs><clipPath id=\"clip\">\(definition)</clipPath></defs><rect width=\"10\" height=\"10\" clip-path=\"url(#clip)\"/>"
                    )
                )
                .paths(pretransformed: true)
            return Mesh.fill(Path(subpaths: paths), faces: .front).surfaceArea
        }
        XCTAssertEqual(
            try area("<rect width=\"6\" height=\"6\"/><rect x=\"4\" width=\"6\" height=\"6\"/>"),
            60,
            accuracy: 1e-8
        )
        XCTAssertEqual(try area("<path d=\"M0 0H10V10H0Z M2 2H8V8H2Z\"/>"), 100, accuracy: 1e-8)
        XCTAssertEqual(try area("<path clip-rule=\"evenodd\" d=\"M0 0H10V10H0Z M2 2H8V8H2Z\"/>"), 64, accuracy: 1e-8)
        XCTAssertEqual(try area("<path d=\"M0 0H10V10H0Z M2 2V8H8V2Z\"/>"), 64, accuracy: 1e-8)
        XCTAssertEqual(try area("<path d=\"M0 0H10V10H0\"/>"), 100, accuracy: 1e-8)
    }

    func testClipTransformsUseReferencesAndNestedClips() throws {
        let source = svg("""
        <defs>
          <rect id="shape" width="8" height="8"/>
          <clipPath id="inner"><rect width="5" height="5"/></clipPath>
          <clipPath id="outer" transform="translate(1 2)" clip-path="url(#inner)">
            <use href="#shape" x="2"/>
          </clipPath>
        </defs>
        <g transform="translate(10 20) scale(2)">
          <rect width="10" height="10" clip-path="url(#outer)"/>
        </g>
        """)
        let bounds = try Bounds(load(source).paths(pretransformed: true))
        XCTAssertEqual(bounds.min, [16, 66, 0], accuracy: 1e-8)
        XCTAssertEqual(bounds.size, [6, 10, 0], accuracy: 1e-8)
    }

    func testGroupObjectBoundingBoxClipPreservesFragmentContext() throws {
        let source = svg("""
        <defs><clipPath id="clip" clipPathUnits="objectBoundingBox"><rect width="0.5" height="1"/></clipPath></defs>
        <g id="group" transform="translate(10 20)" clip-path="url(#clip)">
          <rect id="first" width="8" height="10"/>
          <rect id="second" x="8" width="12" height="10"/>
        </g>
        """)
        let all = try Bounds(load(source).paths(pretransformed: true))
        XCTAssertEqual(all.min, [10, 70, 0], accuracy: 1e-8)
        XCTAssertEqual(all.size, [10, 10, 0], accuracy: 1e-8)
        let selected = try load(source, options: .init(id: "second"))
        XCTAssertEqual(Bounds(selected.paths(pretransformed: true)).min, [18, 70, 0], accuracy: 1e-8)
        XCTAssertEqual(Bounds(selected.paths(pretransformed: true)).size, [2, 10, 0], accuracy: 1e-8)
    }

    func testAncestorClipCannotBeDisabledByChild() throws {
        let source = svg("""
        <clipPath id="clip"><rect width="5" height="5"/></clipPath>
        <g clip-path="url(#clip)"><rect width="10" height="10" clip-path="none"/></g>
        """)
        XCTAssertEqual(try Bounds(load(source).paths(pretransformed: true)).size, [5, 5, 0], accuracy: 1e-8)
    }

    func testBoundingBoxClipsIgnoreDegenerateBoundsAndInheritClipRules() throws {
        let source = svg("""
        <defs clip-rule="evenodd">
          <clipPath id="hole"><path d="M0 0H10V10H0Z M2 2H8V8H2Z"/></clipPath>
          <clipPath id="box" clipPathUnits="objectBoundingBox"><rect width="0.5" height="1"/></clipPath>
        </defs>
        <rect width="10" height="10" clip-path="url(#hole)"/>
        <path d="M0 20H10" clip-path="url(#box)"/>
        """)
        let paths = try load(source).paths(pretransformed: true)
        XCTAssertEqual(Mesh.fill(paths[0], faces: .front).surfaceArea, 64, accuracy: 1e-8)
        XCTAssertEqual(paths[1].length, 10, accuracy: 1e-8)
    }

    func testEmptyAndHiddenClipShapesRemoveGeometry() throws {
        for definition in ["", "<rect width=\"10\" height=\"10\" display=\"none\"/>"] {
            let source =
                svg(
                    "<clipPath id=\"clip\">\(definition)</clipPath><rect width=\"10\" height=\"10\" clip-path=\"url(#clip)\"/>"
                )
            XCTAssertTrue(try load(source).paths(pretransformed: true).allSatisfy(\.isEmpty))
        }
    }

    func testClipReferencesWarnOrRejectCycles() throws {
        let document = try SVGDocument(data: Data(svg("""
        <rect width="10" height="10" clip-path="url(#missing)"/>
        <rect width="10" height="10" clip-path="url(other.svg#clip)"/>
        """).utf8), isCancelled: { false })
        var warnings = [String]()
        let geometry = try document.geometry(options: .init(), isCancelled: { false }) { message, _ in
            warnings.append(message)
        }
        XCTAssertEqual(warnings.count, 2)
        XCTAssertEqual(Bounds(geometry.paths(pretransformed: true)).size, [10, 10, 0])
        XCTAssertThrowsError(try load(svg("""
        <clipPath id="a" clip-path="url(#b)"><rect width="10" height="10"/></clipPath>
        <clipPath id="b" clip-path="url(#a)"><rect width="10" height="10"/></clipPath>
        <rect width="10" height="10" clip-path="url(#a)"/>
        """)))
    }

    func testCSGClippingRemainsUnsupported() throws {
        let source = svg("""
        <defs><clipPath id="clip"><rect width="5" height="5"/></clipPath></defs>
        <rect width="10" height="10" clip-path="url(#clip)"/>
        """)
        let document = try SVGDocument(data: Data(source.utf8), isCancelled: { false })
        var warnings = [String]()
        let geometry = try document.geometry(options: .init(csg: true), isCancelled: { false }) { message, _ in
            warnings.append(message)
        }
        XCTAssertEqual(warnings, ["SVG clipping and masking are not supported"])
        XCTAssertEqual(Bounds(geometry.paths(pretransformed: true)).size, [10, 10, 0])
    }

    #if canImport(CoreText)
    func testTextCanBeClippedAndUsedAsClipGeometry() throws {
        let source = svg("""
        <clipPath id="clip"><rect x="0" y="0" width="3" height="100"/></clipPath>
        <text x="0" y="30" font-size="20" clip-path="url(#clip)">Hello</text>
        """)
        let paths = try load(source).paths(pretransformed: true)
        XCTAssertFalse(paths.allSatisfy(\.isEmpty))
        XCTAssertLessThanOrEqual(Bounds(paths).max.x, 3 + 1e-8)
        let textClip = try load(svg("""
        <clipPath id="clip"><text y="30" font-size="20">Hello</text></clipPath>
        <rect width="100" height="100" clip-path="url(#clip)"/>
        """)).paths(pretransformed: true)
        let text = try load(svg("<text y=\"30\" font-size=\"20\">Hello</text>")).paths(pretransformed: true)
        XCTAssertEqual(Bounds(textClip).size, Bounds(text).size, accuracy: 1e-8)
    }
    #endif

    func testWarningsAreDeliveredAfterXMLParsing() throws {
        let inner = Data(svg("<rect width=\"1\" height=\"1\"/>").utf8)
        let outer = try SVGDocument(
            data: Data(svg("<foreignObject/><image href=\"picture.png\"/>").utf8),
            isCancelled: { false }
        )
        var messages = [String]()
        _ = try outer.geometry(options: .init(), isCancelled: { false }) { message, _ in
            messages.append(message)
            do {
                _ = try SVGDocument(data: inner, isCancelled: { false })
            } catch {
                XCTFail("Nested parse after completion failed: \(error)")
            }
        }
        XCTAssertEqual(messages.count, 2)
    }

    func testXMLSyntaxErrorsHaveReadableMessagesAndOriginalLineNumbers() throws {
        let cases: [(String, String, String?)] = [
            ("<svg>\n<g></svg>", "SVG opening and closing tags do not match", nil),
            ("<svg>\n<rect width=foo/></svg>", "SVG attribute values must be enclosed in quotes", nil),
            ("<svg>\n<g>", "Unexpected end of SVG document", "A tag may be incomplete or missing its closing tag."),
            ("<svg>\n&bad;</svg>", "Unknown XML entity in SVG", "Use &amp; for a literal '&'."),
            ("<svg>\n&amp </svg>", "Invalid XML entity in SVG", "Use &amp; for a literal '&'."),
            ("<svg>\n<rect width=\"-1\" height=\"2\"/>\n</svg>", "SVG dimensions must be non-negative", nil),
        ]
        for (source, message, hint) in cases {
            XCTAssertThrowsError(try load(source)) { error in
                XCTAssertEqual(error.localizedDescription, message + " on line 2.")
                XCTAssertEqual((error as? LocalizedError)?.recoverySuggestion, hint)
            }
            try withSVG(source) { url in
                XCTAssertThrowsError(try evaluate(parse("import \"\(url.path)\""), delegate: nil)) { error in
                    let error = ProgramError(error)
                    XCTAssertEqual(
                        error.messageAndLocation(with: ""),
                        "Error in imported file 'drawing.svg': " + message + " on line 2."
                    )
                    XCTAssertEqual(error.hint, hint)
                    XCTAssertEqual(error.rangeAndSource(with: "")?.source, source)
                    XCTAssertEqual(error.errorLineAndRange(with: "")?.line, String(source.split(separator: "\n")[1]))
                    XCTAssertEqual(error.shapeFileURL(relativeTo: url.deletingLastPathComponent()), url)
                }
                let csg = "import(file=\"\(url.path)\");"
                XCTAssertThrowsError(try Scene(csgString: csg, isCancelled: { false })) { error in
                    let error = ProgramError(error)
                    XCTAssertEqual(error.underlyingError.message, message)
                    XCTAssertEqual(error.hint, hint)
                    XCTAssertEqual(error.rangeAndSource(with: csg)?.source, source)
                    XCTAssertEqual(error.errorLineAndRange(with: csg)?.line, String(source.split(separator: "\n")[1]))
                    XCTAssertEqual(error.shapeFileURL(relativeTo: url.deletingLastPathComponent()), url)
                }
            }
        }
        let deep = "<svg>" + String(repeating: "<g>", count: 256)
        XCTAssertThrowsError(try load(deep)) { error in
            XCTAssertEqual(error.localizedDescription, "SVG nesting is too deep on line 1.")
        }
    }

    func testMalformedSVGAndCancellation() {
        XCTAssertThrowsError(try load("<svg><path></svg>"))
        XCTAssertThrowsError(try load("<html/>"))
        XCTAssertThrowsError(try load(svg("<path d=\"Mwat\"/>")))
        XCTAssertThrowsError(try load(svg("<rect width=\"-1\" height=\"2\"/>")))
        XCTAssertThrowsError(try SVGDocument(data: Data(svg("").utf8), isCancelled: { true })) {
            XCTAssertTrue($0 is CancellationError)
        }
    }

    func testNativeImportFragmentsAndGeometryBuilders() throws {
        try withSVG(svg("<g id=\"part\"><rect width=\"3\" height=\"4\"/></g><line id=\"edge\" x2=\"5\"/>")) { url in
            for builder in ["fill", "extrude"] {
                let scene = try evaluate(parse("\(builder) import \"\(url.path)#part\""), delegate: nil)
                XCTAssertTrue(scene.build { false })
                XCTAssertFalse(scene.geometry.merged().isEmpty)
                XCTAssertEqual(scene.geometry.merged().bounds.size.x, 3, accuracy: 1e-8)
            }
            let scene = try evaluate(parse("import \"\(url.path)#edge\""), delegate: nil)
            var named = [String: Geometry]()
            scene.geometry.gatherNamedObjects(&named)
            XCTAssertNotNil(named["edge"])
            XCTAssertNil(named["part"])
            XCTAssertFalse(try XCTUnwrap(named["edge"]?.path()).isClosed)
        }
    }

    func testNativeImportsPreserveDocumentPositionsAndSelectedFragments() throws {
        try withSVG(svg("""
        <g transform="translate(10 20) scale(2)"><rect id="part" width="3" height="4"/></g>
        <rect x="50" y="60" width="10" height="20"/>
        """)) { url in
            let context = EvaluationContext(source: "", delegate: nil)
            for (suffix, size, center) in [
                ("", Vector(50, 60), Vector(35, 50)),
                ("#part", Vector(6, 8), Vector(13, 76)),
            ] {
                guard case let .mesh(geometry) = try context.importFile(at: url.path + suffix) else {
                    return XCTFail("Expected geometry")
                }
                let bounds = Bounds(geometry.paths(pretransformed: true))
                XCTAssertEqual(bounds.center, center, accuracy: 1e-8)
                XCTAssertEqual(bounds.size, size, accuracy: 1e-8)
                let scene = try evaluate(parse("fill import \"\(url.path)\(suffix)\""), delegate: nil)
                XCTAssertTrue(scene.build { false })
                XCTAssertEqual(scene.geometry.merged().bounds.center, center, accuracy: 1e-8)
            }
            guard case let .mesh(geometry) = try context.importFile(at: url, named: url.path) else {
                return XCTFail("Expected geometry")
            }
            XCTAssertEqual(Bounds(geometry.paths(pretransformed: true)).center, [35, 50, 0], accuracy: 1e-8)
            let csg = try Scene(csgString: "import(file=\"\(url.path)\", id=\"part\");", isCancelled: { false })
            XCTAssertTrue(csg.build { false })
            XCTAssertEqual(Bounds(csg.geometry.paths(pretransformed: true)).center, [13, 76, 0], accuracy: 1e-8)
        }
    }

    func testCSGImportSelectionAndExtrusion() throws {
        try withSVG(svg("<g id=\"part\"><rect width=\"3\" height=\"4\"/></g><circle r=\"20\"/>")) { url in
            let scene = try Scene(
                csgString: "linear_extrude(height=2) import(file=\"\(url.path)\", id=\"part\", center=true);",
                isCancelled: { false }
            )
            XCTAssertTrue(scene.build { false })
            let bounds = scene.geometry.merged().bounds
            XCTAssertEqual(bounds.size, [3, 4, 2], accuracy: 1e-8)
            XCTAssertEqual(bounds.center, [0, 0, 1], accuracy: 1e-8)
        }
    }

    func testSelectionCacheDoesNotMixFragmentsOrDetail() throws {
        try withSVG(svg("<rect id=\"a\" width=\"3\" height=\"4\"/><rect id=\"b\" width=\"6\" height=\"8\"/>")) { url in
            let context = EvaluationContext(source: "", delegate: nil)
            for (id, size) in [("a", Vector(3, 4)), ("b", Vector(6, 8)), ("a", Vector(3, 4))] {
                guard case let .mesh(geometry) = try context.importFile(at: url.path + "#" + id) else {
                    return XCTFail("Expected geometry")
                }
                XCTAssertEqual(geometry.overestimatedBounds.size, size)
            }
        }
    }

    func testSelectingGroupDoesNotRenderUnusedDefinitions() throws {
        let source = svg("""
        <g id="part">
          <defs><rect id="unused" width="100" height="100"/></defs>
          <rect width="3" height="4"/>
        </g>
        """)
        let geometry = try load(source, options: .init(id: "part"))
        XCTAssertEqual(geometry.paths(pretransformed: true).count, 1)
        XCTAssertEqual(geometry.overestimatedBounds.size, [3, 4, 0])
    }

    func testLayerSelectionAndEmptyDocuments() throws {
        let source = svg("""
        <g xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape" inkscape:label="Cut">
          <rect width="3" height="4"/>
        </g>
        <rect width="100" height="100"/>
        """)
        let geometry = try load(source, options: .init(layer: "Cut", csg: true))
        XCTAssertEqual(geometry.overestimatedBounds.size, [3, 4, 0])
        XCTAssertTrue(try load(svg(""), options: .init(csg: true)).paths(pretransformed: true).allSatisfy(\.isEmpty))
        XCTAssertEqual(ImportFileReference("drawing.svg#part%20one").id, "part one")
    }

    func testCSGWithoutViewBoxMatchesOpenSCADCoordinates() throws {
        // Verified against OpenSCAD's exported SVG: user coordinates remain unscaled.
        let geometry = try load(svg(
            "<rect x=\"10\" y=\"20\" width=\"30\" height=\"40\"/>",
            attributes: "width=\"100mm\" height=\"100mm\""
        ), options: .init(csg: true))
        XCTAssertEqual(geometry.overestimatedBounds.min, [10, 40, 0])
        XCTAssertEqual(geometry.overestimatedBounds.max, [40, 80, 0])
    }

    func testCSGTessellationUsesEachCircleRadius() throws {
        try withSVG(svg("<circle id=\"small\" r=\"1\"/><circle id=\"large\" r=\"10\"/>")) { url in
            var counts = [Int]()
            for id in ["small", "large"] {
                let scene = try Scene(
                    csgString: "import(file=\"\(url.path)\", id=\"\(id)\", $fa=1, $fs=1);",
                    isCancelled: { false }
                )
                try counts.append(XCTUnwrap(scene.geometry.children.first?.path()).points.count)
            }
            XCTAssertGreaterThan(counts[1], counts[0])
        }
    }

    func testMissingFragmentRaisesAnError() throws {
        let source = svg("<rect id=\"part\" width=\"3\" height=\"4\"/>")
        XCTAssertThrowsError(try load(source, options: .init(id: "missing"))) { error in
            XCTAssertEqual((error as? SVGImportError)?.message, "SVG element '#missing' not found")
        }
        try withSVG(source) { url in
            let script = String(repeating: "\n", count: 11) + "import \"\(url.path)#missing\""
            XCTAssertThrowsError(try evaluate(parse(script), delegate: nil)) { error in
                XCTAssertEqual(
                    ProgramError(error).messageAndLocation(with: script),
                    "SVG element '#missing' not found in file 'drawing.svg' on line 12."
                )
            }
            let csg = String(repeating: "\n", count: 11) + "import(file=\"\(url.path)\", id=\"missing\");"
            XCTAssertThrowsError(try Scene(csgString: csg, isCancelled: { false })) { error in
                XCTAssertEqual(
                    ProgramError(error).messageAndLocation(with: csg),
                    "SVG element '#missing' not found in file 'drawing.svg' on line 12."
                )
            }
        }
    }

    func testMisspelledFragmentsSuggestMatchingElementIDs() throws {
        try withSVG(svg("<g id=\"main\"><rect id=\"outline\" width=\"3\" height=\"4\"/></g>")) { url in
            for id in ["mai", "mian", "MAIN", "xyz"] {
                let expected = id == "xyz" ? nil : "Did you mean '#main'?"
                XCTAssertThrowsError(try evaluate(parse("import \"\(url.path)#\(id)\""), delegate: nil)) { error in
                    XCTAssertEqual(ProgramError(error).hint, expected)
                }
                XCTAssertThrowsError(try Scene(
                    csgString: "import(file=\"\(url.path)\", id=\"\(id)\");",
                    isCancelled: { false }
                )) { error in
                    XCTAssertEqual(ProgramError(error).hint, expected)
                }
            }
        }
    }

    func testCSGDoesNotInterpretFilenameFragments() throws {
        try withSVG(svg("<rect id=\"part\" width=\"3\" height=\"4\"/>")) { url in
            XCTAssertThrowsError(try Scene(
                csgString: "import(file=\"\(url.path)#part\");", isCancelled: { false }
            )) { error in
                guard case let .runtimeError(error) = ProgramError(error).underlyingError,
                      case .fileNotFound = error.type
                else { return XCTFail("Expected a missing file error, got \(error)") }
            }
        }
    }

    func testMissingSVGIsAnErrorNotATextureWarning() {
        XCTAssertThrowsError(try evaluate(parse("import \"/does-not-exist.svg#part\""), delegate: nil))
        XCTAssertEqual(ImportType(URL(fileURLWithPath: "/drawing.svg#part")), .svg)
        XCTAssertEqual(ImportFileReference("drawing#1.svg").path, "drawing#1.svg")
    }
}

private func XCTAssertEqual(
    _ lhs: Vector,
    _ rhs: Vector,
    accuracy: Double,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(lhs.x, rhs.x, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(lhs.y, rhs.y, accuracy: accuracy, file: file, line: line)
    XCTAssertEqual(lhs.z, rhs.z, accuracy: accuracy, file: file, line: line)
}
