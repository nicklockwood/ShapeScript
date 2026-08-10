//
//  RegressionTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 27/07/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

@testable import Euclid
@testable import ShapeScript
import XCTest

private let projectDirectory: URL = testsDirectory.deletingLastPathComponent()

private let exampleURLs: [URL] = try! FileManager.default
    .contentsOfDirectory(
        at: projectDirectory.appendingPathComponent("Examples"),
        includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "shape" }

private let testShapesURLs: [URL] = try! FileManager.default
    .contentsOfDirectory(
        at: testsDirectory.appendingPathComponent("TestShapes"),
        includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "shape" }
    .filter {
        #if os(iOS)
        return !$0.deletingPathExtension().lastPathComponent.hasSuffix("-mac")
        #else
        return !$0.deletingPathExtension().lastPathComponent.hasSuffix("-ios")
        #endif
    }

final class RegressionTests: XCTestCase {
    func testFill() throws {
        let program = "fill text \"hello\""
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 14)
        #endif
    }

    func testExtrudedOutsetComicSans3HasValidCaps() throws {
        #if os(macOS)
        let program = """
        detail 64
        font "comic sans ms"
        extrude inset (text "3") -0.01
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        let mesh = try XCTUnwrap(geometry.mesh)
        let font = CTFontCreateWithName("comic sans ms" as CFString, 1, nil)
        let shape = try XCTUnwrap(Path.text("3", font: font, detail: 8).first)
        let expected = Mesh.extrude(shape.inset(by: -0.01))

        XCTAssertEqual(mesh.polygons.count, expected.polygons.count)
        XCTAssertFalse(mesh.polygons.containsIntersections)
        XCTAssertTrue(mesh.hasConsistentCapDirections)
        let internalCapPolygons = mesh.polygons.filter { polygon in
            abs(polygon.plane.normal.z) > 0.5 && polygon.vertices.contains {
                let z = $0.position.z
                return abs(z - mesh.bounds.min.z) > epsilon && abs(z - mesh.bounds.max.z) > epsilon
            }
        }
        XCTAssertTrue(internalCapPolygons.isEmpty)
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertTrue(mesh.isConsistentlyWound)
        XCTAssertGreaterThan(mesh.signedVolume, 0)
        #endif
    }

    func testExtrudedOutsetComicSansDPreservesHole() throws {
        #if os(macOS)
        let program = """
        detail 64
        font "comic sans ms"
        extrude inset (text "d") -0.03
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        let mesh = try XCTUnwrap(geometry.mesh)
        let font = CTFontCreateWithName("comic sans ms" as CFString, 1, nil)
        let shape = try XCTUnwrap(Path.text("d", font: font, detail: 8).first)
        let filledArea = Mesh.fill(shape.inset(by: -0.03)).surfaceArea / 2

        XCTAssertEqual(mesh.endCapArea(at: mesh.bounds.min.z), filledArea, accuracy: epsilon)
        XCTAssertEqual(mesh.endCapArea(at: mesh.bounds.max.z), filledArea, accuracy: epsilon)
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertTrue(mesh.isConsistentlyWound)
        XCTAssertGreaterThan(mesh.signedVolume, 0)
        #endif
    }

    func testExtrusion() throws {
        let program = "extrude text \"hello\""
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 129)
        #endif
    }

    func testInsetExtrudedNumber8() throws {
        let program = "inset (extrude text \"8\") 0.03"
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertGreaterThan(mesh.signedVolume, 0)
        #endif
    }

    func testInsetExtrudedNumber8PastStrokeWidthIsEmpty() throws {
        let program = "inset (extrude text \"8\") 0.06"
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertTrue(mesh.isEmpty)
        #endif
    }

    func testInsetExtrudedTextDoesNotDisappear() throws {
        let program = "inset (extrude text \"Hello\") 0.01"
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertGreaterThan(mesh.signedVolume, 0)
        XCTAssertTrue(mesh.polygons.areWatertight, "hole edges: \(mesh.polygons.holeEdges.count)")
        #endif
    }

    func testInsetFilledPrimitiveRewritesPathBeforeFill() throws {
        let scene = try evaluate(parse("inset (fill square) 0.1"), delegate: TestDelegate())
        let geometry = try XCTUnwrap(scene.children.first)
        guard case let .fill(paths) = geometry.type else {
            return XCTFail("Expected fill geometry, got \(geometry.type)")
        }

        let path = try XCTUnwrap(paths.first)
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(path.bounds.size.x, 0.8, accuracy: epsilon)
        XCTAssertNil(geometry.mesh)
    }

    func testInsetExtrudedPrimitiveRewritesPathAndDepth() throws {
        let scene = try evaluate(parse("inset (extrude square) 0.1"), delegate: TestDelegate())
        let geometry = try XCTUnwrap(scene.children.first)
        guard case let .loft(paths) = geometry.type else {
            return XCTFail("Expected loft geometry, got \(geometry.type)")
        }

        XCTAssertEqual(paths.count, 2)
        let path = try XCTUnwrap(paths.first)
        XCTAssertEqual(path.bounds.size.x, 0.8, accuracy: epsilon)
        XCTAssertEqual(path.bounds.min.z, -0.4, accuracy: epsilon)
        XCTAssertEqual(paths.last?.bounds.max.z ?? 0, 0.4, accuracy: epsilon)
        XCTAssertNil(geometry.mesh)
    }

    func testInsetNonAxisAlignedExtrusionRewritesAsLoft() throws {
        let distance = 0.1
        let rotation = Rotation(pitch: .halfturns(0.125))
        let program = """
        inset (extrude {
            rotate 0 0 0.125
            square
        }) \(distance)
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        let geometry = try XCTUnwrap(scene.children.first)
        guard case let .loft(paths) = geometry.type else {
            return XCTFail("Expected loft geometry, got \(geometry.type)")
        }
        XCTAssertEqual(paths.count, 2)
        XCTAssertNil(geometry.mesh)

        XCTAssertTrue(geometry.build { false })
        let mesh = try XCTUnwrap(geometry.mesh)
        let path = Path.square().rotated(by: rotation).inset(by: distance)
        let expected = Mesh.extrude(path, depth: 1 - distance * 2)
        XCTAssertEqual(mesh.vertexPositionSignature, expected.vertexPositionSignature)
    }

    func testInsetExtrudedAlongPathRewritesProfileAndPath() throws {
        let program = """
        inset (extrude {
            square
            along path {
                point 0
                point 0 0 2
            }
        }) 0.1
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        let geometry = try XCTUnwrap(scene.children.first)
        guard case let .extrude(paths, options) = geometry.type else {
            return XCTFail("Expected extrude geometry, got \(geometry.type)")
        }

        let path = try XCTUnwrap(paths.first)
        let along = try XCTUnwrap(options.along.first)
        let start = try XCTUnwrap(along.points.first)
        let end = try XCTUnwrap(along.points.last)
        XCTAssertEqual(path.bounds.size.x, 0.8, accuracy: epsilon)
        XCTAssertEqual(start.position.z, 0.1, accuracy: epsilon)
        XCTAssertEqual(end.position.z, 1.9, accuracy: epsilon)
        XCTAssertNil(geometry.mesh)
    }

    func testExtrudePassesMiterLimitToMeshGeneration() throws {
        let program = """
        extrude {
            miterLimit 1
            square { size 0.2 }
            along path {
                point 0
                point 1
                point 1 1
            }
        }
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        let mesh = try XCTUnwrap(geometry.mesh)
        let expected = Mesh.extrude(
            .square().scaled(by: 0.2),
            along: Path([
                .point(.zero),
                .point(.unitX),
                .point([1, 1]),
            ]),
            miterLimit: 1
        )
        XCTAssertEqual(mesh.vertexPositionSignature, expected.vertexPositionSignature)
    }

    func testInsetGroupRewritesNestedFillPrimitive() throws {
        let scene = try evaluate(parse("inset (group { fill square }) 0.1"), delegate: TestDelegate())
        let geometry = try XCTUnwrap(scene.children.first)
        guard case .group = geometry.type else {
            return XCTFail("Expected group geometry, got \(geometry.type)")
        }
        let child = try XCTUnwrap(geometry.children.first)
        guard case let .fill(paths) = child.type else {
            return XCTFail("Expected fill child, got \(child.type)")
        }
        let path = try XCTUnwrap(paths.first)

        XCTAssertEqual(path.bounds.size.x, 0.8, accuracy: epsilon)
        XCTAssertNil(geometry.mesh)
        XCTAssertNil(child.mesh)
    }

    func testInsetGroupRewritesSiblingAndMeshInsetsFallbackChild() throws {
        let geometry = Geometry(
            type: .group,
            name: nil,
            transform: .identity,
            material: .default,
            smoothing: nil,
            children: [
                Geometry(
                    type: .fill([.square()]),
                    name: nil,
                    transform: .identity,
                    material: .default,
                    smoothing: nil,
                    children: [],
                    sourceLocation: nil
                ),
                Geometry(
                    type: .mesh(.cube()),
                    name: nil,
                    transform: .translation(.unitX),
                    material: .default,
                    smoothing: nil,
                    children: [],
                    sourceLocation: nil
                ),
            ],
            sourceLocation: nil
        ).insetByRewritingPrimitives(by: 0.1, sourceLocation: { nil })
        guard case .group = geometry.type else {
            return XCTFail("Expected group geometry, got \(geometry.type)")
        }
        XCTAssertEqual(geometry.children.count, 2)

        let fill = geometry.children[0]
        guard case let .fill(paths) = fill.type else {
            return XCTFail("Expected fill child, got \(fill.type)")
        }
        let path = try XCTUnwrap(paths.first)
        XCTAssertEqual(path.bounds.size.x, 0.8, accuracy: epsilon)

        let fallback = geometry.children[1]
        guard case let .mesh(mesh) = fallback.type else {
            return XCTFail("Expected mesh fallback child, got \(fallback.type)")
        }
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertNil(geometry.mesh)
        XCTAssertNil(fill.mesh)
        XCTAssertNil(fallback.mesh)
    }

    func testInsetGroupPreservesCameraAndLightChildren() {
        let camera = Camera.default
        let light = Light.default
        let geometry = Geometry(
            type: .group,
            name: nil,
            transform: .identity,
            material: .default,
            smoothing: nil,
            children: [
                Geometry(
                    type: .camera(camera),
                    name: nil,
                    transform: .translation(.unitX),
                    material: .default,
                    smoothing: nil,
                    children: [],
                    sourceLocation: nil
                ),
                Geometry(
                    type: .light(light),
                    name: nil,
                    transform: .translation(.unitY),
                    material: .default,
                    smoothing: nil,
                    children: [],
                    sourceLocation: nil
                ),
                Geometry(
                    type: .fill([.square()]),
                    name: nil,
                    transform: .identity,
                    material: .default,
                    smoothing: nil,
                    children: [],
                    sourceLocation: nil
                ),
            ],
            sourceLocation: nil
        ).insetByRewritingPrimitives(by: 0.1, sourceLocation: { nil })
        guard case .group = geometry.type else {
            return XCTFail("Expected group geometry, got \(geometry.type)")
        }
        XCTAssertEqual(geometry.children.count, 3)
        guard case .camera = geometry.children[0].type else {
            return XCTFail("Expected camera child, got \(geometry.children[0].type)")
        }
        guard case .light = geometry.children[1].type else {
            return XCTFail("Expected light child, got \(geometry.children[1].type)")
        }
        XCTAssertEqual(geometry.children[0].transform.translation, .unitX)
        XCTAssertEqual(geometry.children[1].transform.translation, .unitY)
        guard case let .fill(paths) = geometry.children[2].type else {
            return XCTFail("Expected fill child, got \(geometry.children[2].type)")
        }
        XCTAssertEqual(paths.first?.bounds.size.x ?? 0, 0.8, accuracy: epsilon)
    }

    func testInsetUnionRewritesNestedExtrudeAlongPath() throws {
        let program = """
        inset (union {
            extrude {
                square
                along path {
                    point 0
                    point 0 0 2
                }
            }
        }) 0.1
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        let geometry = try XCTUnwrap(scene.children.first)
        guard case .union = geometry.type else {
            return XCTFail("Expected union geometry, got \(geometry.type)")
        }
        let child = try XCTUnwrap(geometry.children.first)
        guard case let .extrude(paths, options) = child.type else {
            return XCTFail("Expected extrude child, got \(child.type)")
        }
        let path = try XCTUnwrap(paths.first)
        let along = try XCTUnwrap(options.along.first)
        let start = try XCTUnwrap(along.points.first)
        let end = try XCTUnwrap(along.points.last)

        XCTAssertEqual(path.bounds.size.x, 0.8, accuracy: epsilon)
        XCTAssertEqual(start.position.z, 0.1, accuracy: epsilon)
        XCTAssertEqual(end.position.z, 1.9, accuracy: epsilon)
        XCTAssertNil(geometry.mesh)
        XCTAssertNil(child.mesh)
    }

    func testInsetDifferenceRewritesSubtractiveChildrenWithOppositeInset() throws {
        let program = """
        inset (difference {
            cube
            cylinder
        }) 0.1
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        let geometry = try XCTUnwrap(scene.children.first)
        guard case .difference = geometry.type else {
            return XCTFail("Expected difference geometry, got \(geometry.type)")
        }
        XCTAssertEqual(geometry.children.count, 2)

        let solid = try XCTUnwrap(geometry.children.first)
        let subtractive = try XCTUnwrap(geometry.children.last)
        guard case .cube = solid.type else {
            return XCTFail("Expected cube child, got \(solid.type)")
        }
        guard case .cylinder = subtractive.type else {
            return XCTFail("Expected cylinder child, got \(subtractive.type)")
        }

        let radiusScale = 1 + 0.1 / (0.5 * cos(.pi / 16))
        XCTAssertEqual(solid.transform.scale, .init(size: 0.8), accuracy: epsilon)
        XCTAssertEqual(subtractive.transform.scale, [radiusScale, 1.2, radiusScale], accuracy: epsilon)
        XCTAssertNil(geometry.mesh)
        XCTAssertNil(solid.mesh)
        XCTAssertNil(subtractive.mesh)
    }

    func testInsetCubeRewritesScale() throws {
        let scene = try evaluate(parse("inset cube 0.1"), delegate: TestDelegate())
        let geometry = try XCTUnwrap(scene.children.first)
        guard case .cube = geometry.type else {
            return XCTFail("Expected cube geometry, got \(geometry.type)")
        }

        XCTAssertEqual(geometry.transform.scale, .init(size: 0.8), accuracy: epsilon)
        XCTAssertEqual(geometry.transform.translation, .zero, accuracy: epsilon)
        XCTAssertNil(geometry.mesh)
    }

    func testNegativeInsetCubeMatchesMeshInsetBounds() throws {
        let (primitive, mesh) = try assertInsetPrimitiveMatchesMeshBounds(
            "cube { size 0.8 }",
            by: -0.5
        )
        XCTAssertEqual(primitive.exactBounds(with: primitive.transform).size, .init(size: 1.8), accuracy: epsilon)
        XCTAssertEqual(primitive.flattened().bounds.size, .init(size: 1.8), accuracy: epsilon)
        XCTAssertNotNil(mesh.mesh)
    }

    func testNegativeInsetScaledSphereRewritesScale() throws {
        let distance = -0.1
        let size = 0.8
        let segments = 8
        let scene = try evaluate(
            parse("detail \(segments)\ninset sphere { size \(size) } \(distance)"),
            delegate: TestDelegate()
        )
        let geometry = try XCTUnwrap(scene.children.first)
        guard case .sphere = geometry.type else {
            return XCTFail("Expected sphere geometry, got \(geometry.type)")
        }
        let stacks = max(2, segments / 2)
        let verticalApothem = 0.5 * cos(.pi / Double(stacks * 2))
        let radialApothem = verticalApothem * cos(.pi / Double(segments))
        let expectedScale = [
            size * (1 - distance / (radialApothem * size)),
            size * (1 - distance / (verticalApothem * size)),
            size * (1 - distance / (radialApothem * size)),
        ] as Vector

        XCTAssertEqual(geometry.transform.scale, expectedScale, accuracy: epsilon)
        XCTAssertEqual(geometry.transform.translation, .zero, accuracy: epsilon)
        XCTAssertNil(geometry.mesh)
    }

    func testNegativeInsetScaledIcosphereRewritesScale() throws {
        let distance = -0.1
        let size = 0.8
        let subdivisions = 1
        let scene = try evaluate(
            parse("detail 8\ninset icosphere { size \(size) } \(distance)"),
            delegate: TestDelegate()
        )
        let geometry = try XCTUnwrap(scene.children.first)
        guard case .icosphere = geometry.type else {
            return XCTFail("Expected icosphere geometry, got \(geometry.type)")
        }
        let apothem = Mesh.icosphere(subdivisions: subdivisions, wrapMode: .none).polygons.reduce(0.5) {
            Swift.min($0, abs($1.plane.w))
        }
        let expectedScale = size * (1 - distance / (apothem * size))

        XCTAssertEqual(geometry.transform.scale, Vector(size: expectedScale), accuracy: epsilon)
        XCTAssertEqual(geometry.transform.translation, .zero, accuracy: epsilon)
        XCTAssertNil(geometry.mesh)
    }

    func testNegativeInsetCylinderMatchesMeshInsetBounds() throws {
        try assertInsetPrimitiveMatchesMeshBounds("cylinder { size 0.8 }", by: -0.1, prefix: "detail 8")
    }

    func testNegativeInsetConeMatchesMeshInsetBounds() throws {
        try assertInsetPrimitiveMatchesMeshBounds("cone { size 0.8 }", by: -0.1, prefix: "detail 8")
    }

    @discardableResult
    private func assertInsetPrimitiveMatchesMeshBounds(
        _ primitive: String,
        by distance: Double,
        prefix: String = ""
    ) throws -> (primitive: Geometry, mesh: Geometry) {
        let prefix = prefix.isEmpty ? "" : "\(prefix)\n"
        let primitiveScene = try evaluate(parse("\(prefix)inset \(primitive) \(distance)"), delegate: TestDelegate())
        let meshScene = try evaluate(parse("\(prefix)inset (mesh \(primitive)) \(distance)"), delegate: TestDelegate())
        let primitive = try XCTUnwrap(primitiveScene.children.first)
        let mesh = try XCTUnwrap(meshScene.children.first)

        let primitiveBounds = primitive.exactBounds(with: primitive.transform)
        let meshBounds = mesh.exactBounds(with: mesh.transform)

        XCTAssertEqual(primitiveBounds.min, meshBounds.min, accuracy: epsilon)
        XCTAssertEqual(primitiveBounds.max, meshBounds.max, accuracy: epsilon)

        _ = primitive.build { false }
        _ = mesh.build { false }
        let primitiveMeshBounds = primitive.flattened().bounds
        let meshMeshBounds = mesh.flattened().bounds

        XCTAssertEqual(primitiveMeshBounds.min, meshMeshBounds.min, accuracy: epsilon)
        XCTAssertEqual(primitiveMeshBounds.max, meshMeshBounds.max, accuracy: epsilon)
        return (primitive, mesh)
    }

    func testInsetSphereRewritesScale() throws {
        let distance = 0.1
        let segments = 4
        let scene = try evaluate(parse("detail \(segments)\ninset sphere \(distance)"), delegate: TestDelegate())
        let geometry = try XCTUnwrap(scene.children.first)
        guard case .sphere = geometry.type else {
            return XCTFail("Expected sphere geometry, got \(geometry.type)")
        }
        let stacks = max(2, segments / 2)
        let verticalApothem = 0.5 * cos(.pi / Double(stacks * 2))
        let radialApothem = verticalApothem * cos(.pi / Double(segments))
        let expectedScale = [
            1 - distance / radialApothem,
            1 - distance / verticalApothem,
            1 - distance / radialApothem,
        ] as Vector

        XCTAssertEqual(geometry.transform.scale, expectedScale, accuracy: epsilon)
        XCTAssertEqual(geometry.transform.translation, .zero, accuracy: epsilon)
        XCTAssertNil(geometry.mesh)
    }

    func testInsetIcosphereRewritesScale() throws {
        let distance = 0.1
        let subdivisions = 1
        let scene = try evaluate(parse("detail 8\ninset icosphere \(distance)"), delegate: TestDelegate())
        let geometry = try XCTUnwrap(scene.children.first)
        guard case .icosphere = geometry.type else {
            return XCTFail("Expected icosphere geometry, got \(geometry.type)")
        }
        let apothem = Mesh.icosphere(subdivisions: subdivisions, wrapMode: .none).polygons.reduce(0.5) {
            Swift.min($0, abs($1.plane.w))
        }
        let expectedScale = 1 - distance / apothem

        XCTAssertEqual(geometry.transform.scale, Vector(size: expectedScale), accuracy: epsilon)
        XCTAssertEqual(geometry.transform.translation, .zero, accuracy: epsilon)
        XCTAssertNil(geometry.mesh)
    }

    func testInsetCylinderRewritesScale() throws {
        let distance = 0.1
        let segments = 4
        let scene = try evaluate(parse("detail \(segments)\ninset cylinder \(distance)"), delegate: TestDelegate())
        let geometry = try XCTUnwrap(scene.children.first)
        guard case .cylinder = geometry.type else {
            return XCTFail("Expected cylinder geometry, got \(geometry.type)")
        }
        let expectedRadiusScale = 1 - distance / (0.5 * cos(.pi / Double(segments)))
        let expectedHeightScale = 1 - distance * 2

        XCTAssertEqual(
            geometry.transform.scale,
            [expectedRadiusScale, expectedHeightScale, expectedRadiusScale],
            accuracy: epsilon
        )
        XCTAssertEqual(geometry.transform.translation, .zero, accuracy: epsilon)
        XCTAssertNil(geometry.mesh)
    }

    func testInsetConeRewritesScaleAndOffset() throws {
        let distance = 0.1
        let segments = 4
        let scene = try evaluate(parse("detail \(segments)\ninset cone \(distance)"), delegate: TestDelegate())
        let geometry = try XCTUnwrap(scene.children.first)
        guard case .cone = geometry.type else {
            return XCTFail("Expected cone geometry, got \(geometry.type)")
        }
        let apothem = 0.5 * cos(.pi / Double(segments))
        let sideLength = sqrt(apothem * apothem + 1)
        let expectedScale = 1 - distance * (sideLength / apothem + 1)
        let expectedOffset = distance * (1 - sideLength / apothem) / 2

        XCTAssertEqual(geometry.transform.scale, Vector(size: expectedScale), accuracy: epsilon)
        XCTAssertEqual(geometry.transform.translation, .unitY * expectedOffset, accuracy: epsilon)
        XCTAssertNil(geometry.mesh)
    }

    func testInsetExtrudedTextIsNotMirrored() throws {
        #if canImport(CoreText)
        let distance = 0.01
        let scene = try evaluate(parse("inset (extrude text \"F\") \(distance)"), delegate: TestDelegate())
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        let mesh = geometry.merged()
        let shape = try XCTUnwrap(Path.text("F", detail: 2).first)
        let expected = Mesh.extrude(shape.inset(by: distance), depth: 1 - distance * 2)

        XCTAssertEqual(mesh.vertexPositionSignature, expected.vertexPositionSignature)
        #endif
    }

    func testInsetNonAxisAlignedExtrudedTextIsNotMirrored() throws {
        #if canImport(CoreText)
        let distance = 0.01
        let rotation = Rotation(pitch: .halfturns(0.125))
        let program = """
        inset (extrude {
            rotate 0 0 0.125
            text "F"
        }) \(distance)
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        let geometry = try XCTUnwrap(scene.children.first)
        guard case .loft = geometry.type else {
            return XCTFail("Expected loft geometry, got \(geometry.type)")
        }
        XCTAssertTrue(geometry.build { false })
        let mesh = geometry.merged()
        let shape = try XCTUnwrap(Path.text("F", detail: 2).first)
        let expected = Mesh.extrude(
            shape.rotated(by: rotation).inset(by: distance),
            depth: 1 - distance * 2
        )

        XCTAssertEqual(mesh.vertexPositionSignature, expected.vertexPositionSignature)
        #endif
    }

    func testInsetFilledTextDoesNotDisappear() throws {
        let program = "inset (fill text \"txt\") 0.01"
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertGreaterThan(mesh.polygons.surfaceArea, 0)
        #endif
    }

    func testInsetFilledTextPreservesCharacterOffsets() throws {
        let program = "inset (fill text \"Hello\") 0.04"
        let originalScene = try evaluate(parse("fill text \"Hello\""), delegate: TestDelegate())
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(originalScene.children.count, 1)
        XCTAssertEqual(scene.children.count, 1)
        let originalGeometry = try XCTUnwrap(originalScene.children.first)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(originalGeometry.build { false })
        XCTAssertTrue(geometry.build { false })
        let original = try XCTUnwrap(originalGeometry.mesh)
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertGreaterThan(mesh.bounds.size.x, original.bounds.size.x * 0.5)
        #endif
    }

    func testInsetFilledTextDoesNotBakeMaterial() throws {
        let program = "inset (fill text \"Hello\") 0.03"
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertEqual(mesh.materials, [nil])
        XCTAssertFalse(mesh.hasVertexColors)
        #endif
    }

    func testInsetFilledTextPreservesSourceMaterial() throws {
        let program = """
        inset (fill {
            color red
            text "Hello"
        }) 0.03
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertEqual(geometry.material, Material(color: .red))
        XCTAssertEqual(mesh.materials, [nil])
        XCTAssertFalse(mesh.hasVertexColors)
        #endif
    }

    func testInsetMeshDoesNotBakeMaterial() throws {
        let program = "inset (mesh fill text \"Hello\") 0.03"
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertEqual(mesh.materials, [nil])
        XCTAssertFalse(mesh.hasVertexColors)
        #endif
    }

    func testInsetMeshPreservesSourceMaterial() throws {
        let program = """
        inset (mesh fill {
            color red
            text "Hello"
        }) 0.03
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertEqual(mesh.materials, [Material(color: .red)])
        XCTAssertFalse(mesh.hasVertexColors)
        #endif
    }

    func testInsetMeshPreservesMixedSourceMaterials() throws {
        let program = """
        inset (mesh union {
            cube {
                color blue
                size 0.8
            }
            cube {
                color red
                position 2
            }
        }) -0.1
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertEqual(Set(mesh.materials.compactMap { $0 as? Material }), [
            Material(color: .blue),
            Material(color: .red),
        ])
    }

    func testInsetExtrudedTextAlongPathPreservesEndCapMaterial() throws {
        let program = """
        inset (extrude {
            color red
            text "e"
            along path {
                point 0
                point 1
                point 1 0 1
            }
        }) 0.01
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        let mesh = try XCTUnwrap(geometry.mesh)
        XCTAssertFalse(mesh.isEmpty)
        let endCapPolygons = mesh.polygons.filter {
            $0.vertices.allSatisfy { $0.position.x.isApproximatelyEqual(to: mesh.bounds.min.x) } ||
                $0.vertices.allSatisfy { $0.position.z.isApproximatelyEqual(to: mesh.bounds.max.z) }
        }
        XCTAssertFalse(endCapPolygons.isEmpty)
        XCTAssertTrue(endCapPolygons.allSatisfy {
            $0.material as? Material == Material(color: .red)
        })
        XCTAssertFalse(mesh.hasVertexColors)
        #endif
    }

    func testExtrusionAlongOpenPath() throws {
        let program = """
        extrude {
            text "hello"
            along path {
                point 0
                curve 1
                point 1 0 1
            }
        }
        """
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 661)
        #endif
    }

    func testExtrusionAlongClosedPath() throws {
        let program = "extrude { text \"hello\" \n along circle }"
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 1712)
        #endif
    }

    func testExtrudedTextAlongNonPlanarCurvedPathIsWatertight() throws {
        let program = """
        detail 64

        extrude {
            text {
                orientation -0.5
                "Hello"
                size 0.1
            }
            along path {
                point 0 0
                curve 0 0 1
                curve 0 1 1
                curve 1 1 1
                point 1 1 2
            }
        }
        """
        let scene = try evaluate(parse(program), delegate: TestDelegate())
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        let geometry = try XCTUnwrap(scene.children.first)
        XCTAssertTrue(geometry.build { false })
        let mesh = geometry.flattened()
        XCTAssertFalse(mesh.isEmpty)
        XCTAssertTrue(mesh.isWatertight)
        XCTAssertTrue(mesh.isConsistentlyWound)
        XCTAssertGreaterThan(mesh.signedVolume, 0)
        #endif
    }

    func testLathe() throws {
        let program = "lathe text \"hello\""
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 1712)
        #endif
    }

    func testDifference() throws {
        let program = "difference cube { size 0.8 } sphere"
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 188)
        #endif
    }

    func testUnion() throws {
        let program = "union cube { size 0.8 } sphere"
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 236)
        #endif
    }

    func testStencil() throws {
        let program = "stencil cube cylinder { size 0.5 2 0.5 \n color red }"
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 38)
        #endif
    }

    func testHull() throws {
        let program = "hull sphere cube { position 1 }"
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 69)
        #endif
    }

    func testProblematicDetailSphereHull() throws {
        for detail in [52, 54, 63] {
            let program = """
            detail \(detail)
            hull {
                sphere {
                    size 0.0018
                    position 0.021920310216782973 0.02192031021678297 0.029
                }
                sphere {
                    size 0.0018
                    position -0.10966680337261942 0.2648919860483299 0
                }
            }
            """
            let scene = try evaluate(parse(program), delegate: TestDelegate())
            XCTAssertEqual(scene.children.count, 1)
            XCTAssertTrue(scene.build { false })
            let geometry = try XCTUnwrap(scene.children.first)
            let mesh = try XCTUnwrap(geometry.mesh)
            XCTAssertTrue(mesh.isWatertight)
            XCTAssertLessThan(mesh.polygons.count, 5_000)
        }
    }

    func testOffCenterHullIsWatertight() throws {
        let program = """
        detail 16
        smoothing 0

        hull {
            position 0 0.15

            cylinder {
                size 0.3 1 0.3
                orientation 0.5
                position 0 0 0.5
            }
            cylinder {
                size 0.3 1 0.3
                orientation 0.5
                position 0 0 -0.5
            }
            cylinder {
                size 0.2 1.1 0.2
                orientation 0.5
                position 0 0 0.5
            }
            cylinder {
                size 0.2 1.1 0.2
                orientation 0.5
                position 0 0 -0.5
            }
        }
        """
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
    }

    func testMinkowski() throws {
        let program = "minkowski sphere { size 0.1 } cube"
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        #if canImport(CoreText)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 182)
        #endif
    }

    func testDifference2() throws {
        let program = """
        detail 190

        define RADIUSBOTTOM    94
        define RADIUSTOP       104.8
        define HEIGHT          64
        define DEPTH           (HEIGHT / 2)
        define THICKNESS       (RADIUSBOTTOM / 10)
        define WALLTHICKNESS   1
        define DIAMETER        (THICKNESS * (pi / 2) - WALLTHICKNESS * 2)

        define LATHE lathe path {
            point 0 HEIGHT
            point (RADIUSTOP / 2 + THICKNESS)  HEIGHT
            point (RADIUSBOTTOM / 2 + THICKNESS)  0
            point 0  0
        }

        define CUBE cube {
            size (RADIUSTOP + THICKNESS * 2 + WALLTHICKNESS) (HEIGHT - DEPTH) (RADIUSTOP + THICKNESS * 2 + WALLTHICKNESS)
            position 0  ((HEIGHT + DIAMETER) - ((HEIGHT - DEPTH) / 2))
        }

        define CONE cone {
            orientation 1
            size (RADIUSTOP + THICKNESS * 2 + WALLTHICKNESS * 2)  (THICKNESS * 2)
            position 0  (HEIGHT / 2 + THICKNESS / 2)
        }

        print LATHE.polygons.count
        print CUBE.polygons.count
        print CONE.polygons.count
                        
        difference LATHE CUBE CONE
        """
        let delegate = TestDelegate()
        let scene = try evaluate(parse(program), delegate: delegate)
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertEqual(scene.children.first?.isWatertight { false }, true)
        XCTAssertEqual(scene.children.first?.polygons { false }.count, 1330) // TODO: why isn't this 1140?
        XCTAssertEqual(delegate.log, [570.0, 6.0, 950.0])
    }

    func testExamples() throws {
        XCTAssertFalse(exampleURLs.isEmpty)
        XCTAssertFalse(testShapesURLs.isEmpty)
        for url in exampleURLs + testShapesURLs {
            let name = url.lastPathComponent
            let input = try String(contentsOf: url)
            let program = try parse(input)
            let delegate = TestDelegate(directory: url.deletingLastPathComponent())
            let context = EvaluationContext(source: program.source, delegate: delegate)
            XCTAssertNoThrow(try program.evaluate(in: context), "\(name) errored")
            for (i, geometry) in context.state.children.compactMap({
                $0.value as? Geometry
            }).enumerated() {
                XCTAssert(geometry.isWatertight { false }, """
                \(name) object \(i + 1) was not watertight
                """)
            }
        }
    }
}

private extension Mesh {
    var hasConsistentCapDirections: Bool {
        let capPolygons = polygons.filter {
            $0.endCapZ(in: bounds) != nil
        }
        let capsByZ = Dictionary(grouping: capPolygons) {
            $0.endCapZ(in: bounds) == bounds.min.z
        }
        return capsByZ.values.allSatisfy { polygons in
            guard let normal = polygons.first?.plane.normal.z.sign else {
                return true
            }
            return polygons.allSatisfy {
                $0.plane.normal.z.sign == normal
            }
        }
    }

    func endCapArea(at z: Double) -> Double {
        polygons.filter {
            $0.vertices.allSatisfy { abs($0.position.z - z) < epsilon }
        }.reduce(0) {
            $0 + $1.area
        }
    }
}

private extension Collection<Euclid.Polygon> {
    var containsIntersections: Bool {
        let polygons = Array(self)
        for i in polygons.indices {
            for j in polygons.indices.dropFirst(i + 1) {
                if polygons[i].hasInteriorIntersection(with: polygons[j]) {
                    return true
                }
            }
        }
        return false
    }
}

private extension Mesh {
    var vertexPositionSignature: [String] {
        Set(polygons.flatMap { polygon in
            polygon.vertices.map { vertex in
                let p = vertex.position
                return "\(p.x.roundedForSignature),\(p.y.roundedForSignature),\(p.z.roundedForSignature)"
            }
        }).sorted()
    }
}

private extension Double {
    var roundedForSignature: Double {
        (self * 1e8).rounded() / 1e8
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

private extension Euclid.Polygon {
    func hasInteriorIntersection(with other: Euclid.Polygon) -> Bool {
        let sharedVertices = Set(vertices.map(\.position)).intersection(other.vertices.map(\.position))
        if sharedVertices.count >= 2 {
            return false
        }
        return vertices.contains {
            !sharedVertices.contains($0.position) && other.intersects($0.position)
        } || other.vertices.contains {
            !sharedVertices.contains($0.position) && intersects($0.position)
        }
    }

    func endCapZ(in bounds: Bounds) -> Double? {
        if vertices.allSatisfy({ abs($0.position.z - bounds.min.z) < epsilon }) {
            return bounds.min.z
        }
        if vertices.allSatisfy({ abs($0.position.z - bounds.max.z) < epsilon }) {
            return bounds.max.z
        }
        return nil
    }
}
