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
        XCTAssertEqual(geometry.children.map { $0.path?.isClosed }, [true, true, true, true, false, false, false])
        let box = try XCTUnwrap(geometry.children.first?.path)
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
            let path = try XCTUnwrap(geometry.path)
            XCTAssertTrue(path.isClosed)
            XCTAssertEqual(path.bounds.size, [width, 2, 0], accuracy: 1e-8)
        }
        let geometry = try load(
            svg("<rect width=\"10\" height=\"20\" fill=\"none\" stroke-width=\"8\"/>"),
            options: .init(csg: true)
        )
        XCTAssertEqual(geometry.path?.bounds.size, [10, 20, 0])
    }

    func testCSGUnionsOverlappingElementsAndPreservesHoles() throws {
        let union = try load(
            svg("<rect width=\"10\" height=\"10\"/><rect x=\"5\" width=\"10\" height=\"10\"/>"),
            options: .init(csg: true)
        )
        XCTAssertEqual(union.path?.subpaths.count, 1)
        XCTAssertEqual(union.path?.bounds.size, [15, 10, 0])
        let hole = try load(svg("<path d=\"M0 0H10V10H0Z M2 2H8V8H2Z\"/>"), options: .init(csg: true))
        XCTAssertEqual(hole.path?.subpaths.count, 2)
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

    func testWarningsAreDeliveredAfterXMLParsing() throws {
        let inner = Data(svg("<rect width=\"1\" height=\"1\"/>").utf8)
        let outer = try SVGDocument(
            data: Data(svg("<text>Hello</text><image href=\"picture.png\"/>").utf8),
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
        let cases = [
            ("<svg>\n<g></svg>", "SVG opening and closing tags do not match"),
            ("<svg>\n<rect width=foo/></svg>", "SVG attribute values must be enclosed in quotes"),
            ("<svg>\n<g>", "Unexpected end of SVG document; a tag may be incomplete or missing its closing tag"),
            ("<svg>\n&bad;</svg>", "Unknown XML entity in SVG; use &amp; for a literal '&'"),
            ("<svg>\n<rect width=\"-1\" height=\"2\"/>\n</svg>", "SVG dimensions must be non-negative"),
        ]
        for (source, message) in cases {
            XCTAssertThrowsError(try load(source)) { error in
                XCTAssertEqual(error.localizedDescription, message + " on line 2.")
            }
            try withSVG(source) { url in
                XCTAssertThrowsError(try evaluate(parse("import \"\(url.path)\""), delegate: nil)) { error in
                    let error = ProgramError(error)
                    XCTAssertEqual(
                        error.messageAndLocation(with: ""),
                        "Error in imported file 'drawing.svg': " + message + " on line 2."
                    )
                    XCTAssertEqual(error.rangeAndSource(with: "")?.source, source)
                    XCTAssertEqual(error.errorLineAndRange(with: "")?.line, String(source.split(separator: "\n")[1]))
                    XCTAssertEqual(error.shapeFileURL(relativeTo: url.deletingLastPathComponent()), url)
                }
                let csg = "import(file=\"\(url.path)\");"
                XCTAssertThrowsError(try Scene(csgString: csg, isCancelled: { false })) { error in
                    let error = ProgramError(error)
                    XCTAssertEqual(error.underlyingError.message, message)
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
            XCTAssertFalse(try XCTUnwrap(named["edge"]?.path).isClosed)
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
        XCTAssertEqual(SVGFileReference("drawing.svg#part%20one").id, "part one")
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
                try counts.append(XCTUnwrap(scene.geometry.children.first?.path).points.count)
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
            for selection in ["file=\"\(url.path)#missing\"", "file=\"\(url.path)\", id=\"missing\""] {
                let script = String(repeating: "\n", count: 11) + "import(\(selection));"
                XCTAssertThrowsError(try Scene(csgString: script, isCancelled: { false })) { error in
                    XCTAssertEqual(
                        ProgramError(error).messageAndLocation(with: script),
                        "SVG element '#missing' not found in file 'drawing.svg' on line 12."
                    )
                }
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
        XCTAssertEqual(SVGFileReference("drawing#1.svg").path, "drawing#1.svg")
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
