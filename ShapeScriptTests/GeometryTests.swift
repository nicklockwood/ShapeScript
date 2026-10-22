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
    #if canImport(CoreText)
    func testTextLetterspacingIsAdditiveAndCanChangeBetweenLines() throws {
        let scene = try evaluate(parse("""
        text {
            font "Helvetica"
            letterspacing 0.2
            "WiW"
            letterspacing -0.1
            "WiW"
        }
        """), delegate: nil)
        let geometry = try XCTUnwrap(scene.children.first)
        guard case let .text(text) = geometry.type else {
            return XCTFail("Expected text geometry")
        }
        XCTAssertEqual(text.text.map(\.letterspacing), [0.2, -0.1])
        let normal = Path.text(
            text.text.map { TextValue(string: $0.string, font: $0.font) },
            detail: text.detail, isCancelled: { false }
        )
        XCTAssertEqual(text.paths.count, 6)
        for (index, pair) in zip(normal, text.paths).enumerated() {
            let (original, actual) = pair
            let spacing = index < 3 ? 0.2 : -0.1
            let shift = Double(index % 3) * spacing
            XCTAssertEqual(actual.bounds.min.x, original.bounds.min.x + shift, accuracy: 1e-8)
            XCTAssertEqual(actual.bounds.max.x, original.bounds.max.x + shift, accuracy: 1e-8)
            XCTAssertEqual(actual.bounds.min.y, original.bounds.min.y, accuracy: 1e-8)
            XCTAssertEqual(actual.bounds.max.y, original.bounds.max.y, accuracy: 1e-8)
        }
    }

    func testTextLetterspacingPreservesDefaultLayoutAndAffectsWrapping() {
        let original = TextValue(string: "WiWi WiWi", font: "Helvetica")
        let normal = Path.text([original], isCancelled: { false })
        var text = original
        text.letterspacing = 0
        XCTAssertEqual(Path.text([text], isCancelled: { false }), normal)
        let width = Bounds(normal).size.x + 0.1
        XCTAssertEqual(Path.text([text], width: width, isCancelled: { false }), normal)
        text.letterspacing = 0.3
        let wrapped = Path.text([text], width: width, isCancelled: { false })
        XCTAssertGreaterThan(Bounds(wrapped).size.y, Bounds(normal).size.y)
        XCTAssertLessThanOrEqual(Bounds(wrapped).size.x, width)
    }

    #endif

    func testTextLetterspacingSerializationAndValidation() throws {
        let text = TextValue(string: "Hello", letterspacing: 0.2)
        XCTAssertEqual(try JSONDecoder().decode(TextValue.self, from: JSONEncoder().encode(text)), text)
        let legacy = try JSONDecoder().decode(TextValue.self, from: Data(#"{"string":"Hello"}"#.utf8))
        XCTAssertNil(legacy.letterspacing)
        XCTAssertFalse(Value.text(TextValue(string: "Hello", letterspacing: .infinity)).isFinite)
        XCTAssertFalse(Value.text(TextValue(string: "Hello", letterspacing: .nan)).isFinite)
    }

    func testPathCSGContainersPreserveChildrenAndProduceProfiles() throws {
        for (operation, area) in [
            ("union", 6.0), ("difference", 2.0), ("intersection", 2.0),
            ("xor", 4.0), ("hull", 6.0), ("minkowski", 16.0),
        ] {
            let source = """
            \(operation) {
                square { size 2 }
                square {
                    size 2
                    position 1 0
                }
            }
            """
            let scene = try evaluate(parse(source), delegate: nil)
            let geometry = try XCTUnwrap(scene.children.first)
            XCTAssertEqual(geometry.children.map(\.type), [.square, .square])
            let path = try XCTUnwrap(geometry.path, operation)
            XCTAssertEqual(Mesh.fill(path, faces: .front).surfaceArea, area, accuracy: 1e-8, operation)
            XCTAssertFalse(geometry.hasMesh, operation)
            XCTAssertTrue(geometry.renderedChildren.isEmpty, operation)
            XCTAssertTrue(scene.build { false })
            XCTAssertTrue(try XCTUnwrap(geometry.mesh).isEmpty, operation)
            XCTAssertTrue(geometry.renderedChildren.isEmpty, operation)
            XCTAssertEqual(geometry.exactBounds(with: .identity), path.bounds)

            for builder in ["fill", "extrude"] {
                let built = try evaluate(parse("\(builder) { \(source) }"), delegate: nil)
                let parent = try XCTUnwrap(built.children.first)
                XCTAssertEqual(parent.children.first?.type, geometry.type)
                XCTAssertTrue(built.build { false })
                let mesh = built.geometry.merged()
                if builder == "fill" {
                    XCTAssertEqual(mesh.surfaceArea, area * 2, accuracy: 1e-8, operation)
                } else {
                    XCTAssertEqual(mesh.signedVolume, area, accuracy: 1e-8, operation)
                    XCTAssertTrue(mesh.isWatertight)
                }
            }
        }
    }

    func testInsetPathOperationsMatchesInsetOfResult() throws {
        for operation in ["union", "difference", "intersection", "xor", "hull", "minkowski"] {
            let profile = """
            \(operation) {
                position 3 4
                size 2 3
                square { size 4 }
                square { size 2 }
            }
            """
            let scene = try evaluate(parse(profile), delegate: nil)
            let geometry = try XCTUnwrap(scene.children.first)
            let path = try XCTUnwrap(geometry.path(pretransformed: true))
            let expected = path.inset(by: 0.1)
            let inset = try evaluate(parse("inset (\(profile)) 0.1"), delegate: nil)
            let result = try XCTUnwrap(inset.children.first?.path(pretransformed: true), operation)
            XCTAssertEqual(result.bounds, expected.bounds, operation)
            XCTAssertEqual(
                Mesh.fill(result, faces: .front).surfaceArea,
                Mesh.fill(expected, faces: .front).surfaceArea,
                accuracy: 1e-8, operation
            )
        }
    }

    func testNestedPathOperationCacheInvalidationAndCancellation() throws {
        let scene = try evaluate(parse("""
        union {
            difference {
                square { size 4 }
                square { size 2 }
            }
            square { position 6 0 }
        }
        """), delegate: nil)
        let geometry = try XCTUnwrap(scene.children.first).transformed(by: .identity)
        final class CancellationState: @unchecked Sendable {
            private let lock = NSLock()
            private var checks = 0

            func isCancelled() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                checks += 1
                return checks > 3
            }
        }
        let cancellation = CancellationState()
        XCTAssertNil(geometry.path(pretransformed: false, isCancelled: {
            cancellation.isCancelled()
        }))
        func area() throws -> Double {
            try Mesh.fill(XCTUnwrap(geometry.path), faces: .front).surfaceArea
        }
        XCTAssertEqual(try area(), 13, accuracy: 1e-8)
        geometry.children[0].children[1].isHidden = true
        XCTAssertEqual(try area(), 17, accuracy: 1e-8)
        geometry.children[0].children[1].isHidden = false
        XCTAssertEqual(try area(), 13, accuracy: 1e-8)
    }

    func testPathGroupsKeepChildrenIndividuallySelectable() throws {
        let scene = try evaluate(parse("""
        group {
            circle { name "circle" }
            difference {
                name "frame"
                square { size 4 }
                square { size 2 }
            }
        }
        """), delegate: nil)
        let group = try XCTUnwrap(scene.children.first)
        XCTAssertEqual(scene.geometry.renderedChildren, [group])
        XCTAssertEqual(group.renderedChildren, group.children)
        XCTAssertTrue(group.children.allSatisfy { $0.isRenderedInScene(focus: false) })
        XCTAssertTrue(group.children[1].renderedChildren.isEmpty)
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(group.renderedChildren, group.children)
    }

    #if canImport(CoreText)
    func testPathOperationsUnionOverlappingTextGlyphs() throws {
        let scene = try evaluate(parse("""
        union {
            text {
                font "Helvetica"
                letterspacing -0.3
                "HH"
            }
        }
        """), delegate: nil)
        let geometry = try XCTUnwrap(scene.children.first)
        let text = try XCTUnwrap(geometry.children.first)
        let glyphs = text.paths(pretransformed: true)
        XCTAssertEqual(glyphs.count, 2)
        let expected = try XCTUnwrap(Path.union(glyphs))
        let actual = try XCTUnwrap(geometry.path)
        XCTAssertEqual(
            Mesh.fill(actual, faces: .front).surfaceArea,
            Mesh.fill(expected, faces: .front).surfaceArea,
            accuracy: 1e-8
        )
    }
    #endif

    func testPathCSGGroupsAreSingleFilledOperands() throws {
        for (operation, area) in [("difference", 4.0), ("intersection", 2.0)] {
            let scene = try evaluate(parse("""
            extrude {
                \(operation) {
                    group {
                        square { size 2 }
                        square {
                            size 2
                            position 1 0
                        }
                    }
                    square {
                        size 1 2
                        position 1.5 0
                    }
                }
            }
            """), delegate: nil)
            XCTAssertTrue(scene.build { false })
            XCTAssertEqual(scene.geometry.merged().signedVolume, area, accuracy: 1e-8, operation)
        }
    }

    func testPathMinkowskiUsesFilledRegions() throws {
        let scene = try evaluate(parse("""
        extrude {
            minkowski {
                square { size 4 }
                square
            }
        }
        """), delegate: nil)
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(scene.geometry.merged().signedVolume, 25, accuracy: 1e-8)
    }

    func testPathCSGCacheTracksHiddenChildren() throws {
        let scene = try evaluate(parse("difference { square { size 4 }\nsquare { size 2 } }"), delegate: nil)
        let geometry = try XCTUnwrap(scene.children.first)
        let cutter = geometry.children[1]
        func area() throws -> Double {
            try Mesh.fill(XCTUnwrap(geometry.path), faces: .front).surfaceArea
        }
        XCTAssertEqual(try area(), 12, accuracy: 1e-8)
        cutter.isHidden = true
        XCTAssertEqual(try area(), 16, accuracy: 1e-8)
        cutter.isHidden = false
        XCTAssertEqual(try area(), 12, accuracy: 1e-8)
        geometry.children[0].isHidden = true
        XCTAssertEqual(try area(), 0, accuracy: 1e-8)
    }

    func testCoplanarHullSupportsOpenPathsAndPoints() throws {
        let sources = [
            ("path { point 0 0; point 2 0; point 2 1 }\npoint 0 1", 2.0),
            ("group { path { point 0 0; point 2 0 }; path { point 2 1; point 0 1 } }", 2.0),
            ("point 1 0.5; point 0 0; point 2 1; point 2 0; point 0 1", 2.0),
            ("square\npoint 1.5 0", 1.5),
        ]
        for (body, area) in sources {
            let source = "hull {\n\(body.replacingOccurrences(of: ";", with: "\n"))\n}"
            let scene = try evaluate(parse(source), delegate: nil)
            let geometry = try XCTUnwrap(scene.children.first)
            let path = try XCTUnwrap(geometry.path, body)
            XCTAssertTrue(path.isClosed, body)
            XCTAssertFalse(geometry.hasMesh, body)
            XCTAssertEqual(Mesh.fill(path, faces: .front).surfaceArea, area, accuracy: 1e-8, body)
            let extrusion = try evaluate(parse("extrude " + source), delegate: nil)
            XCTAssertTrue(extrusion.build { false })
            XCTAssertEqual(extrusion.geometry.merged().signedVolume, area, accuracy: 1e-8, body)
        }
        let tilted = try evaluate(parse("""
        hull {
            path { point 0 0 0; point 2 0 2 }
            point 2 1 2
            point 0 1 0
        }
        """.replacingOccurrences(of: ";", with: "\n")), delegate: nil)
        let path = try XCTUnwrap(tilted.children.first?.path)
        XCTAssertEqual(Mesh.fill(path, faces: .front).surfaceArea, sqrt(8), accuracy: 1e-8)
    }

    func testHullOfCollinearPointsProducesOpenPath() throws {
        let scene = try evaluate(parse("""
        hull {
            point 1 2 3
            point 2 4 6
            point 0 0 0
        }
        """), delegate: nil)
        let path = try XCTUnwrap(scene.children.first?.path)
        XCTAssertFalse(path.isClosed)
        XCTAssertEqual(path.bounds, Bounds(min: .zero, max: [2, 4, 6]))
        XCTAssertEqual(path.length, sqrt(56), accuracy: 1e-8)
    }

    func testNonCoplanarPointHullStillProducesMesh() throws {
        let scene = try evaluate(parse("""
        hull {
            point 0 0 0
            point 1 0 0
            point 0 1 0
            point 0 0 1
        }
        """), delegate: nil)
        XCTAssertNil(scene.children.first?.path)
        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(scene.geometry.merged().signedVolume, 1.0 / 6, accuracy: 1e-8)
    }

    func testRawPathHullRetainsItsProfileChild() throws {
        let scene = try evaluate(parse("hull { path { square } }"), delegate: nil)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertEqual(geometry.type, .hull([]))
        XCTAssertEqual(geometry.children.count, 1)
        XCTAssertNotNil(geometry.children.first?.path)
        XCTAssertNotNil(geometry.path)
        XCTAssertEqual(geometry.path?.faceNormal, geometry.children.first?.path?.faceNormal)
    }

    func testDefinedPathCSGProfilesRetainTheirOperations() throws {
        let scene = try evaluate(parse("""
        define profile {
            difference {
                square { size 4 }
                square { size 2 }
            }
        }
        extrude profile { position 2 3 }
        """), delegate: nil)
        let extrusion = try XCTUnwrap(scene.children.first)
        XCTAssertEqual(extrusion.children.first?.type, .difference)
        XCTAssertTrue(scene.build { false })
        let mesh = scene.geometry.merged()
        XCTAssertEqual(mesh.signedVolume, 12, accuracy: 1e-8)
        XCTAssertEqual(mesh.bounds.center, [2, 3, 0])
    }

    func testNonCoplanarAndMixedHullsStillProduceMeshes() throws {
        for source in [
            "hull { square\nsquare { position 0 0 1 } }",
            "hull { square\ncube }",
        ] {
            let scene = try evaluate(parse(source), delegate: nil)
            let geometry = try XCTUnwrap(scene.children.first)
            XCTAssertNil(geometry.path)
            XCTAssertTrue(scene.build { false })
            XCTAssertFalse(try XCTUnwrap(geometry.mesh).isEmpty)
            XCTAssertTrue(geometry.hasMesh)
        }
    }

    func testPathCSGTransformsColoursAndEmptyResults() throws {
        let scene = try evaluate(parse("""
        color red
        difference {
            position 3 4 5
            orientation 0.2 0.3 0.1
            square { size 4 }
            square { size 2 }
        }
        """), delegate: nil)
        let geometry = try XCTUnwrap(scene.children.first)
        let local = try XCTUnwrap(geometry.path)
        XCTAssertEqual(local.subpaths.count, 2)
        XCTAssertTrue(local.points.allSatisfy { $0.color == .red })
        XCTAssertEqual(geometry.path(pretransformed: true), local.transformed(by: geometry.transform))
        XCTAssertNil(geometry.path(pretransformed: true, isCancelled: { true }))
        let empty = try evaluate(parse("intersection { square\nsquare { position 3 0 } }"), delegate: nil)
        XCTAssertTrue(try XCTUnwrap(empty.children.first?.path).isEmpty)
    }

    func testSceneGeometryHasStableIdentityAndParents() throws {
        let scene = try evaluate(parse("group { cube\nsphere }"), delegate: nil)
        let root = scene.geometry
        let group = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(scene.geometry === root)
        XCTAssertTrue(group.parent === root)
        XCTAssertTrue(group.children.allSatisfy { $0.parent === group })
        XCTAssertTrue(scene.build { false })
        XCTAssertTrue(scene.geometry === root)
        XCTAssertTrue(group.parent === root)

        let zUpScene = scene.with(zUp: true)
        XCTAssertTrue(zUpScene.geometry === root)
        XCTAssertTrue(zUpScene.children.first === group)
        XCTAssertTrue(group.parent === root)
    }

    func testCameraDimensionsUseIntegerPixels() throws {
        let scene = try evaluate(parse("camera { width 80.6\nheight 40.4 }"), delegate: nil)
        let camera = try XCTUnwrap(scene.cameras.first?.camera)
        XCTAssertEqual(camera.width, 81)
        XCTAssertEqual(camera.height, 40)
        XCTAssertEqual(try JSONDecoder().decode(Camera.self, from: JSONEncoder().encode(camera)), camera)
        XCTAssertNil(Camera.default.width)
        XCTAssertNil(Camera.default.height)
    }

    func testCameraDimensionsRejectOutOfRangeValues() throws {
        for dimension in ["width", "height"] {
            let source = "camera { \(dimension) 1000000000000000000000000000000 }"
            XCTAssertThrowsError(try evaluate(parse(source), delegate: nil)) { error in
                XCTAssertEqual((error as? RuntimeError)?.message, "Camera \(dimension) is out of range")
            }
        }
    }

    func testTextPathInitializationSupportsCancellation() {
        #if canImport(CoreText)
        nonisolated(unsafe) var cancellationChecks = 0
        let text = TextPath(text: [TextValue(string: "Hello")], wrapWidth: nil, detail: 2) {
            cancellationChecks += 1
            return true
        }
        XCTAssertGreaterThan(cancellationChecks, 0)
        XCTAssertTrue(text.paths.isEmpty)
        #endif
    }

    func testNamedPathsAndPrimitivesPreserveGeometry() throws {
        let primitives = [
            ("path", "square"),
            ("circle", ""),
            ("square", ""),
            ("text", "\"Hello\""),
            ("roundrect", "radius 0.1"),
            ("svgpath", "\"M0 0 L1 0 L1 1 Z\""),
            ("arc", "angle 0.5"),
            ("polygon", "sides 6"),
            ("polygon", "point 0 0\npoint 1 0\npoint 0 1"),
        ]
        for (primitive, body) in primitives {
            let source = "\(primitive) {\nposition 2 3\nsize 2\n\(body)\n}"
            let namedSource = "\(primitive) {\nname \"profile\"\nposition 2 3\nsize 2\n\(body)\n}"
            let scene = try evaluate(parse(namedSource), delegate: nil)
            let geometry = try XCTUnwrap(scene.children.first, primitive)
            XCTAssertEqual(scene.children.count, 1, primitive)
            XCTAssertEqual(geometry.name, "profile", primitive)
            XCTAssertTrue(geometry.children.isEmpty, primitive)
            for builder in ["", "fill ", "extrude "] {
                // Point-based polygons are faces, not extrusion profiles.
                if body.hasPrefix("point"), !builder.isEmpty { continue }
                let unnamedSource = body.hasPrefix("point") ? "mesh {\n\(source)\n}" : builder + source
                let unnamed = try evaluate(parse(unnamedSource), delegate: nil)
                let named = try evaluate(parse(builder + namedSource), delegate: nil)
                let expected = try XCTUnwrap(unnamed.children.first)
                let actual = try XCTUnwrap(named.children.first)
                XCTAssertTrue(expected.build { false })
                XCTAssertTrue(actual.build { false })
                XCTAssertEqual(named.geometry.merged(), unnamed.geometry.merged(), primitive)
            }
        }
    }

    func testPathPrimitivesSurviveDefinitions() throws {
        for primitive in ["circle", "square", "text \"Hello\""] {
            let direct = try evaluate(parse(primitive), delegate: nil)
            let expectedType = try XCTUnwrap(direct.children.first?.type)
            let directScene = try evaluate(parse("extrude \(primitive)"), delegate: nil)
            let directExtrusion = try XCTUnwrap(directScene.children.first)
            XCTAssertTrue(directExtrusion.build { false })
            let expectedMesh = try XCTUnwrap(directExtrusion.mesh)
            #if canImport(CoreText)
            XCTAssertFalse(expectedMesh.isEmpty, primitive)
            #else
            // Text paths are empty on platforms without CoreText.
            XCTAssertEqual(expectedMesh.isEmpty, primitive == "text \"Hello\"", primitive)
            #endif
            for definition in ["define profile \(primitive)", "define profile { \(primitive) }"] {
                let scene = try evaluate(parse("\(definition)\nextrude profile"), delegate: nil)
                let extrusion = try XCTUnwrap(scene.children.first)
                XCTAssertEqual(extrusion.children.map(\.type), [expectedType])
                XCTAssertTrue(extrusion.build { false })
                XCTAssertEqual(extrusion.mesh, expectedMesh, definition)
            }
        }
    }

    func testPathBuildersPreserveAndBuildPrimitivesConsistently() throws {
        for builder in ["fill", "extrude", "lathe"] {
            for primitive in ["circle", "square", "text \"Hello\""] {
                let scene = try evaluate(parse("\(builder) \(primitive)"), delegate: nil)
                let geometry = try XCTUnwrap(scene.children.first)
                let child = try XCTUnwrap(geometry.children.first)
                XCTAssertEqual(geometry.children.count, 1)
                XCTAssertNotNil(child.path)
                let paths = child.paths(pretransformed: true)
                let expectedType: GeometryType = switch builder {
                case "fill": .fill(paths)
                case "extrude": .extrude(paths, .default)
                default: .lathe(paths, .init(segments: 16))
                }
                let context = EvaluationContext(source: "", delegate: nil)
                let expected = Geometry(type: expectedType, in: context)
                XCTAssertTrue(geometry.build { false })
                XCTAssertTrue(expected.build { false })
                XCTAssertEqual(geometry.mesh?.bounds, expected.mesh?.bounds)
                XCTAssertEqual(geometry.volume { false }, expected.volume { false }, accuracy: 0.000001)
                let bounds = geometry.exactBounds(with: .identity)
                let expectedBounds = expected.exactBounds(with: .identity)
                XCTAssertEqual(bounds.min, expectedBounds.min, accuracy: epsilon)
                XCTAssertEqual(bounds.max, expectedBounds.max, accuracy: epsilon)
            }
        }
    }

    func testExtrusionBuildsMixedPrimitiveAndExplicitPaths() throws {
        let scene = try evaluate(parse("""
        extrude {
            square { position -2 0 }
            circle
            path {
                point 2 0
                point 3 0
                point 3 1
                point 2 1
                point 2 0
            }
        }
        """), delegate: nil)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        XCTAssertEqual(geometry.mesh?.bounds.min, [-2.5, -0.5, -0.5])
        XCTAssertEqual(geometry.mesh?.bounds.max, [3, 1, 0.5])
        XCTAssertGreaterThan(geometry.volume { false }, 2.7)
    }

    // MARK: Render progress

    func testRenderProgressDoesNotReportCompleteUntilFinished() {
        let progress = RenderProgress(
            phase: .buildingLeaves,
            completedUnitCount: 10,
            totalUnitCount: 10,
            isFinished: false,
            isCancelled: false
        )

        XCTAssertEqual(progress.fractionCompleted, 0.98)

        progress.finish()

        XCTAssertEqual(progress.fractionCompleted, 1)
    }

    func testRenderProgressCancellationPersistsAcrossTracking() {
        let progress = RenderProgress()
        progress.cancel()

        progress.beginTracking(totalUnitCount: 1, isCancelled: { false })
        XCTAssertTrue(progress.isCancelled)

        progress.endTracking()
        XCTAssertTrue(progress.isCancelled)
    }

    func testRenderProgressDoesNotCountCheckpointsTwice() {
        let progress = RenderProgress()
        progress.beginTracking(totalUnitCount: 100, isCancelled: { false })
        _ = progress.completeUnit(.buildingLeaves, by: 10)
        _ = progress.beginUnit(.buildingFinal, unitCount: 20)

        for _ in 0 ..< 5 {
            _ = progress.checkpoint(.buildingFinal)
        }
        XCTAssertEqual(progress.fractionCompleted, 0.15)

        _ = progress.completeUnit(.buildingFinal, by: 20)
        XCTAssertEqual(progress.fractionCompleted, 0.3)
    }

    func testRenderProgressCancellationChecksDoNotAdvanceProgress() {
        let progress = RenderProgress()
        progress.beginTracking(totalUnitCount: 100, isCancelled: { false })
        _ = progress.beginUnit(.buildingFinal, unitCount: 50)
        let isCancelled: CancellationHandler = { progress.isCancelled }

        for _ in 0 ..< 10 {
            XCTAssertFalse(isCancelled())
        }
        XCTAssertEqual(progress.fractionCompleted, 0)

        _ = progress.completeUnit(.buildingFinal, by: 50)
        XCTAssertEqual(progress.fractionCompleted, 0.5)
    }

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
        XCTAssertTrue(cube.isRenderedInScene(focus: false))
        XCTAssertTrue(sphere.isRenderedInScene(focus: false))
    }

    func testDifferenceRendersFirstChildForPreview() throws {
        let scene = try evaluate(parse("""
        difference {
            cube
            sphere
        }
        """), delegate: nil)

        let difference = try XCTUnwrap(scene.children.first)
        let cube = try XCTUnwrap(difference.children.first)
        let sphere = try XCTUnwrap(difference.children.last)

        XCTAssertNil(difference.mesh)
        XCTAssertTrue(cube.isRenderedInScene(focus: false))
        XCTAssertFalse(sphere.isRenderedInScene(focus: false))
    }

    func testMeshBooleanOperandsBuildWithoutPreviewMesh() {
        for type in [GeometryType.difference, .stencil] {
            let operand = Geometry(
                type: .mesh(.cube(size: 0.5)), name: nil, transform: .identity,
                material: .default, smoothing: nil, children: [], sourceLocation: nil
            )
            let base = Geometry(
                type: .cube, name: nil, transform: .identity,
                material: .default, smoothing: nil, children: [], sourceLocation: nil
            )
            let geometry = Geometry(
                type: type, name: nil, transform: .identity,
                material: .default, smoothing: nil, children: [base, operand], sourceLocation: nil
            )
            XCTAssertNil(operand.mesh)
            XCTAssertTrue(geometry.build { false })
            XCTAssertNotNil(operand.mesh)
            XCTAssertEqual(
                geometry.merged().signedVolume,
                type == .difference ? 0.875 : 1,
                accuracy: 1e-6
            )
        }
    }

    func testUnionRendersChildrenForPreview() throws {
        let scene = try evaluate(parse("""
        union {
            cube
            sphere
        }
        """), delegate: nil)

        let union = try XCTUnwrap(scene.children.first)
        let cube = try XCTUnwrap(union.children.first)
        let sphere = try XCTUnwrap(union.children.last)

        XCTAssertNil(union.mesh)
        XCTAssertTrue(cube.isRenderedInScene(focus: false))
        XCTAssertTrue(sphere.isRenderedInScene(focus: false))
    }

    func testHiddenGeometryIsNotRenderedInScene() throws {
        let scene = try evaluate(parse("""
        cube
        hide sphere
        """), delegate: nil)

        let cube = try XCTUnwrap(scene.children.first)
        let sphere = try XCTUnwrap(scene.children.last)

        XCTAssertFalse(cube.isHidden)
        XCTAssertTrue(sphere.isHidden)
        XCTAssertTrue(cube.isRenderedInScene(focus: false))
        XCTAssertFalse(sphere.isRenderedInScene(focus: false))
    }

    func testHiddenFocusedGeometryIsNotRenderedInScene() throws {
        let scene = try evaluate(parse("""
        hide focus cube
        sphere
        """), delegate: nil)

        let cube = try XCTUnwrap(scene.children.first)
        let sphere = try XCTUnwrap(scene.children.last)

        XCTAssertTrue(cube.isHidden)
        XCTAssertTrue(cube.isFocused)
        XCTAssertFalse(scene.geometry.childIsFocused)
        XCTAssertFalse(cube.isRenderedInScene(focus: false))
        XCTAssertTrue(sphere.isRenderedInScene(focus: false))
    }

    func testHiddenUnionChildIsRemovedFromResult() throws {
        let scene = try evaluate(parse("""
        union {
            cube {
                position -10
            }
            hide cube {
                position 10
            }
        }
        """), delegate: nil)
        let union = try XCTUnwrap(scene.children.first)

        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(union.polygons { false }.count, 6)
        XCTAssertEqual(union.exactBounds(with: union.transform).center, [-10, 0, 0])
    }

    func testHiddenDifferenceSubtractorIsRemovedFromResult() throws {
        let scene = try evaluate(parse("""
        difference {
            cube
            hide cube {
                position 0.5
            }
        }
        """), delegate: nil)
        let difference = try XCTUnwrap(scene.children.first)

        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(difference.polygons { false }.count, 6)
        XCTAssertEqual(difference.volume { false }, 1, accuracy: 1e-12)
    }

    func testHiddenDifferenceBaseProducesEmptyResult() throws {
        let scene = try evaluate(parse("""
        difference {
            hide cube
            sphere
        }
        """), delegate: nil)
        let difference = try XCTUnwrap(scene.children.first)

        XCTAssertTrue(scene.build { false })
        XCTAssertEqual(difference.polygons { false }.count, 0)
        XCTAssertEqual(difference.volume { false }, 0)
    }

    func testSceneKitRenderedChildrenMatchRenderChildrenSemanticsForUnionPreview() throws {
        let scene = try evaluate(parse("""
        union {
            cube
            sphere
        }
        """), delegate: nil)

        let union = try XCTUnwrap(scene.children.first)

        XCTAssertNil(union.mesh)
        XCTAssertEqual(union.renderedChildren, union.children)
    }

    func testMinkowskiRendersLargestVisibleChildUntilBuilt() throws {
        let scene = try evaluate(parse("""
        minkowski {
            cube { size 0.5 }
            hide cube { size 3 }
            cube { size 2 }
        }
        """), delegate: nil)

        let minkowski = try XCTUnwrap(scene.children.first)

        XCTAssertNil(minkowski.mesh)
        XCTAssertEqual(minkowski.renderedChildren, [minkowski.children[2]])

        XCTAssertTrue(scene.build { false })
        XCTAssertNotNil(minkowski.mesh)
        XCTAssertTrue(minkowski.renderedChildren.isEmpty)
    }

    func testHullPreservesTextureOnOneChild() throws {
        let scene = try evaluate(parse("""
        detail 8
        hull {
            cube { position -1.5 }
            sphere { texture checkerboard }
        }
        """), delegate: nil)

        XCTAssertTrue(scene.build { false })
        let mesh = try XCTUnwrap(scene.children.first?.mesh)
        let texturedPolygons = mesh.polygons.filter {
            ($0.material as? Material)?.texture == .checkerboard
        }
        XCTAssertFalse(texturedPolygons.isEmpty)
        XCTAssertTrue(texturedPolygons.flatMap(\.vertices).contains { $0.texcoord != .zero })
    }

    func testHullPreservesTextureOnBothChildren() throws {
        let scene = try evaluate(parse("""
        detail 8
        hull {
            cube {
                position -1.5
                texture checkerboard
            }
            sphere { texture checkerboard }
        }
        """), delegate: nil)

        XCTAssertTrue(scene.build { false })
        let mesh = try XCTUnwrap(scene.children.first?.mesh)
        let texturedPolygons = mesh.polygons.filter {
            ($0.material as? Material)?.texture == .checkerboard
        }
        XCTAssertEqual(texturedPolygons.count, mesh.polygons.count)
        XCTAssertTrue(texturedPolygons.flatMap(\.vertices).contains { $0.texcoord != .zero })
    }

    func testMinkowskiDistributesOverUnion() throws {
        let scene = try evaluate(parse("""
        detail 8
        minkowski {
            union {
                position 0.25 0 0
                cube { position -0.75 0 0 }
                cube { position 0.75 0 0 }
            }
            sphere { size 0.2 }
        }
        """), delegate: nil)
        let minkowski = try XCTUnwrap(scene.children.first)
        let union = try XCTUnwrap(minkowski.children.first)

        XCTAssertTrue(scene.build { false })
        XCTAssertNil(union.mesh)
        XCTAssertTrue(minkowski.hasBuiltMeshes)

        let kernel = minkowski.children[1].flattened()
        let components = union.children.map {
            $0.flattened().transformed(by: union.transform)
        }
        let expected = Mesh.union(components.map {
            $0.minkowskiSum(with: kernel)
        }).makeWatertight().detessellate()
        XCTAssertEqual(minkowski.mesh, expected)
    }

    func testMinkowskiDistributesOverOverlappingUnion() throws {
        let scene = try evaluate(parse("""
        detail 8
        define fillet(source radius) {
            minkowski {
                inset(source radius)
                sphere { size radius * 2 }
            }
        }
        fillet(union {
            cube
            cylinder {
                size 0.45 1.2 0.45
                orientation 0.5
                position 0.45
            }
        } 0.06)
        """), delegate: nil)
        let minkowski = try XCTUnwrap(scene.children.first)
        let union = try XCTUnwrap(minkowski.children.first)

        XCTAssertTrue(scene.build { false })
        XCTAssertNil(union.mesh)
        XCTAssertNotNil(minkowski.mesh)
    }

    func testMinkowskiDoesNotDistributeOverDifference() throws {
        let scene = try evaluate(parse("""
        detail 8
        minkowski {
            difference {
                cube
                sphere { size 0.5 }
            }
            sphere { size 0.2 }
        }
        """), delegate: nil)
        let minkowski = try XCTUnwrap(scene.children.first)
        let difference = try XCTUnwrap(minkowski.children.first)

        XCTAssertTrue(scene.build { false })
        XCTAssertNotNil(difference.mesh)
        XCTAssertNotNil(minkowski.mesh)
    }

    func testDifferenceRenderedChildrenDependOnDebugState() throws {
        let scene = try evaluate(parse("""
        difference {
            cube
            debug sphere
        }
        """), delegate: nil)

        let difference = try XCTUnwrap(scene.children.first)

        XCTAssertEqual(difference.renderedChildren, difference.children)
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

    func testRenderedChildrenCanBeFilteredByFocus() throws {
        let scene = try evaluate(parse("""
        group {
            cube
            focus sphere
        }
        """), delegate: nil)
        let group = try XCTUnwrap(scene.children.first)

        XCTAssertEqual(group.renderedChildren(focus: false).count, 2)
        XCTAssertEqual(group.renderedChildren, [group.children[1]])
        XCTAssertEqual(group.renderedChildren(focus: true), [group.children[1]])
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

        let copy = geometry.withoutHiddenOrUnfocused()
        XCTAssertEqual(copy.children.count, 1)
        XCTAssertEqual(copy.children[0].transform.translation, [10, 0, 0])
        XCTAssertEqual(copy.objectCount, 1)
        XCTAssertEqual(copy.polygons { false }.count, 6)
        XCTAssertEqual(copy.overestimatedBounds.center, [10, 0, 0])
        XCTAssertEqual(copy.exactBounds(with: copy.transform).size, [1, 1, 1])
    }

    func testVisibleGeometryRemovesHiddenChildren() throws {
        let scene = try evaluate(parse("""
        group {
            cube {
                position 10
            }
            hide cube {
                position 100
            }
        }
        """), delegate: nil)

        let copy = scene.visibleGeometry
        let group = try XCTUnwrap(copy.children.first)

        XCTAssertEqual(group.children.count, 1)
        XCTAssertEqual(group.children[0].transform.translation, [10, 0, 0])
        XCTAssertEqual(copy.objectCount, 1)
        XCTAssertEqual(scene.visibleBounds.center, [10, 0, 0])
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

    func testDebugFocusAndHideDoNotAffectGeometryIdentity() throws {
        let scene = try evaluate(parse("""
        cube
        debug cube
        focus cube
        hide cube
        """), delegate: nil)

        guard scene.children.count == 4 else {
            XCTFail()
            return
        }
        let normal = scene.children[0]
        let debug = scene.children[1]
        let focused = scene.children[2]
        let hidden = scene.children[3]

        XCTAssertFalse(normal.debug)
        XCTAssertFalse(normal.isFocused)
        XCTAssertFalse(normal.isHidden)
        XCTAssertTrue(debug.debug)
        XCTAssertFalse(debug.isFocused)
        XCTAssertFalse(debug.isHidden)
        XCTAssertFalse(focused.debug)
        XCTAssertTrue(focused.isFocused)
        XCTAssertFalse(focused.isHidden)
        XCTAssertFalse(hidden.debug)
        XCTAssertFalse(hidden.isFocused)
        XCTAssertTrue(hidden.isHidden)

        XCTAssertEqual(normal, debug)
        XCTAssertEqual(normal, focused)
        XCTAssertEqual(normal, hidden)
        XCTAssertEqual(normal.hashValue, debug.hashValue)
        XCTAssertEqual(normal.hashValue, focused.hashValue)
        XCTAssertEqual(normal.hashValue, hidden.hashValue)
        XCTAssertEqual(normal.cacheKey, debug.cacheKey)
        XCTAssertEqual(normal.cacheKey, focused.cacheKey)
        XCTAssertEqual(normal.cacheKey, hidden.cacheKey)
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

    func testSphereRepresentativePointsMatchMeshVertices() {
        for segments in [3, 4, 5, 6, 7, 8, 12, 16, 32] {
            let points = GeometryType.sphere(segments: segments).representativePoints
            let vertices = Set(Mesh.sphere(slices: segments).polygons.flatMap {
                $0.vertices.map(\.position)
            })
            for vertex in vertices {
                XCTAssertTrue(points.contains {
                    $0.isApproximatelyEqual(to: vertex, absoluteTolerance: epsilon)
                }, "Missing mesh vertex \(vertex) with \(segments) segments")
            }
            for point in points {
                XCTAssertTrue(vertices.contains {
                    $0.isApproximatelyEqual(to: point, absoluteTolerance: epsilon)
                }, "Unexpected representative point \(point) with \(segments) segments")
            }
        }
    }

    func testRotatedSphereBoundsMatchMesh() {
        let context = EvaluationContext(source: "", delegate: nil)
        let transform = Transform(
            scale: [2, 3, 4],
            rotation: .init(pitch: .pi / 7, yaw: .pi / 5, roll: .pi / 3),
            translation: [1, 2, 3]
        )
        for segments in [3, 4, 5, 6, 7, 8, 12, 16, 32] {
            let sphere = Geometry(type: .sphere(segments: segments), in: context)
            let bounds = sphere.exactBounds(with: transform)
            let expected = Mesh.sphere(slices: segments).transformed(by: transform).bounds
            XCTAssertEqual(bounds.min, expected.min, accuracy: epsilon, "\(segments) segments")
            XCTAssertEqual(bounds.max, expected.max, accuracy: epsilon, "\(segments) segments")
        }
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
                return checks >= 4
            })
            XCTAssertLessThan(checks, 10, "\(type)")
            XCTAssertLessThan(shape.mesh?.polygons.count ?? .max, 256 * 2)
        }
    }

    func testMeshFunctionBuildsPrimitiveOnDemand() throws {
        let context = EvaluationContext(source: "", delegate: nil)
        let shape = Geometry(type: .cube, in: context)
        XCTAssertNil(shape.mesh)

        let mesh = try XCTUnwrap(shape.mesh())

        XCTAssertEqual(mesh, Mesh.cube())
        XCTAssertEqual(shape.mesh, mesh)
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
        let mesh = try XCTUnwrap(shape.mesh())
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

    func testPathGeometryPreservesMaterialAndVertexColors() {
        let offset = Vector(1, 2, 3)
        for path in [Path.square(), Path.square(color: .blue)] {
            let geometry = Geometry(
                type: .path(path), name: nil, transform: .translation(offset),
                material: Material(color: .red), smoothing: nil, children: [], sourceLocation: nil
            )
            let expected = Path.square(color: path.hasColors ? .blue : .red)
            XCTAssertEqual(geometry.path(pretransformed: false), expected)
            XCTAssertEqual(geometry.path(pretransformed: true), expected.translated(by: offset))
        }
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

        let geometry = try XCTUnwrap(scene.children.first)
        let mesh = try XCTUnwrap(geometry.mesh())
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
            let scene = try evaluate(parse(program), delegate: TestDelegate(), cache: nil)
            XCTAssertTrue(scene.build { false })
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
            XCTAssertNotNil(geometry.mesh())
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
                guard otherIndex != index, let polygon = subpathPolygons[otherIndex] else {
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
        XCTAssertLessThan(rawExtrusion.duration, 2)

        let build = timed("detailed extrusion Geometry.build") {
            geometry.build { false }
        }
        let buildSucceeded = build.result
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertTrue(buildSucceeded)
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertLessThan(build.duration, 2)
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

        let mesh = try XCTUnwrap(geometry.mesh())
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
        ], .init(segments: 4)), in: context)
        XCTAssertEqual(shape.overestimatedBounds.size, [1, 2, 1])
        XCTAssertEqual(shape.overestimatedBounds.center, [1, 2.5, 3])
        XCTAssertEqual(shape.exactBounds(with: shape.transform), shape.overestimatedBounds)
    }

    func testTransformedBoundsForFilledAndStoredGeometry() {
        let paths: [Path] = [
            .square().translated(by: [1, 2, 0]),
            .square().scaled(by: 0.5).translated(by: [-1, 3, 2]),
        ]
        let types: [GeometryType] = [
            .fill(paths), .loft(paths),
            .hull(paths.flatMap(\.points).map { Vertex($0.position) }),
            .mesh(.cube().translated(by: [1, 2, 3])),
        ]
        for type in types {
            let geometry = Geometry(type: type, in: EvaluationContext(source: "", delegate: nil))
            for transform in [
                Transform.identity,
                .init(scale: [-2, 3, 0.5], translation: [1, -2, 3]),
                .init(scale: [-2, 3, 0.5], rotation: .pitch(.pi / 3), translation: [1, -2, 3]),
            ] {
                let expected = Bounds(type.representativePoints.transformed(by: transform))
                let actual = type.bounds(with: transform)
                XCTAssertEqual(actual.min, expected.min, accuracy: epsilon)
                XCTAssertEqual(actual.max, expected.max, accuracy: epsilon)
                let geometryBounds = geometry.exactBounds(with: transform)
                XCTAssertEqual(geometryBounds.min, expected.min, accuracy: epsilon)
                XCTAssertEqual(geometryBounds.max, expected.max, accuracy: epsilon)
            }
        }
    }

    func testLatheBoundsMatchSampledRings() {
        let profiles: [[Path]] = [
            [],
            [.empty],
            [.square()],
            [.circle(radius: 0.5).translated(by: [0, 1, 0])],
            [Path([.point(0, -2), .point(3, -1), .point(1, 4), .point(0, -2)])],
            [.square().translated(by: [-2, 0, 0]), .square().translated(by: [1, 3, 0])],
        ]
        let transforms: [Transform] = [
            .identity,
            .translation([1, 2, 3]),
            .scale([-2, 3, 0.5]),
            .rotation(.roll(.halfPi)),
            .init(scale: [-2, 3, 0.5], rotation: .pitch(.pi / 3) * .roll(.pi / 5), translation: [1, -2, 3]),
        ]
        for paths in profiles {
            for segments in [3, 4, 7, 16, 127] {
                let type = GeometryType.lathe(paths, .init(segments: segments))
                let points = type.representativePoints
                let shape = Geometry(type: type, in: EvaluationContext(source: "", delegate: nil))
                for transform in transforms {
                    let expected = Bounds(points.transformed(by: transform))
                    let actual = shape.exactBounds(with: transform)
                    if expected.isEmpty {
                        XCTAssertTrue(actual.isEmpty)
                    } else {
                        XCTAssertEqual(actual.min, expected.min, accuracy: epsilon)
                        XCTAssertEqual(actual.max, expected.max, accuracy: epsilon)
                    }
                }
                let expected = Bounds(points)
                if expected.isEmpty {
                    XCTAssertTrue(type.bounds.isEmpty)
                } else {
                    XCTAssertEqual(type.bounds.min, expected.min, accuracy: epsilon)
                    XCTAssertEqual(type.bounds.max, expected.max, accuracy: epsilon)
                }
            }
        }
    }

    func testLatheAlongStraightAxisMatchesOrdinaryLathe() throws {
        let profile = """
        path {
            point 0 0.6
            point -0.05 0.6
            curve -0.12 0.2
            point -0.25 0.1
            point -0.25 0
            point -0.25 0
            point 0 0
        }
        """
        let ordinary = try evaluate(parse("lathe { \(profile) }"), delegate: nil)
        let expected = try XCTUnwrap(ordinary.children.first?.mesh())
        for axis in ["0\n0 0.6", "point 0\npoint 0 0.6"] {
            let scene = try evaluate(parse("""
            lathe {
                \(profile)
                along path { \(axis) }
            }
            """), delegate: nil)
            let geometry = try XCTUnwrap(scene.children.first)
            guard case let .lathe(_, options) = geometry.type else {
                return XCTFail("Expected lathe geometry")
            }
            XCTAssertEqual(options.along.first?.points.map(\.position), [.zero, [0, 0.6, 0]])
            let mesh = try XCTUnwrap(geometry.mesh())
            XCTAssertEqual(mesh.bounds.min, expected.bounds.min, accuracy: epsilon)
            XCTAssertEqual(mesh.bounds.max, expected.bounds.max, accuracy: epsilon)
            XCTAssertEqual(mesh.surfaceArea, expected.surfaceArea, accuracy: epsilon)
            XCTAssertEqual(mesh.signedVolume, expected.signedVolume, accuracy: epsilon)
            XCTAssertTrue(mesh.isWatertight)
            let topFaces = mesh.polygons.filter { polygon in
                polygon.vertices.allSatisfy { abs($0.position.y - 0.6) < epsilon }
            }
            XCTAssertFalse(topFaces.isEmpty, "Expected a flat top cap")
            let topBounds = Bounds(topFaces.flatMap { $0.vertices.map(\.position) })
            XCTAssertEqual(topBounds.size, [0.1, 0, 0.1], accuracy: epsilon)
            for vertex in topFaces.flatMap(\.vertices) {
                XCTAssertEqual(vertex.normal, .unitY, accuracy: epsilon)
            }
        }
    }

    func testLatheAlongCircleWithRadialProfile() throws {
        let scene = try evaluate(parse("""
        lathe {
            path {
                point 0
                point 1
            }
            along circle
        }
        """), delegate: nil)
        let geometry = try XCTUnwrap(scene.children.first)
        let bounds = geometry.exactBounds(with: .identity)
        let mesh = try XCTUnwrap(geometry.mesh())
        XCTAssertFalse(mesh.polygons.isEmpty)
        XCTAssertEqual(bounds, mesh.bounds)
        XCTAssertGreaterThan(mesh.surfaceArea, 0)
    }

    func testLatheAlongClosedLoop() throws {
        let scene = try evaluate(parse("""
        lathe {
            path {
                point -0.1 1
                point -0.1 0
            }
            along circle { size 2 }
        }
        """), delegate: nil)
        let geometry = try XCTUnwrap(scene.children.first)
        let bounds = geometry.exactBounds(with: .identity)
        let mesh = try XCTUnwrap(geometry.mesh())
        XCTAssertEqual(bounds, mesh.bounds)
        XCTAssertTrue(mesh.polygons.areWatertight)
        XCTAssertGreaterThan(mesh.signedVolume, 0)
        guard case let .lathe(paths, options) = geometry.type else {
            return XCTFail("Expected lathe")
        }
        let contours = try XCTUnwrap(paths.first).latheContours(
            along: XCTUnwrap(options.along.first), slices: options.segments
        )
        XCTAssertEqual(contours.first, contours.last)
    }

    func testLatheAlongMiterLimitBuildAndBounds() throws {
        let scene = try evaluate(parse("""
        lathe {
            miterLimit 1
            path {
                point -0.1 1
                point -0.1 0
            }
            along path {
                point 0 -2
                point 0 0
                point 0.5 -1
            }
        }
        """), delegate: nil)
        let geometry = try XCTUnwrap(scene.children.first)
        let bounds = geometry.exactBounds(with: .identity)
        let mesh = try XCTUnwrap(geometry.mesh())
        XCTAssertTrue(mesh.polygons.areWatertight)
        XCTAssertEqual(bounds, mesh.bounds)
        let encoded = try JSONEncoder().encode(geometry.type)
        XCTAssertEqual(try JSONDecoder().decode(GeometryType.self, from: encoded), geometry.type)
        let legacy = Data(#"{"segments":16,"along":[]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(LatheOptions.self, from: legacy).miterLimit, .infinity)
    }

    func testLatheAlongBendKeepsNeighboringContoursApart() throws {
        let scene = try evaluate(parse("""
        lathe {
            path {
                point 0 0.6
                point -0.05 0.6
                curve -0.12 0.2
                point -0.25 0.1
                point -0.25 0
                point -0.25 0
                point 0 0
            }
            along path {
                0 -0.5
                0 0
                0.2 0.5
            }
        }
        """), delegate: nil)
        let geometry = try XCTUnwrap(scene.children.first)
        guard case let .lathe(paths, options) = geometry.type else {
            return XCTFail("Expected lathe geometry")
        }
        let profile = try XCTUnwrap(paths.first)
        let axis = try XCTUnwrap(options.along.first)
        let contours = profile.latheContours(along: axis, slices: options.segments).sorted {
            $0.bounds.center.y < $1.bounds.center.y
        }
        for (previous, next) in zip(contours, contours.dropFirst()) {
            for point in previous.points {
                XCTAssertLessThanOrEqual(
                    (point.position - next.bounds.center).dot(next.faceNormal), epsilon
                )
            }
            for point in next.points {
                XCTAssertGreaterThanOrEqual(
                    (point.position - previous.bounds.center).dot(previous.faceNormal), -epsilon
                )
            }
        }
        XCTAssertTrue(try XCTUnwrap(geometry.mesh()).isWatertight)
    }

    func testLatheAlongCylinderHasStraightSides() throws {
        let scene = try evaluate(parse("""
        lathe {
            path {
                0.5
                0.5 0.25
                0.5 0.5
                0.5 0.75
                0.5 1
            }
            along path {
                0.2 -0.5
                0 0
                0.2 0.5
            }
        }
        """), delegate: nil)
        let mesh = try XCTUnwrap(scene.children.first?.mesh())
        let directions = [Vector(-0.2, 0.5).normalized(), Vector(0.2, 0.5).normalized()]
        let endpoints = [Vector(0.2, -0.5), Vector(0.2, 0.5)]
        var capCount = 0
        for polygon in mesh.polygons {
            let isCap = zip(endpoints, directions).contains { center, normal in
                polygon.vertices.allSatisfy { abs(($0.position - center).dot(normal)) < epsilon }
            }
            if isCap {
                capCount += 1
            } else {
                XCTAssertTrue(directions.contains { abs(polygon.plane.normal.dot($0)) < epsilon })
            }
        }
        XCTAssertEqual(capCount, 2)
        XCTAssertTrue(mesh.isWatertight)
    }

    func testLatheAlongPathBuildsMesh() throws {
        let profile = Path([
            .point(0, -0.5),
            .point(0.2, -0.4),
            .point(0.2, 0.4),
            .point(0, 0.5),
        ])
        let along = Path([
            .point(0, -1, 0),
            .point(0, 0, 1),
            .point(0, 1, 0),
        ])
        let options = LatheOptions(segments: 12, along: [along])
        let geometry = Geometry(
            type: .lathe([profile], options),
            in: EvaluationContext(source: "", delegate: nil)
        )

        let mesh = try XCTUnwrap(geometry.mesh())
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertGreaterThan(mesh.bounds.max.z, 0.9)
        XCTAssertLessThan(mesh.bounds.min.y, -0.9)
        XCTAssertGreaterThan(mesh.bounds.max.y, 0.9)
    }

    func testLatheAlongWithPrimitiveProfile() throws {
        let scene = try evaluate(parse("""
        lathe {
            square { size 2 3 }
            along path {
                point 0 -1 0
                point 0 0 1
                point 0 1 0
            }
        }
        """), delegate: nil)
        let geometry = try XCTUnwrap(scene.children.first)
        guard case let .lathe(paths, options) = geometry.type else {
            return XCTFail("Expected lathe geometry")
        }
        XCTAssertEqual(paths, [.rectangle(width: 2, height: 3)])
        XCTAssertTrue(geometry.children.isEmpty)
        let along = try XCTUnwrap(options.along.first)
        let expected = Mesh.lathe(paths[0], along: along, slices: options.segments)
        XCTAssertFalse(expected.isEmpty)
        XCTAssertEqual(try XCTUnwrap(geometry.mesh()), expected)
        XCTAssertEqual(geometry.overestimatedBounds, expected.bounds)

        let encoded = try JSONEncoder().encode(geometry.type)
        XCTAssertEqual(try JSONDecoder().decode(GeometryType.self, from: encoded), geometry.type)
    }

    func testLatheAlongMaintainsContinuousRingFrames() throws {
        func program(detail: Int) -> String {
            """
            detail \(detail)
            lathe {
                path {
                    point 0
                    point 1 1
                    point 0 2
                }
                along path {
                    point 0
                    curve 0 5

                    scale 2 1 2
                    size 2 1 2

                    curve 5 10 5

                    scale 1 1 1
                    size 1 1 1

                    point 0 20
                }
            }
            """
        }

        for detail in [8, 16, 32, 64] {
            let scene = try evaluate(parse(program(detail: detail)), delegate: nil)
            let geometry = try XCTUnwrap(scene.children.first)
            guard case let .lathe(paths, options) = geometry.type,
                  let profile = paths.first,
                  let along = options.along.first
            else {
                return XCTFail("Expected lathe geometry, got \(geometry.type)")
            }

            let contours = profile.latheContours(along: along, slices: options.segments)
            XCTAssertEqual(contours.first?.points.count, 1, "detail \(detail)")
            XCTAssertEqual(contours.last?.points.count, 1, "detail \(detail)")
            XCTAssertTrue(contours.dropFirst().prefix(while: { $0.points.count == 1 }).isEmpty, "detail \(detail)")
            XCTAssertTrue(
                contours.reversed().dropFirst().prefix(while: { $0.points.count == 1 }).isEmpty,
                "detail \(detail)"
            )
            let centers = contours.map(\.bounds.center)
            XCTAssertLessThanOrEqual(contours.count, profile.points.count + along.points.count - 2)
            for point in along.points {
                XCTAssertTrue(centers.contains {
                    $0.isApproximatelyEqual(to: point.position, absoluteTolerance: epsilon)
                }, "Missing contour at axis vertex \(point.position), detail \(detail)")
            }
            for (lhs, rhs) in zip(centers, centers.dropFirst()) {
                XCTAssertGreaterThan(lhs.distance(from: rhs), epsilon, "detail \(detail)")
            }

            let mesh = try XCTUnwrap(geometry.mesh())
            XCTAssertFalse(mesh.isEmpty, "detail \(detail)")
            let polePositions = try [
                XCTUnwrap(contours.first?.points.first?.position),
                XCTUnwrap(contours.last?.points.first?.position),
            ]
            for polePosition in polePositions {
                let incidentPolygons = mesh.polygons.filter { polygon in
                    polygon.vertices.contains {
                        $0.position.isApproximatelyEqual(to: polePosition, absoluteTolerance: epsilon)
                    }
                }
                XCTAssertEqual(incidentPolygons.count, options.segments, "detail \(detail)")
            }
            XCTAssertGreaterThan(mesh.bounds.max.z, 4, "detail \(detail)")
            XCTAssertGreaterThan(mesh.bounds.max.y, 16, "detail \(detail)")
        }
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
