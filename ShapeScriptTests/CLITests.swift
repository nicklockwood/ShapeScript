//
//  CLITests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 17/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

#if os(macOS) || os(Linux)

import XCTest

final class CLITests: XCTestCase {
    func testRootHelpListsSubcommands() throws {
        let result = try runExecutable(["--help"])
        XCTAssertEqual(result.status, 0, result.failureMessage)
        XCTAssertTrue(result.output.contains("USAGE: shapescript"))
        XCTAssertTrue(result.output.contains("SUBCOMMANDS:"))
        XCTAssertTrue(result.output.contains("check"))
        XCTAssertTrue(result.output.contains("info"))
        XCTAssertTrue(result.output.contains("export"))
    }

    func testRootCommandIncludesTitleAndCopyrightHeader() throws {
        let result = try runExecutable([])
        XCTAssertEqual(result.status, 0, result.failureMessage)
        XCTAssertTrue(result.output.contains("ShapeScript, version"))
        XCTAssertTrue(result.output.contains("Copyright (c) 2023-2026 Nick Lockwood"))
        XCTAssertTrue(result.output.contains("USAGE: shapescript"))
    }

    func testVersionArgumentPrintsVersion() throws {
        let result = try runExecutable(["--version"])
        XCTAssertEqual(result.status, 0, result.failureMessage)
        XCTAssertTrue(result.output.contains("."))
    }

    func testUnknownShortOptionFails() throws {
        let result = try runExecutable(["-v"])
        XCTAssertNotEqual(result.status, 0, result.failureMessage)
        XCTAssertTrue(result.output.contains("Unknown option '-v'"), result.failureMessage)
    }

    func testCheckHelpDescribesCheckCommand() throws {
        let result = try runExecutable(["check", "--help"])
        XCTAssertEqual(result.status, 0, result.failureMessage)
        XCTAssertTrue(result.output.contains("USAGE: shapescript check <input-path>"))
        XCTAssertTrue(result.output.contains("Input .shape file."))
        XCTAssertFalse(result.output.contains("--output"))
    }

    func testInfoHelpDescribesInfoCommand() throws {
        let result = try runExecutable(["info", "--help"])
        XCTAssertEqual(result.status, 0, result.failureMessage)
        XCTAssertTrue(result.output.contains("USAGE: shapescript info <input-path>"))
        XCTAssertTrue(result.output.contains("Input .shape file."))
        XCTAssertFalse(result.output.contains("--output"))
    }

    func testExportHelpDescribesExportCommand() throws {
        let result = try runExecutable(["help", "export"])
        XCTAssertEqual(result.status, 0, result.failureMessage)
        XCTAssertTrue(result.output.contains("USAGE: shapescript export <input-path>"))
        XCTAssertTrue(result.output.contains("--output"))
        XCTAssertTrue(result.output.contains("--z-up"))
    }

    func testSupportsRootOutputSyntax() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let outputURL = directory.appendingPathComponent("custom.stl")
            let result = try runExecutable([
                inputURL.lastPathComponent,
                "--output",
                outputURL.lastPathComponent,
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func testSupportsLegacyInfoSyntax() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let result = try runExecutable([inputURL.lastPathComponent], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(result.output.contains("Building geometry ..."), result.failureMessage)
        }
    }

    func testSupportsExistingExtensionlessLegacyInputSyntax() throws {
        try withTemporaryFile(named: "model") { directory, inputURL in
            let result = try runExecutable([inputURL.lastPathComponent], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.firstOutputLine, "Error: Unsupported file type ''")
        }
    }

    func testDoesNotTreatMissingExtensionlessArgumentAsLegacyInput() throws {
        try withTemporaryDirectory { directory in
            let result = try runExecutable(["nonexistant"], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.firstOutputLine, "Error: Unexpected argument 'nonexistant'")
        }
    }

    func testSupportsLegacyExportSyntax() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let outputURL = directory.appendingPathComponent("model.stl")
            let result = try runExecutable([
                inputURL.lastPathComponent,
                outputURL.lastPathComponent,
                "--z-up",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func testSupportsLegacyExportSyntaxWithLeadingOption() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let outputURL = directory.appendingPathComponent("model.stl")
            let result = try runExecutable([
                "--z-up",
                inputURL.lastPathComponent,
                outputURL.lastPathComponent,
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func testRejectsLegacyExportSyntaxWithMatchingInputAndOutputNames() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let result = try runExecutable([
                inputURL.lastPathComponent,
                inputURL.lastPathComponent,
            ], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.firstOutputLine, "Error: Unsupported export file type 'shape'")
        }
    }

    func testSupportsLegacyExportSyntaxWithNamedOutput() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let outputURL = directory.appendingPathComponent("model.stl")
            let result = try runExecutable([
                inputURL.lastPathComponent,
                "--output",
                outputURL.lastPathComponent,
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func testSupportsLegacyExportSyntaxWithShortNamedOutput() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let outputURL = directory.appendingPathComponent("model.stl")
            let result = try runExecutable([
                inputURL.lastPathComponent,
                "-o",
                outputURL.lastPathComponent,
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func testSupportsLegacyExportSyntaxWithInlineNamedOutput() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let outputURL = directory.appendingPathComponent("model.stl")
            let result = try runExecutable([
                inputURL.lastPathComponent,
                "--output=\(outputURL.lastPathComponent)",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func testCheckDoesNotBuildGeometry() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let result = try runExecutable(["check", inputURL.lastPathComponent], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(result.output.contains("Loading file 'model.shape' ..."))
            XCTAssertTrue(result.output.contains("Running script ..."))
            XCTAssertFalse(result.output.contains("Building geometry ..."))
        }
    }

    func testInfoBuildsGeometry() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let result = try runExecutable(["info", inputURL.lastPathComponent], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(result.output.contains("Building geometry ..."))
        }
    }

    func testCLIRejectsImageOutput() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let result = try runExecutable([
                "export",
                inputURL.lastPathComponent,
                "--output",
                "model.stl",
                "--camera",
                "Hero",
            ], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(result.output.contains("Unknown option '--camera'"), result.failureMessage)
        }
    }

    func testCLIAcceptsModelOutput() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let outputURL = directory.appendingPathComponent("model.stl")
            let result = try runExecutable([
                "export",
                inputURL.lastPathComponent,
                "--output",
                outputURL.lastPathComponent,
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func testExportReportsMissingInputBeforeInvalidOutput() throws {
        let result = try runExecutable([
            "export",
            "nonexistent.shape",
            "--output",
            "out",
        ])
        XCTAssertNotEqual(result.status, 0, result.failureMessage)
        XCTAssertTrue(result.firstOutputLine.contains("nonexistent.shape"))
        XCTAssertFalse(result.firstOutputLine.contains("Unsupported export file type"))
    }

    func testRunnerReportsMissingInputBeforeUnsupportedInputType() throws {
        let result = try runExecutable(["info", "nonexistant"])
        XCTAssertNotEqual(result.status, 0, result.failureMessage)
        XCTAssertEqual(result.firstOutputLine, "Error: Unexpected argument 'nonexistant'")
    }

    func testRunnerReportsUnsupportedInputTypeAfterFileExists() throws {
        try withTemporaryFile(named: "model") { directory, inputURL in
            let result = try runExecutable(["info", inputURL.lastPathComponent], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.firstOutputLine, "Error: Unsupported file type ''")
        }
    }

    func testRootExistingExtensionlessFileReportsUnsupportedFileType() throws {
        try withTemporaryFile(named: "foo") { directory, _ in
            let result = try runExecutable(["foo"], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.firstOutputLine, "Error: Unsupported file type ''")
        }
    }

    func testRootMissingExtensionlessFileReportsUnexpectedArgument() throws {
        try withTemporaryDirectory { directory in
            let result = try runExecutable(["foo"], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.firstOutputLine, "Error: Unexpected argument 'foo'")
        }
    }

    func testRootExistingExtensionlessFileWithOutputReportsUnsupportedFileType() throws {
        try withTemporaryFile(named: "foo") { directory, _ in
            let result = try runExecutable(["foo", "--output", "foo.png"], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.firstOutputLine, "Error: Unsupported file type ''")
        }
    }

    func testRootMissingExtensionlessFileWithOutputReportsUnexpectedArgument() throws {
        try withTemporaryDirectory { directory in
            let result = try runExecutable(["foo", "--output", "foo.png"], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.firstOutputLine, "Error: Unexpected argument 'foo'")
        }
    }

    func testRootExistingUnsupportedFileReportsExtension() throws {
        try withTemporaryFile(named: "foo.bar") { directory, _ in
            let result = try runExecutable(["foo.bar"], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.firstOutputLine, "Error: Unsupported file type 'bar'")
        }
    }

    func testRootMissingUnsupportedFileReportsMissingFile() throws {
        try withTemporaryDirectory { directory in
            let result = try runExecutable(["foo.bar"], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.firstOutputLine, "Error: File 'foo.bar' not found")
        }
    }
}

private extension CLITests {
    struct ExecutableResult {
        var executableURL: URL
        var status: Int32
        var output: String

        var failureMessage: String {
            """
            Executable: \(executableURL.path)
            Status: \(status)
            Output:
            \(output)
            """
        }

        var firstOutputLine: String {
            output
                .split(separator: "\n", omittingEmptySubsequences: false)
                .first
                .map(String.init) ?? ""
        }
    }

    func withTemporaryShapeFile(_ body: (URL, URL) throws -> Void) throws {
        try withTemporaryFile(named: "model.shape", body)
    }

    func withTemporaryFile(named name: String, _ body: (URL, URL) throws -> Void) throws {
        try withTemporaryDirectory { directory in
            let inputURL = directory.appendingPathComponent(name)
            try "cube".write(to: inputURL, atomically: true, encoding: .utf8)
            try body(directory, inputURL)
        }
    }

    func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    func runExecutable(_ arguments: [String], in directory: URL? = nil) throws -> ExecutableResult {
        let executableURL = try shapeScriptExecutableURL
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let output = String(
            decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        return ExecutableResult(
            executableURL: executableURL,
            status: process.terminationStatus,
            output: output
        )
    }

    var shapeScriptExecutableURL: URL {
        get throws {
            let bundleURL = Bundle(for: type(of: self)).bundleURL
            var buildDirectories = [URL]()
            var url = bundleURL
            for _ in 0 ..< 5 {
                url.deleteLastPathComponent()
                buildDirectories.append(url)
            }

            let productNames = ["CLI", "shapescript"]
            let candidates = buildDirectories.flatMap { directory in
                productNames.map { directory.appendingPathComponent($0) }
            } + [
                URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(".build")
                    .appendingPathComponent("debug")
                    .appendingPathComponent("shapescript"),
            ]
            return try XCTUnwrap(candidates.first { url in
                FileManager.default.isExecutableFile(atPath: url.path)
            })
        }
    }
}

#endif
