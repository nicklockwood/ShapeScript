//
//  ImportFragmentTests.swift
//  ShapeScriptTests
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

@testable import Euclid
@testable import ShapeScript
import XCTest
#if canImport(SceneKit)
import ImageIO
import SceneKit
#endif

final class ImportFragmentTests: XCTestCase {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    func testShapeSelectionPreservesTransformsMaterialsAndDescendants() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("assembly.shape")
            try """
            group {
                name "assembly"
                position 10 20 0
                size 2
                color red
                group {
                    name "wheel"
                    position 3 0 0
                    cube { name "hub" }
                }
                sphere { name "body" }
            }
            """.write(to: url, atomically: true, encoding: .utf8)
            let scene = try evaluate(parse("import \"\(url.path)#wheel\""), delegate: nil)
            XCTAssertEqual(scene.children.count, 1)
            let wheel = try XCTUnwrap(scene.children.first)
            XCTAssertEqual(wheel.name, "wheel")
            XCTAssertEqual(wheel.children.map(\.name), ["hub"])
            XCTAssertEqual(wheel.material.color, .red)
            XCTAssertTrue(scene.build { false })
            XCTAssertEqual(scene.geometry.merged().bounds.center, [16, 20, 0])
            XCTAssertEqual(scene.geometry.merged().bounds.size, [2, 2, 2])
        }
    }

    func testShapeFragmentsSelectNamedPaths() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("profiles.shape")
            try """
            group {
                position 10 0
                path {
                    name "outline"
                    position 2 0
                    square
                }
                circle { name "hole" }
                text {
                    name "label"
                    "Hello"
                }
            }
            """.write(to: url, atomically: true, encoding: .utf8)
            for name in ["outline", "hole", "label"] {
                let scene = try evaluate(parse("import \"\(url.path)#\(name)\""), delegate: nil)
                let geometry = try XCTUnwrap(scene.children.first)
                XCTAssertEqual(scene.children.count, 1)
                XCTAssertEqual(geometry.name, name)
                XCTAssertTrue(geometry.isPath)
                if name == "outline" {
                    XCTAssertEqual(geometry.paths(pretransformed: true).first?.bounds.center, [12, 0, 0])
                }
            }
        }
    }

    func testShapeFragmentsRespectOptionsAndDoNotMixCachedSelections() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("parts.shape")
            try """
            option width 1
            cube {
                name "small part"
                size width
            }
            cube {
                name "large"
                size width * 2
            }
            """.write(to: url, atomically: true, encoding: .utf8)
            let context = EvaluationContext(source: "", delegate: nil)
            for (id, width, expected) in [("small%20part", 3.0, 3.0), ("large", 4, 8), ("small%20part", 5, 5)] {
                guard case let .mesh(geometry) = try context.importFile(
                    at: url.path + "#" + id,
                    options: ["width": .number(width)]
                ) else {
                    return XCTFail("Expected geometry")
                }
                XCTAssertEqual(geometry.overestimatedBounds.size.x, expected)
                XCTAssertTrue(context.state.children.isEmpty)
            }
        }
    }

    func testMissingAndAmbiguousShapeNamesAreErrors() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("parts.shape")
            try "cube { name \"wheel\" }\ncube { name \"wheel\" }".write(to: url, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try evaluate(parse("import \"\(url.path)#whee\""), delegate: nil)) { error in
                XCTAssertEqual(ProgramError(error).hint, "Did you mean '#wheel'?")
            }
            XCTAssertThrowsError(try evaluate(parse("import \"\(url.path)#wheel\""), delegate: nil)) { error in
                XCTAssertTrue(ProgramError(error).message.contains("ambiguous"))
            }
        }
    }

    func testUnselectedShapeStillEvaluatesAndFragmentDoesNotHideErrors() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("parts.shape")
            try "cube { name \"wheel\" }\nunknownSymbol".write(to: url, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try evaluate(parse("import \"\(url.path)#wheel\""), delegate: nil)) { error in
                XCTAssertTrue(ProgramError(error).underlyingError.message.contains("unknownSymbol"))
            }
        }
    }

    func testJSONFragmentsRemainLiteralFilenames() {
        XCTAssertEqual(ImportFileReference("parts.json#item").path, "parts.json#item")
        XCTAssertNil(ImportFileReference("parts.json#item").id)
        XCTAssertEqual(ImportFileReference("part#1.shape").path, "part#1.shape")
        XCTAssertEqual(ImportType(URL(fileURLWithPath: "part.shape#wheel")), .shape)
    }

    func testOBJObjectsPreserveGroupsNegativeIndicesAndMaterials() throws {
        let geometry = try XCTUnwrap(Geometry.namedOBJ("""
        o wheel
        v 0 0 0
        v 2 0 0
        v 0 2 0
        g rim
        usemtl red
        f -3 -2 -1
        o body
        v 10 0 0
        v 12 0 0
        v 10 2 0
        usemtl blue
        f 4 5 6
        """, materials: ["red": Material(color: .red), "blue": Material(color: .blue)], isCancelled: { false }))
        XCTAssertEqual(geometry.children.map(\.name), ["wheel", "body"])
        XCTAssertEqual(geometry.children[0].children.map(\.name), ["rim"])
        XCTAssertTrue(geometry.build { false })
        XCTAssertEqual(geometry.children[0].merged().bounds.max, [2, 2, 0])
        XCTAssertTrue(geometry.children[0].merged().polygons.allSatisfy { ($0.material as? Material)?.color == .red })
        XCTAssertTrue(geometry.children[1].merged().polygons.allSatisfy { ($0.material as? Material)?.color == .blue })
    }

    func testUnnamedSTLRejectsFragment() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("cube.stl")
            try Mesh.cube().stlData().write(to: url)
            XCTAssertThrowsError(try evaluate(parse("import \"\(url.path)#wheel\""), delegate: nil)) { error in
                XCTAssertTrue(ProgramError(error).message.contains("Geometry '#wheel' not found"))
            }
        }
    }

    #if canImport(SceneKit)

    func testOBJMissingMaterialLibraryStillImportsGeometry() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("missing.obj")
            try "mtllib missing.mtl\nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n"
                .write(to: url, atomically: true, encoding: .utf8)
            let scene = try evaluate(parse("import \"\(url.path)\""), delegate: nil)
            XCTAssertTrue(scene.build { false })
            XCTAssertFalse(scene.geometry.merged().isEmpty)
        }
    }

    #if canImport(SceneKit)
    func testOBJDiffuseTextureTintPreservesAlpha() throws {
        try withDirectory { directory in
            let image = try XCTUnwrap(CGImage(
                width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: XCTUnwrap(CGDataProvider(data: Data([128, 64, 32, 128, 32, 64, 128, 255]) as CFData)),
                decode: nil, shouldInterpolate: false, intent: .defaultIntent
            ))
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
                directory.appendingPathComponent("paint.png") as CFURL, "public.png" as CFString, 1, nil
            ))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            try "newmtl paint\nKd 0.2 0.2 0.2\nmap_Kd paint.png\nKd 0.5 0.25 0.75\nd 0.4\n".write(
                to: directory.appendingPathComponent("paint.mtl"), atomically: true, encoding: .utf8
            )
            for (object, fragment) in [("", ""), ("o triangle\n", "#triangle")] {
                let url = directory.appendingPathComponent("paint.obj")
                try ("mtllib paint.mtl\n" + object + "v 0 0 0\nv 1 0 0\nv 0 1 0\nusemtl paint\nf 1 2 3\n")
                    .write(to: url, atomically: true, encoding: .utf8)
                let scene = try evaluate(parse("import \"\(url.path)\(fragment)\""), delegate: nil)
                XCTAssertTrue(scene.build { false })
                let material = try XCTUnwrap(scene.geometry.merged().polygons.first?.material as? Material)
                let texture = try XCTUnwrap(material.texture)
                let source = try XCTUnwrap(CGImageSourceCreateWithData(texture.data as CFData, nil))
                let result = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                var pixels = [UInt8](repeating: 0, count: 8)
                let context = try XCTUnwrap(CGContext(
                    data: &pixels, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 8,
                    space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(result, in: CGRect(x: 0, y: 0, width: 2, height: 1))
                let tint = Color(red: 0.5, green: 0.25, blue: 0.75).toLinear()
                for (index, input) in [
                    Color(red: 1, green: 0.5, blue: 0.25),
                    Color(red: 32 / 255.0, green: 64 / 255.0, blue: 128 / 255.0),
                ].enumerated() {
                    let expected = (input.toLinear() * tint).toSRGB()
                    let alpha = index == 0 ? 128.0 : 255.0
                    for (channel, value) in [expected.red, expected.green, expected.blue].enumerated() {
                        XCTAssertEqual(Double(pixels[index * 4 + channel]), value * alpha, accuracy: 1.1)
                    }
                    XCTAssertEqual(Double(pixels[index * 4 + 3]), alpha)
                }
                XCTAssertEqual(material.averageOpacity, (128 / 255.0 + 1) / 2 * 0.4, accuracy: 0.002)
            }
        }
    }

    func testOBJOpacityChannelsAndDissolveWithNamedFragments() throws {
        try withDirectory { directory in
            let bytes: [UInt8] = [64, 128, 192, 255]
            let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
            let image = try XCTUnwrap(CGImage(
                width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            ))
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
                directory.appendingPathComponent("opacity.png") as CFURL, "public.png" as CFString, 1, nil
            ))
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            for (channel, value) in [("r", 64.0), ("g", 128.0), ("b", 192.0), ("m", 255.0)] {
                try "newmtl paint\nKd 0.5 0.25 0.75\nd 0.4\nmap_d -imfchan \(channel) opacity.png\n".write(
                    to: directory.appendingPathComponent("paint.mtl"), atomically: true, encoding: .utf8
                )
                for (object, fragment) in [("", ""), ("o triangle\n", ""), ("o triangle\n", "#triangle")] {
                    let url = directory.appendingPathComponent("paint.obj")
                    try ("mtllib paint.mtl\n" + object + "v 0 0 0\nv 1 0 0\nv 0 1 0\nusemtl paint\nf 1 2 3\n")
                        .write(to: url, atomically: true, encoding: .utf8)
                    let scene = try evaluate(parse("import \"\(url.path)\(fragment)\""), delegate: nil)
                    XCTAssertTrue(scene.build { false })
                    let polygons = scene.geometry.merged().polygons
                    XCTAssertFalse(polygons.isEmpty)
                    for polygon in polygons {
                        let material = try XCTUnwrap(polygon.material as? Material)
                        XCTAssertEqual(material.averageOpacity, value / 255 * 0.4, accuracy: 1 / 255.0, channel)
                        XCTAssertEqual(try XCTUnwrap(material.color).red, 0.5, accuracy: 1e-6)
                    }
                }
            }
        }
    }
    #endif

    func testOBJMaterialMidtonesWithAndWithoutObjectNames() throws {
        try withDirectory { directory in
            try "newmtl paint\nKd 0.5 0.25 0.75\nd 0.4\n".write(
                to: directory.appendingPathComponent("paint.mtl"), atomically: true, encoding: .utf8
            )
            for object in ["", "o triangle\n"] {
                let url = directory.appendingPathComponent("paint.obj")
                try ("mtllib paint.mtl\n" + object + "v 0 0 0\nv 1 0 0\nv 0 1 0\nusemtl paint\nf 1 2 3\n")
                    .write(to: url, atomically: true, encoding: .utf8)
                let scene = try evaluate(parse("import \"\(url.path)\""), delegate: nil)
                XCTAssertTrue(scene.build { false })
                let polygons = scene.geometry.merged().polygons
                XCTAssertFalse(polygons.isEmpty)
                for polygon in polygons {
                    let material = try XCTUnwrap(polygon.material as? Material)
                    let color = try XCTUnwrap(material.color)
                    XCTAssertEqual(color.red, 0.5, accuracy: 1e-6)
                    XCTAssertEqual(color.green, 0.25, accuracy: 1e-6)
                    XCTAssertEqual(color.blue, 0.75, accuracy: 1e-6)
                    XCTAssertEqual(material.averageOpacity, 0.4, accuracy: 1e-6)
                }
            }
        }
    }

    func testOBJFragmentPreservesMaterialLibrary() throws {
        try withDirectory { directory in
            try "newmtl red\nKd 1 0 0\n".write(
                to: directory.appendingPathComponent("parts.mtl"), atomically: true, encoding: .utf8
            )
            let url = directory.appendingPathComponent("parts.obj")
            try """
            mtllib parts.mtl
            o wheel
            v 0 0 0
            v 2 0 0
            v 0 2 0
            usemtl red
            f 1 2 3
            """.write(to: url, atomically: true, encoding: .utf8)
            let scene = try evaluate(parse("import \"\(url.path)#wheel\""), delegate: nil)
            XCTAssertTrue(scene.build { false })
            let polygons = scene.geometry.merged().polygons
            XCTAssertFalse(polygons.isEmpty)
            for polygon in polygons {
                let color = try XCTUnwrap((polygon.material as? Material)?.color)
                XCTAssertEqual(color.red, 1, accuracy: 1e-6)
                XCTAssertEqual(color.green, 0, accuracy: 1e-6)
                XCTAssertEqual(color.blue, 0, accuracy: 1e-6)
            }
        }
    }

    func testNamedModelSelectionPreservesTransformAndMaterial() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("assembly.scn")
            let model = SCNScene()
            let parent = SCNNode()
            parent.name = "assembly"
            parent.position = SCNVector3(10, 20, 0)
            parent.scale = SCNVector3(2, 2, 2)
            let wheel = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
            wheel.name = "wheel"
            wheel.position = SCNVector3(3, 0, 0)
            wheel.geometry?.firstMaterial?.diffuse.contents = OSColor.red
            parent.addChildNode(wheel)
            model.rootNode.addChildNode(parent)
            XCTAssertTrue(model.write(to: url, options: nil, delegate: nil, progressHandler: nil))
            let context = EvaluationContext(source: "", delegate: nil)
            for name in ["wheel", "assembly", "wheel"] {
                guard case let .mesh(geometry) = try context.importFile(at: url.path + "#" + name) else {
                    return XCTFail("Expected geometry")
                }
                XCTAssertEqual(geometry.name, name)
                XCTAssertTrue(geometry.build { false })
                XCTAssertEqual(geometry.merged().bounds.center, [16, 20, 0])
                XCTAssertEqual(geometry.merged().bounds.size, [2, 2, 2])
                XCTAssertTrue(geometry.merged().polygons.allSatisfy { ($0.material as? Material)?.color == .red })
            }
        }
    }

    #endif

    func testOBJGroupNamesCanBeSelectedFromShape() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("parts.obj")
            try """
            v 0 0 0
            v 2 0 0
            v 0 2 0
            v 10 0 0
            v 12 0 0
            v 10 2 0
            g wheel
            f 1 2 3
            g body
            f 4 5 6
            """.write(to: url, atomically: true, encoding: .utf8)
            let shape = try evaluate(parse("import \"\(url.path)#wheel\""), delegate: nil)
            XCTAssertTrue(shape.build { false })
            XCTAssertEqual(shape.geometry.merged().bounds.max, [2, 2, 0])
            let body = try evaluate(parse("import \"\(url.path)#body\""), delegate: nil)
            XCTAssertTrue(body.build { false })
            XCTAssertEqual(body.geometry.merged().bounds.min, [10, 0, 0])
        }
    }
}
