//
//  ImportExportTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 19/06/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

@testable import Euclid
@testable import ShapeScript
import XCTest

#if canImport(SceneKit)
import SceneKit
#endif

final class ImportExportTests: XCTestCase {
    private func withSparseFile(
        extension fileExtension: String,
        size: Int,
        _ body: (URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Oversized.\(fileExtension)")
        XCTAssert(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
        try body(url)
    }

    // MARK: Geometry

    func testCog() throws {
        let source = """
        define cog {
            option teeth 6
            path {
                define step 1 / teeth
                for 1 to teeth {
                    point -0.02 0.8
                    point 0.05 1
                    rotate step
                    point -0.05 1
                    point 0.02 0.8
                    rotate step
                }
                point -0.02 0.8
            }
        }

        difference {
            extrude {
                size 1 1 0.5
                cog { teeth 8 }
            }
            rotate 0 0 0.5
            cylinder
        }
        """
        let program = try parse(source)
        let context = EvaluationContext(source: program.source, delegate: nil)
        XCTAssertNoThrow(try program.evaluate(in: context))
        let geometry = try XCTUnwrap(context.state.children.first?.value as? Geometry)
        XCTAssert(geometry.build { false })
        let mesh = try XCTUnwrap(geometry.mesh)
        let polygons = mesh.polygons
        XCTAssertEqual(polygons.count, 96)
        XCTAssert(polygons.areWatertight)
        let triangles = mesh.triangulate().polygons
        XCTAssertEqual(triangles.count, 256)
        XCTAssert(triangles.areWatertight)

        #if canImport(SceneKit)
        geometry.scnBuild(with: .default)
        let node = SCNNode(geometry)
        let geometry2 = try Geometry(node)
        XCTAssert(geometry2.build { false })
        let mesh2 = try XCTUnwrap(geometry2.mesh)
        XCTAssertEqual(mesh2.polygons.count, 256)
        XCTAssert(mesh2.isWatertight)
        #endif
    }

    // MARK: JSON

    func testParseJSONValues() throws {
        let source = """
        [
            "hello",
            3,
            3.5,
            true,
            null,
            [1, 2, 3],
            {
                "foo": 2,
                "bar": true,
            }
        ]
        """
        let json = try JSONSerialization
            .jsonObject(with: XCTUnwrap(source.data(using: .utf8)))
        let value = Value(json: json)
        XCTAssertEqual(value, [
            "hello",
            3,
            3.5,
            true,
            [],
            [1, 2, 3],
            [
                "bar": true,
                "foo": 2,
            ],
        ])
        XCTAssertEqual(value["seventh"]?["foo"], 2)
    }

    func testMalformedJSON() throws {
        let json = """
        [
            "🙃,
            "foo"
        ]
        """
        XCTAssertThrowsError(try Value(jsonData: XCTUnwrap(json.data(using: .utf8)))) { error in
            let error = try? XCTUnwrap(error as? ParserError)
            guard case let .custom(message, _, range)? = error?.type else {
                XCTFail()
                return
            }
            if let range {
                XCTAssertEqual(message, "Unescaped control character")
                XCTAssertEqual(range.lowerBound, json.range(of: "🙃,")?.upperBound)
            } else {
                XCTAssert(message.hasPrefix("Unescaped control character") ||
                    message.hasPrefix("Badly formed array"))
            }
        }
    }

    func testImportJSONGeometryDescriptionAsMesh() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("triangle.json")
        let json = """
        {
            "name": "triangle",
            "polygons": [
                {
                    "points": [
                        { "position": [0, 0] },
                        { "position": [1, 0] },
                        { "position": [0, 1] }
                    ]
                }
            ]
        }
        """
        try json.write(to: url, atomically: true, encoding: .utf8)

        let source = #"import "triangle.json""#
        let program = try parse(source)
        guard case let .expression(expressionType) = program.statements.first?.type else {
            XCTFail("Expression not found")
            return
        }
        let expression = Expression(
            type: expressionType,
            range: program.statements.first?.range ?? source.startIndex ..< source.endIndex
        )
        let delegate = TestDelegate(directory: directory)
        let context = EvaluationContext(source: source, delegate: delegate)
        let value = try expression.evaluate(as: .mesh, for: "", in: context)
        let geometry = try XCTUnwrap(value.value as? Geometry)

        XCTAssertEqual(delegate.imports, ["triangle.json"])
        XCTAssertEqual(geometry.name, "triangle")
        XCTAssertEqual(geometry.polygons { false }.count, 2)
        XCTAssertEqual(geometry.polygons { false }.first?.vertices.map(\.position), [
            Vector(0, 0, 0),
            Vector(1, 0, 0),
            Vector(0, 1, 0),
        ])
    }

    func testImportObjPackageDirectoryAsMesh() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let packageURL = directory.appendingPathComponent("Sphere.obj", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let objURL = packageURL.appendingPathComponent("Sphere.obj")
        try """
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f 1 2 3
        """.write(to: objURL, atomically: true, encoding: .utf8)

        let source = #"import "Sphere.obj""#
        let program = try parse(source)
        guard case let .expression(expressionType) = program.statements.first?.type else {
            XCTFail("Expression not found")
            return
        }
        let expression = Expression(
            type: expressionType,
            range: program.statements.first?.range ?? source.startIndex ..< source.endIndex
        )
        let delegate = TestDelegate(directory: directory)
        let context = EvaluationContext(source: source, delegate: delegate)
        let value = try expression.evaluate(as: .mesh, for: "", in: context)
        let geometry = try XCTUnwrap(value.value as? Geometry)

        XCTAssertEqual(delegate.imports, ["Sphere.obj"])
        XCTAssertEqual(geometry.polygons { false }.count, 2)
        XCTAssertEqual(geometry.polygons { false }.first?.vertices.map(\.position), [
            Vector(0, 0, 0),
            Vector(1, 0, 0),
            Vector(0, 1, 0),
        ])
    }

    // MARK: Import limits

    func testOversizedShapeTextAndJSONImportsAreRejected() throws {
        for (fileExtension, limit) in [
            ("shape", FileSizeLimit.shape),
            ("txt", FileSizeLimit.text),
            ("json", FileSizeLimit.json),
        ] {
            try withSparseFile(extension: fileExtension, size: limit + 1) { url in
                let delegate = TestDelegate(directory: url.deletingLastPathComponent())
                let context = EvaluationContext(
                    source: "",
                    delegate: delegate
                )
                XCTAssertThrowsError(try context.importFile(at: url.lastPathComponent)) { error in
                    guard case let RuntimeErrorType.fileParsingError(_, at, message) = error else {
                        XCTFail("Unexpected error: \(error)")
                        return
                    }
                    XCTAssertEqual(at, url)
                    XCTAssert(message.contains("size limit"))
                }
            }
        }
    }

    func testOversizedImageImportIsRejected() throws {
        try withSparseFile(extension: "png", size: FileSizeLimit.image + 1) { url in
            XCTAssertThrowsError(try Texture.file(name: url.lastPathComponent, url: url)) { error in
                guard case let FileError.tooLarge(errorURL, maximumSize) = error else {
                    XCTFail("Unexpected error: \(error)")
                    return
                }
                XCTAssertEqual(errorURL, url)
                XCTAssertEqual(maximumSize, FileSizeLimit.image)
            }
        }
    }
}
