//
//  CLITests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 17/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

#if os(macOS) || os(Linux)

import Euclid
import XCTest

final class CLITests: XCTestCase {
    func testExportUpAxisUsesInputFileType() throws {
        for fileExtension in ["shape", "SHAPE", "csg", "CSG"] {
            let isCSG = fileExtension.lowercased() == "csg"
            try withTemporaryFile(named: "model.\(fileExtension)") { directory, inputURL in
                let source = isCSG ? "cube([2,4,10],true);" : "cube { size 2 4 10 }"
                try source.write(to: inputURL, atomically: true, encoding: .utf8)
                for outputExtension in ["stl", "stla"] {
                    for zUp in [false, true] {
                        let outputURL = directory.appendingPathComponent("output.\(outputExtension)")
                        var arguments = ["export", inputURL.lastPathComponent, "--output", outputURL.lastPathComponent]
                        if zUp {
                            arguments.append("--z-up")
                        }
                        let result = try runExecutable(arguments, in: directory)
                        XCTAssertEqual(result.status, 0, result.failureMessage)
                        let mesh = try XCTUnwrap(Mesh(stlData: Data(contentsOf: outputURL)))
                        let expected = !isCSG && zUp ? Vector(2, 10, 4) : Vector(2, 4, 10)
                        XCTAssertEqual(mesh.bounds.size, expected, arguments.joined(separator: " "))
                    }
                }
            }
        }
    }

    func testCSGWarningsArePrintedWithoutFailing() throws {
        try withTemporaryFile(named: "model.csg") { directory, inputURL in
            try "color(\"red\") cube(1);".write(to: inputURL, atomically: true, encoding: .utf8)
            let result = try runExecutable(["check", inputURL.lastPathComponent], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(
                result.output.contains("Warning: model.csg: Named CSG colors are unsupported"),
                result.failureMessage
            )
        }
    }

    func testCSGCheckInfoAndSTLExport() throws {
        for name in ["model.csg", "model.CSG"] {
            try withTemporaryFile(named: name) { directory, inputURL in
                try "cube([2,3,4]);".write(to: inputURL, atomically: true, encoding: .utf8)
                for command in ["check", "info"] {
                    let result = try runExecutable([command, name], in: directory)
                    XCTAssertEqual(result.status, 0, result.failureMessage)
                }
                let result = try runExecutable([name, "--output", "model.stl"], in: directory)
                XCTAssertEqual(result.status, 0, result.failureMessage)
                XCTAssertTrue(FileManager.default
                    .fileExists(atPath: directory.appendingPathComponent("model.stl").path))
            }
        }
    }

    func testCSGImageExport() throws {
        try withTemporaryFile(named: "model.csg") { directory, inputURL in
            try "color([1,0,0]) cube(1,true);".write(to: inputURL, atomically: true, encoding: .utf8)
            let result = try runExecutable([
                "export", inputURL.lastPathComponent, "--output", "model.bmp", "--camera", "Front",
                "--width", "8", "--height", "6",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            let data = try Data(contentsOf: directory.appendingPathComponent("model.bmp"))
            XCTAssertEqual(data[18], 8)
            XCTAssertEqual(data[22], 6)
            XCTAssertTrue(data.dropFirst(54).contains { $0 != 255 })
        }
    }

    func testCSGErrorsAreSurfaced() throws {
        try withTemporaryFile(named: "model.csg") { directory, inputURL in
            try "\ncube([1,2]);".write(to: inputURL, atomically: true, encoding: .utf8)
            let result = try runExecutable(["check", inputURL.lastPathComponent], in: directory)
            XCTAssertNotEqual(result.status, 0)
            XCTAssertTrue(result.output.contains("Expected a CSG vector with 3 components"), result.failureMessage)
            XCTAssertTrue(result.output.contains("line 2"), result.failureMessage)
        }
    }

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
        XCTAssertTrue(result.output.contains("USAGE: shapescript check [--preview] [--no-cache] <input-path>"))
        XCTAssertTrue(result.output.contains("Input .shape or .csg file."))
        XCTAssertFalse(result.output.contains("--output"))
        XCTAssertTrue(result.output.contains("--preview"))
        XCTAssertTrue(result.output.contains("--no-cache"))
        XCTAssertTrue(result.output.contains("script-options"))
    }

    func testInfoHelpDescribesInfoCommand() throws {
        let result = try runExecutable(["info", "--help"])
        XCTAssertEqual(result.status, 0, result.failureMessage)
        XCTAssertTrue(result.output.contains("USAGE: shapescript info [--preview] [--no-cache] <input-path>"))
        XCTAssertTrue(result.output.contains("Input .shape or .csg file."))
        XCTAssertFalse(result.output.contains("--output"))
        XCTAssertTrue(result.output.contains("--preview"))
        XCTAssertTrue(result.output.contains("--no-cache"))
        XCTAssertTrue(result.output.contains("script-options"))
    }

    func testExportHelpDescribesExportCommand() throws {
        let result = try runExecutable(["help", "export"])
        XCTAssertEqual(result.status, 0, result.failureMessage)
        XCTAssertTrue(result.output.contains("USAGE: shapescript export <input-path>"))
        XCTAssertTrue(result.output.contains("--output"))
        XCTAssertTrue(result.output.contains("--camera"))
        XCTAssertTrue(result.output.contains("--preview"))
        XCTAssertTrue(result.output.contains("--no-cache"))
        XCTAssertTrue(result.output.contains("script-options"))
        XCTAssertTrue(result.output.contains("--z-up"))
    }

    func testCheckAcceptsTopLevelScriptOption() throws {
        try withTemporaryShapeFile("""
        option radius 1
        print radius
        cube
        """) { directory, inputURL in
            let result = try runExecutable([
                "check",
                inputURL.lastPathComponent,
                "--",
                "--radius",
                "2",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.standardOutput, "2\n")
        }
    }

    func testCheckAcceptsPreviewFlag() throws {
        try withTemporaryShapeFile("""
        print preview
        cube
        """) { directory, inputURL in
            let result = try runExecutable([
                "check",
                "--preview",
                inputURL.lastPathComponent,
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.standardOutput, "true\n")
        }
    }

    func testInfoAcceptsPreviewFlag() throws {
        try withTemporaryShapeFile("""
        print preview
        cube
        """) { directory, inputURL in
            let result = try runExecutable([
                "info",
                "--preview",
                inputURL.lastPathComponent,
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(result.standardOutput.hasPrefix("true\n"), result.failureMessage)
        }
    }

    func testExportAcceptsPreviewFlag() throws {
        try withTemporaryShapeFile("""
        print preview
        cube
        """) { directory, inputURL in
            let outputURL = directory.appendingPathComponent("model.stl")
            let result = try runExecutable([
                "export",
                "--preview",
                inputURL.lastPathComponent,
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.standardOutput, "true\n")
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func testLegacyRootCommandAcceptsPreviewFlag() throws {
        try withTemporaryShapeFile("""
        print preview
        cube
        """) { directory, inputURL in
            let result = try runExecutable([
                "--preview",
                inputURL.lastPathComponent,
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(result.standardOutput.hasPrefix("true\n"), result.failureMessage)
        }
    }

    func testScriptOptionValueFallsBackToString() throws {
        try withTemporaryShapeFile("""
        option label ""
        print label
        cube
        """) { directory, inputURL in
            let result = try runExecutable([
                "check",
                inputURL.lastPathComponent,
                "--",
                "--label",
                "hello",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.standardOutput, "hello\n")
        }
    }

    func testScriptOptionAcceptsShapeScriptExpression() throws {
        try withTemporaryShapeFile("""
        option radius 1
        print radius
        cube
        """) { directory, inputURL in
            let result = try runExecutable([
                "check",
                inputURL.lastPathComponent,
                "--",
                "--radius",
                "1 + 2",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.standardOutput, "3\n")
        }
    }

    func testScriptOptionAcceptsStringWithSpaces() throws {
        try withTemporaryShapeFile("""
        option label ""
        print label
        cube
        """) { directory, inputURL in
            let result = try runExecutable([
                "check",
                inputURL.lastPathComponent,
                "--",
                "--label",
                "hello world",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.standardOutput, "hello world\n")
        }
    }

    func testScriptOptionAcceptsTupleColor() throws {
        try withTemporaryShapeFile("""
        option swatch #fff
        print swatch
        cube { color swatch }
        """) { directory, inputURL in
            let result = try runExecutable([
                "check",
                inputURL.lastPathComponent,
                "--",
                "--swatch",
                "1 0 0",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.standardOutput, "1 0 0\n")
        }
    }

    func testScriptOptionAcceptsParenthesizedTupleColor() throws {
        try withTemporaryShapeFile("""
        option swatch #fff
        print swatch
        cube { color swatch }
        """) { directory, inputURL in
            let result = try runExecutable([
                "check",
                inputURL.lastPathComponent,
                "--",
                "--swatch",
                "(1 0 0)",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.standardOutput, "1 0 0\n")
        }
    }

    func testScriptOptionAcceptsHexColor() throws {
        try withTemporaryShapeFile("""
        option swatch #fff
        print swatch
        cube { color swatch }
        """) { directory, inputURL in
            let result = try runExecutable([
                "check",
                inputURL.lastPathComponent,
                "--",
                "--swatch",
                "#ff0000",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.standardOutput, "1 0 0\n")
        }
    }

    func testRejectsInvalidScriptOptionSyntax() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let result = try runExecutable([
                "check",
                inputURL.lastPathComponent,
                "--",
                "radius",
            ], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.firstOutputLine, "Error: Expected script option values after 'radius'")
        }
    }

    func testRejectsUnknownScriptOption() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let result = try runExecutable([
                "check",
                inputURL.lastPathComponent,
                "--",
                "--radius",
                "2",
            ], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(result.firstOutputLine.contains("Unknown option 'radius'"))
        }
    }

    func testRejectsScriptOptionTypeMismatch() throws {
        try withTemporaryShapeFile("""
        option radius 1
        cube
        """) { directory, inputURL in
            let result = try runExecutable([
                "check",
                inputURL.lastPathComponent,
                "--",
                "--radius",
                "large",
            ], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(result.firstOutputLine.contains("Type mismatch"))
        }
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

    func testSupportsLegacyExportSyntaxWithScriptOption() throws {
        try withTemporaryShapeFile("""
        option radius 1
        cube { size radius }
        """) { directory, inputURL in
            let outputURL = directory.appendingPathComponent("model.stl")
            let result = try runExecutable([
                inputURL.lastPathComponent,
                outputURL.lastPathComponent,
                "--",
                "--radius",
                "2",
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

    func testCheckWritesProgressToStandardError() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let result = try runExecutable(["check", inputURL.lastPathComponent], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.standardOutput, "")
            XCTAssertTrue(result.standardError.contains("Loading file 'model.shape' ..."))
            XCTAssertTrue(result.standardError.contains("Running script ..."))
        }
    }

    func testInfoBuildsGeometry() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let result = try runExecutable(["info", inputURL.lastPathComponent], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(result.output.contains("Building geometry ..."))
        }
    }

    func testBMPExportColorsAndRowPadding() throws {
        try withTemporaryShapeFile("background 1 0 0 0.5") { directory, inputURL in
            let result = try runExecutable([
                "export", inputURL.lastPathComponent, "--width", "3", "--height", "2",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            let data = try Data(contentsOf: directory.appendingPathComponent("model.bmp"))
            XCTAssertEqual(data.count, 78)
            XCTAssertEqual(Array(data.prefix(2)), [0x42, 0x4D])
            XCTAssertEqual(Array(data[2 ..< 6]), [78, 0, 0, 0])
            XCTAssertEqual(Array(data[10 ..< 14]), [54, 0, 0, 0])
            XCTAssertEqual(Array(data[28 ..< 34]), [24, 0, 0, 0, 0, 0])
            let row: [UInt8] = [128, 128, 255, 128, 128, 255, 128, 128, 255, 0, 0, 0]
            XCTAssertEqual(Array(data.dropFirst(54)), row + row)
        }
    }

    func testBMPExportRendersGeometry() throws {
        try withTemporaryShapeFile("background 1\ncube { color red }") { directory, inputURL in
            let result = try runExecutable([
                "export", inputURL.lastPathComponent, "--output", "model.bmp",
                "--width", "32", "--height", "32",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            let data = try Data(contentsOf: directory.appendingPathComponent("model.bmp"))
            let center = 54 + (16 * 32 + 16) * 3
            XCTAssertEqual(data[center], 0)
            XCTAssertEqual(data[center + 1], 0)
            XCTAssertGreaterThan(data[center + 2], 100)
            XCTAssertEqual(Array(data[54 ..< 57]), [255, 255, 255])
        }
    }

    func testBMPExportRendersOrthographicGeometry() throws {
        try withTemporaryShapeFile("background 1\ncamera { fov 0\nsize 4 }\ncube { color red }") { directory, inputURL in
            let result = try runExecutable([
                "export", inputURL.lastPathComponent, "--output", "model.bmp",
                "--width", "32", "--height", "32",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            let data = try Data(contentsOf: directory.appendingPathComponent("model.bmp"))
            let center = 54 + (16 * 32 + 16) * 3
            XCTAssertEqual(data[center], 0)
            XCTAssertEqual(data[center + 1], 0)
            XCTAssertGreaterThan(data[center + 2], 100)
            XCTAssertEqual(Array(data[54 ..< 57]), [255, 255, 255])
        }
    }

    func testBMPExportDimensions() throws {
        let cases: [(camera: String, options: [String], width: Int, height: Int)] = [
            ("", [], 320, 320),
            ("width 3.4\nheight 2.6", [], 3, 3),
            ("", ["--width", "80"], 80, 80),
            ("", ["--height", "60"], 60, 60),
            ("width 80\nheight 40", [], 80, 40),
            ("width 80\nheight 40", ["--width", "40"], 40, 20),
            ("width 80\nheight 40", ["--height", "60"], 120, 60),
            ("width 40\nheight 80", ["--width", "60"], 60, 120),
            ("width 40\nheight 80", ["--height", "40"], 20, 40),
            ("width 80\nheight 40", ["--width", "60", "--height", "50"], 60, 50),
            ("width 80", ["--height", "40"], 40, 40),
            ("height 160", ["--width", "80"], 80, 40),
            ("width 80\nheight 40", ["--width", "3"], 3, 2),
            ("width 80\nheight 40", ["--width", "1"], 1, 1),
        ]
        for test in cases {
            try withTemporaryShapeFile("camera {\n\(test.camera)\n}\ncube") { directory, inputURL in
                let result = try runExecutable([
                    "export", inputURL.lastPathComponent, "--output", "model.bmp",
                ] + test.options, in: directory)
                XCTAssertEqual(result.status, 0, result.failureMessage)
                let data = try Data(contentsOf: directory.appendingPathComponent("model.bmp"))
                XCTAssertEqual(Array(data.prefix(2)), [0x42, 0x4D])
                guard data.count >= 54 else {
                    return XCTFail("Missing BMP header")
                }
                let width = data[18 ..< 22].reversed().reduce(0) { $0 * 256 + Int($1) }
                let height = data[22 ..< 26].reversed().reduce(0) { $0 * 256 + Int($1) }
                XCTAssertEqual(data.count, 54 + ((test.width * 3 + 3) & ~3) * test.height)
                XCTAssertEqual(width, test.width, "\(test)")
                XCTAssertEqual(height, test.height, "\(test)")
            }
        }
    }

    func testExportSubcommandDefaultsOutputToInputWithSTLExtension() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let outputURL = directory.appendingPathComponent("model.stl")
            let result = try runExecutable(["export", inputURL.lastPathComponent], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func testExportDefaultsToBMPWithImageDimensions() throws {
        for options in [["--width", "16"], ["--height", "12"], ["--width", "16", "--height", "12"]] {
            try withTemporaryShapeFile { directory, inputURL in
                let result = try runExecutable(["export", inputURL.lastPathComponent] + options, in: directory)
                XCTAssertEqual(result.status, 0, result.failureMessage)
                let data = try Data(contentsOf: directory.appendingPathComponent("model.bmp"))
                XCTAssertEqual(Array(data.prefix(2)), [0x42, 0x4D])
                XCTAssertFalse(FileManager.default
                    .fileExists(atPath: directory.appendingPathComponent("model.stl").path))
            }
        }
    }

    func testExportRespectsExplicitOutputWithImageDimensions() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let result = try runExecutable([
                "export", inputURL.lastPathComponent, "--width", "16", "--output", "model.stla",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            let output = try String(contentsOf: directory.appendingPathComponent("model.stla"))
            XCTAssertTrue(output.hasPrefix("solid "))
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("model.bmp").path))
        }
    }

    func testDefaultExportURLUsesInputPathWithSTLExtension() throws {
        try withTemporaryDirectory { directory in
            let inputURL = directory
                .appendingPathComponent("nested", isDirectory: true)
                .appendingPathComponent("model.shape")
            try FileManager.default.createDirectory(
                at: inputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "cube".write(to: inputURL, atomically: true, encoding: .utf8)

            let result = try runExecutable(["export", "nested/model.shape"], in: directory)
            let outputURL = directory
                .appendingPathComponent("nested", isDirectory: true)
                .appendingPathComponent("model.stl")
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func testCLIRejectsCameraForModelOutput() throws {
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
            XCTAssertTrue(
                result.output.contains("Image export options cannot be used with .stl output"),
                result.failureMessage
            )
        }
    }

    func testCameraArgumentDefaultsToBMPAndSupportsShorthand() throws {
        try withTemporaryShapeFile { directory, inputURL in
            let result = try runExecutable([inputURL.lastPathComponent, "--camera", "Front"], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("model.bmp").path))
        }
    }

    func testBMPExportSelectsNamedCamera() throws {
        let source = """
        camera {
            name "First"
            width 12
            height 8
            background red
        }
        camera {
            name "Héro"
            width 6
            height 4
            background blue
        }
        cube
        """
        try withTemporaryShapeFile(source) { directory, inputURL in
            let result = try runExecutable([
                "export", inputURL.lastPathComponent, "--camera", "hero", "--output", "model.bmp",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            let data = try Data(contentsOf: directory.appendingPathComponent("model.bmp"))
            XCTAssertEqual(data[18], 6)
            XCTAssertEqual(data[22], 4)
            XCTAssertEqual(Array(data[54 ..< 57]), [255, 0, 0])
        }
    }

    func testBMPExportSelectsUnnamedCamera() throws {
        try withTemporaryShapeFile("camera { width 8\nheight 6 }\ncamera { width 4\nheight 3 }\ncube") { directory, inputURL in
            let result = try runExecutable([
                "export", inputURL.lastPathComponent, "--camera", "Custom 2", "--output", "model.bmp",
            ], in: directory)
            XCTAssertEqual(result.status, 0, result.failureMessage)
            let data = try Data(contentsOf: directory.appendingPathComponent("model.bmp"))
            XCTAssertEqual(data[18], 4)
            XCTAssertEqual(data[22], 3)
        }
    }

    func testBMPExportSupportsPresetCameras() throws {
        try withTemporaryShapeFile("cube { size 1 2 3\ncolor red }\nbackground white") { directory, inputURL in
            for camera in ["Front", "Back", "Left", "Right", "Top", "Bottom"] {
                let result = try runExecutable([
                    "export", inputURL.lastPathComponent, "--camera", camera,
                    "--width", "16", "--height", "16", "--output", "model.bmp",
                ], in: directory)
                XCTAssertEqual(result.status, 0, result.failureMessage)
                let data = try Data(contentsOf: directory.appendingPathComponent("model.bmp"))
                XCTAssertTrue(data.dropFirst(54).contains { $0 != 255 }, camera)
            }
        }
    }

    func testCameraArgumentReportsMissingAndAmbiguousNames() throws {
        try withTemporaryShapeFile("camera { name \"Hero\" }\ncamera { name \"hero\" }\ncube") { directory, inputURL in
            for (camera, message) in [
                (
                    "Missing",
                    "Camera 'Missing' not found. Available cameras: Front, Back, Left, Right, Top, Bottom, Hero, hero."
                ),
                ("Hero", "Camera name 'Hero' is ambiguous."),
                ("", "--camera option expects a camera name"),
            ] {
                let result = try runExecutable([
                    "export", inputURL.lastPathComponent, "--camera", camera, "--output", "model.bmp",
                ], in: directory)
                XCTAssertNotEqual(result.status, 0, result.failureMessage)
                XCTAssertTrue(result.output.contains(message), result.failureMessage)
            }
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

    func testExportExistingExtensionlessFileReportsUnsupportedFileTypeBeforeMissingOutput() throws {
        try withTemporaryFile(named: "foo") { directory, _ in
            let result = try runExecutable(["export", "foo"], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.firstOutputLine, "Error: Unsupported file type ''")
        }
    }

    func testExportMissingExtensionlessFileReportsUnexpectedArgumentBeforeMissingOutput() throws {
        try withTemporaryDirectory { directory in
            let result = try runExecutable(["export", "foo"], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.firstOutputLine, "Error: Unexpected argument 'foo'")
        }
    }

    func testExportExistingUnsupportedFileReportsExtensionBeforeMissingOutput() throws {
        try withTemporaryFile(named: "foo.bar") { directory, _ in
            let result = try runExecutable(["export", "foo.bar"], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.firstOutputLine, "Error: Unsupported file type 'bar'")
        }
    }

    func testExportMissingUnsupportedFileReportsMissingFileBeforeMissingOutput() throws {
        try withTemporaryDirectory { directory in
            let result = try runExecutable(["export", "foo.bar"], in: directory)
            XCTAssertNotEqual(result.status, 0, result.failureMessage)
            XCTAssertEqual(result.firstOutputLine, "Error: File 'foo.bar' not found")
        }
    }
}

private extension CLITests {
    struct ExecutableResult {
        var executableURL: URL
        var status: Int32
        var standardOutput: String
        var standardError: String

        var output: String {
            standardError + standardOutput
        }

        var failureMessage: String {
            """
            Executable: \(executableURL.path)
            Status: \(status)
            Standard output:
            \(standardOutput)
            Standard error:
            \(standardError)
            """
        }

        var firstOutputLine: String {
            let lines = output
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            return lines.first { $0.hasPrefix("Error: ") } ?? lines.first ?? ""
        }
    }

    func withTemporaryShapeFile(_ body: (URL, URL) throws -> Void) throws {
        try withTemporaryFile(named: "model.shape", body)
    }

    func withTemporaryShapeFile(_ contents: String, _ body: (URL, URL) throws -> Void) throws {
        try withTemporaryDirectory { directory in
            let inputURL = directory.appendingPathComponent("model.shape")
            try contents.write(to: inputURL, atomically: true, encoding: .utf8)
            try body(directory, inputURL)
        }
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

    func runExecutable(
        _ arguments: [String],
        in directory: URL? = nil,
        disableCache: Bool = true
    ) throws -> ExecutableResult {
        let executableURL = try shapeScriptExecutableURL
        let process = Process()
        process.executableURL = executableURL
        process.arguments = disableCache ? argumentsByDisablingCache(arguments) : arguments
        process.currentDirectoryURL = directory

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let standardOutput = String(
            decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        let standardError = String(
            decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        return ExecutableResult(
            executableURL: executableURL,
            status: process.terminationStatus,
            standardOutput: standardOutput,
            standardError: standardError
        )
    }

    func argumentsByDisablingCache(_ arguments: [String]) -> [String] {
        guard !arguments.isEmpty,
              !arguments.contains("--no-cache"),
              !arguments.contains("--help"),
              !arguments.contains("-h"),
              !arguments.contains("--version"),
              arguments.first != "help",
              arguments.first != "-v" // Preserve the unknown-option test.
        else {
            return arguments
        }
        var arguments = arguments
        arguments.insert(["--no-cache"], beforeTerminator: "--")
        return arguments
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

private extension Array where Element: Equatable {
    mutating func insert(_ elements: [Element], beforeTerminator terminator: Element) {
        if let index = firstIndex(of: terminator) {
            insert(contentsOf: elements, at: index)
        } else {
            append(contentsOf: elements)
        }
    }
}

#endif
