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

    func testMissingAssetsWarnAndAllowGeometryCreation() throws {
        #if targetEnvironment(simulator) || !os(iOS)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let image = directory.appendingPathComponent("Missing.png").path
        let font = directory.appendingPathComponent("Missing.ttf").path
        let source = """
        texture "\(image)"
        normals import "\(image)"
        font "\(font)"
        font import "\(font)"
        cube
        """
        let scene = try evaluate(parse(source), delegate: nil)
        XCTAssertEqual(scene.warnings, [
            "Texture '\(image)' not found on line 1.",
            "Texture '\(image)' not found on line 2.",
            "Font file '\(font)' not found on line 3.",
            "Font file '\(font)' not found on line 4.",
        ])
        XCTAssertEqual(scene.children.count, 1)
        XCTAssertNil(scene.children.first?.material.texture)
        #endif
    }

    func testMissingAssetWarningOmitsCurrentDocumentName() throws {
        #if targetEnvironment(simulator) || !os(iOS)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("Main.shape")
        let source = """
        cube {
            texture "Missing.png"
        }
        """
        let scene = try evaluate(parse(source, at: url), delegate: nil)
        XCTAssertEqual(scene.warnings, [
            "Texture 'Missing.png' not found on line 2.",
        ])
        #endif
    }

    func testMissingAssetWarningIncludesImportedFileAndLine() throws {
        #if targetEnvironment(simulator) || !os(iOS)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Child.shape")
        try """
        // Missing texture in an imported document
        for 1 to 2 {
            texture "Missing.png"
            cube
        }
        """.write(to: url, atomically: true, encoding: .utf8)
        let scene = try evaluate(
            parse("import \"\(url.path)\"", at: directory.appendingPathComponent("Main.shape")),
            delegate: nil
        )
        XCTAssertEqual(scene.warnings, [
            "Child.shape: Texture 'Missing.png' not found on line 3.",
        ])
        XCTAssertEqual(scene.children.count, 2)
        #endif
    }

    func testAssetPermissionErrorsRemainErrors() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (command, fileExtension) in [("texture", "png"), ("font", "ttf")] {
            let url = directory.appendingPathComponent("Restricted.\(fileExtension)")
            try Data().write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
            guard !FileManager.default.isReadableFile(atPath: url.path) else {
                throw XCTSkip("This environment can read files without read permission")
            }
            let program = try parse("\(command) \"\(url.path)\"")
            let context = EvaluationContext(source: program.source, delegate: nil)
            XCTAssertThrowsError(try program.evaluate(in: context)) { error in
                guard let error = error as? RuntimeError,
                      case .fileAccessRestricted = error.type
                else {
                    return XCTFail("Expected a file access error, got \(error)")
                }
            }
            XCTAssertTrue(context.warnings.isEmpty)
        }
    }

    func testMissingModelRemainsAnError() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("stl").path
        XCTAssertThrowsError(try evaluate(parse("import \"\(path)\""), delegate: nil))
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
        let mesh = try XCTUnwrap(geometry.mesh())
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
        let mesh2 = try XCTUnwrap(geometry2.mesh())
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

    #if canImport(SceneKit)
    func testUnsupportedAndCorruptModelImportsExplainInvalidFormat() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let delegate = TestDelegate(directory: directory)
        let context = EvaluationContext(source: "", delegate: delegate)

        for name in ["Bool2D.foo", "Invalid.scn"] {
            let url = directory.appendingPathComponent(name)
            try "invalid model data".write(to: url, atomically: true, encoding: .utf8)
            XCTAssertThrowsError(try context.importFile(at: name)) { error in
                guard case let RuntimeErrorType.fileParsingError(path, errorURL, message) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(path, name)
                XCTAssertEqual(errorURL, url)
                XCTAssertEqual(
                    message,
                    "The file format is unsupported, or the file contains invalid 3D model data."
                )
            }
        }
    }
    #endif

    func testMissingUnsupportedFileStillReportsFileNotFound() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let delegate = TestDelegate(directory: directory)
        let context = EvaluationContext(source: "", delegate: delegate)
        XCTAssertThrowsError(try context.importFile(at: "Missing.foo")) { error in
            guard case let RuntimeErrorType.fileNotFound(path, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, "Missing.foo")
        }
    }

    func testImportsWithoutDelegateResolveAbsoluteRelativeAndFinderPaths() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("foo:bar.txt")
        try "contents".write(to: url, atomically: true, encoding: .utf8)
        let context = EvaluationContext(source: "", delegate: nil)
        context.state.baseURL = directory.appendingPathComponent("main.shape")

        XCTAssertEqual(try context.importFile(at: url.path), "contents")
        XCTAssertEqual(try context.importFile(at: "foo:bar.txt"), "contents")
        XCTAssertEqual(try context.importFile(at: "foo/bar.txt"), "contents")
        XCTAssertThrowsError(try context.importFile(at: "missing.txt")) { error in
            guard case let RuntimeErrorType.fileNotFound(path, url) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, "missing.txt")
            XCTAssertEqual(url, directory.appendingPathComponent("missing.txt"))
        }
    }

    func testImportFileWithFinderSlashInName() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("foo:bar.txt")
        try "fallback".write(to: url, atomically: true, encoding: .utf8)

        let delegate = TestDelegate(directory: directory)
        let context = EvaluationContext(source: "", delegate: delegate)
        XCTAssertEqual(try context.importFile(at: "foo/bar.txt"), "fallback")
    }

    func testImportFilePrefersRealDirectoryPathOverFinderSlashName() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let subdirectory = directory.appendingPathComponent("foo", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try "normal".write(
            to: subdirectory.appendingPathComponent("bar.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "fallback".write(
            to: directory.appendingPathComponent("foo:bar.txt"),
            atomically: true,
            encoding: .utf8
        )

        let delegate = TestDelegate(directory: directory)
        let context = EvaluationContext(source: "", delegate: delegate)
        XCTAssertEqual(try context.importFile(at: "foo/bar.txt"), "normal")
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

    func testOversizedMeshImportsAreRejected() throws {
        for fileExtension in ["stl", "stla", "obj", "off"] {
            try withSparseFile(extension: fileExtension, size: FileSizeLimit.mesh + 1) { url in
                let context = EvaluationContext(source: "", delegate: nil)
                XCTAssertThrowsError(try context.importGeometry(at: url)) { error in
                    guard case let FileError.tooLarge(errorURL, maximumSize) = error else {
                        XCTFail("Unexpected error: \(error)")
                        return
                    }
                    XCTAssertEqual(errorURL, url)
                    XCTAssertEqual(maximumSize, FileSizeLimit.mesh)
                }
            }
        }
    }

    func testMeshImportSizeErrorIsSurfaced() throws {
        try withSparseFile(extension: "obj", size: FileSizeLimit.mesh + 1) { url in
            let delegate = TestDelegate(directory: url.deletingLastPathComponent())
            let context = EvaluationContext(source: "", delegate: delegate)
            XCTAssertThrowsError(try context.importFile(at: url.lastPathComponent)) { error in
                guard case let RuntimeErrorType.fileParsingError(_, at, message) = error else {
                    XCTFail("Unexpected error: \(error)")
                    return
                }
                XCTAssertEqual(at, url)
                XCTAssertTrue(message.contains("size limit"))
            }
        }
    }
}
