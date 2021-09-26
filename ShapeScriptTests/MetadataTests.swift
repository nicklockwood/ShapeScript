//
//  MetadataTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 10/07/2021.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import XCTest

private let projectDirectory = URL(fileURLWithPath: #file)
    .deletingLastPathComponent().deletingLastPathComponent()

private let changelogURL = projectDirectory
    .appendingPathComponent("CHANGELOG.md")

private let podspecURL = projectDirectory
    .appendingPathComponent("ShapeScript.podspec.json")

private let projectURL = projectDirectory
    .appendingPathComponent("ShapeScript.xcodeproj")
    .appendingPathComponent("project.pbxproj")

private let helpDirectory = projectDirectory
    .appendingPathComponent("Help")

private let helpIndexURL = helpDirectory
    .appendingPathComponent("index.md")

private let imagesDirectory = helpDirectory
    .appendingPathComponent("images")

private let examplesDirectory = projectDirectory
    .appendingPathComponent("Examples")

private let exampleURLs = try! FileManager.default
    .contentsOfDirectory(atPath: examplesDirectory.path)
    .map { URL(fileURLWithPath: $0, relativeTo: examplesDirectory) }
    .filter { $0.pathExtension == "shape" }

private let shapeScriptVersion: String = {
    let string = try! String(contentsOf: projectURL)
    let start = string.range(of: "MARKETING_VERSION = ")!.upperBound
    let end = string.range(of: ";", range: start ..< string.endIndex)!.lowerBound
    return String(string[start ..< end])
}()

private func findHeadings(in string: String) -> [String] {
    string.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.hasPrefix("## ") }
        .map { String($0.dropFirst(3)) }
}

class MetadataTests: XCTestCase {
    // MARK: Releases

    func testLatestVersionInChangelog() {
        let changelog = try! String(contentsOf: changelogURL, encoding: .utf8)
        XCTAssertTrue(changelog.contains("[\(shapeScriptVersion)]"), "CHANGELOG.md does not mention latest release")
        XCTAssertTrue(
            changelog.contains("(https://github.com/nicklockwood/ShapeScript/releases/tag/\(shapeScriptVersion))"),
            "CHANGELOG.md does not include correct link for latest release"
        )
    }

    func testLatestVersionInPodspec() {
        let podspec = try! String(contentsOf: podspecURL, encoding: .utf8)
        XCTAssertTrue(
            podspec.contains("\"version\": \"\(shapeScriptVersion)\""),
            "Podspec version does not match latest release"
        )
        XCTAssertTrue(
            podspec.contains("\"tag\": \"\(shapeScriptVersion)\""),
            "Podspec tag does not match latest release"
        )
    }

    // MARK: Help

    func testUpdateIndex() throws {
        let geometryLinks = [
            ("Primitives", "primitives.md"),
            ("Options", "options.md"),
            ("Materials", "materials.md"),
            ("Transforms", "transforms.md"),
            ("Bounds", "bounds.md"),
            ("Groups", "groups.md"),
            ("Paths", "paths.md"),
            ("Text", "text.md"),
            ("Builders", "builders.md"),
            ("Constructive Solid Geometry", "csg.md"),
        ]

        let syntaxLinks = [
            ("Comments", "comments.md"),
            ("Literals", "literals.md"),
            ("Symbols", "symbols.md"),
            ("Expressions", "expressions.md"),
            ("Functions", "functions.md"),
            ("Commands", "commands.md"),
            ("Control Flow", "control-flow.md"),
            ("Blocks", "blocks.md"),
            ("Scope", "scope.md"),
            ("Debugging", "debugging.md"),
            ("Import", "import.md"),
        ]

        func findSections(in string: String) -> [(String, String)] {
            findHeadings(in: string).compactMap { heading in
                let fragment = heading.lowercased()
                    .replacingOccurrences(of: "'", with: "")
                    .replacingOccurrences(of: " ", with: "-")
                XCTAssert(!fragment.contains(where: {
                    !"abcdefghijklmnopqrstuvwxyz0123456789_-".contains($0)
                }))
                return (heading, fragment)
            }
        }

        func buildLinks(_ links: [(String, String)]) throws -> String {
            try links.map { heading, path in
                let file = helpDirectory.appendingPathComponent(path)
                let text = try String(contentsOf: file)
                let links = findSections(in: text).map { subheading, fragment in
                    "\n        - [\(subheading)](\(path)#\(fragment))"
                }.joined()
                return "    - [\(heading)](\(path))" + links
            }.joined(separator: "\n")
        }

        let index = try """
        ShapeScript Help
        ---

        - [Overview](overview.md)
        - [Getting Started](getting-started.md)
        - [Camera Control](camera-control.md)
        - Geometry
        \(buildLinks(geometryLinks))
        - Syntax
        \(buildLinks(syntaxLinks))
        - [Export](export.md)
        - [Examples](examples.md)
        - [Glossary](glossary.md)

        """

        let existing = try String(contentsOf: helpIndexURL)
        XCTAssertEqual(existing, index)

        try index.write(to: helpIndexURL, atomically: true, encoding: .utf8)
    }

    func testHelpLinks() throws {
        let enumerator =
            try XCTUnwrap(FileManager.default.enumerator(atPath: helpDirectory.path))

        let urlRegex = try! NSRegularExpression(pattern: "\\]\\(([^\\)]+)\\)", options: [])

        var referencedImages = Set<String>()
        for case let file as String in enumerator where file.hasSuffix(".md") {
            let fileURL = helpDirectory.appendingPathComponent(file)
            let text = try XCTUnwrap(String(contentsOf: fileURL)) as NSString
            var range = NSRange(location: 0, length: text.length)
            for match in urlRegex.matches(in: text as String, options: [], range: range) {
                range = NSRange(location: match.range.upperBound, length: range.length - match.range.upperBound)
                var url = text.substring(with: match.range(at: 1))
                var fragment = ""
                let parts = url.components(separatedBy: "#")
                guard !url.hasPrefix("http") else {
                    continue
                }
                let isImage = url.hasSuffix(".png")
                if parts.count == 2 {
                    url = parts[0]
                    fragment = parts[1]
                    if url.isEmpty {
                        url = fileURL.path
                    }
                }
                let absoluteURL = URL(fileURLWithPath: url, relativeTo: helpDirectory)
                guard FileManager.default.fileExists(atPath: absoluteURL.path) else {
                    XCTFail("\(url) referenced in \(file) does not exist")
                    continue
                }
                if isImage {
                    referencedImages.insert(absoluteURL.lastPathComponent)
                    continue
                }
                guard !fragment.isEmpty else {
                    continue
                }
                let text = try XCTUnwrap(String(contentsOf: absoluteURL))
                let title = "## \(fragment.replacingOccurrences(of: "-", with: "[ -]"))"
                if text.range(of: title, options: [.regularExpression, .caseInsensitive]) == nil {
                    if !url.hasSuffix(file) {
                        XCTFail("anchor \(url)#\(fragment) referenced in \(file) does not exist")
                    } else {
                        XCTFail("anchor #\(fragment) referenced in \(file) does not exist")
                    }
                }
            }
        }

        let imagesEnumerator =
            try XCTUnwrap(FileManager.default.enumerator(atPath: imagesDirectory.path))

        for case let file as String in imagesEnumerator where file.hasSuffix(".png") {
            if !referencedImages.contains(file) {
                XCTFail("Image \(file) not referenced in help")
            }
        }
    }

    // MARK: Examples

    func testExamplesAllListedInHelp() throws {
        let examplesHelpURL = helpDirectory.appendingPathComponent("examples.md")
        let examplesHelp = try String(contentsOf: examplesHelpURL)
        let exampleHeadings = findHeadings(in: examplesHelp)
        let exampleFileNames = exampleURLs.map { $0.deletingPathExtension().lastPathComponent }
        for name in exampleFileNames {
            XCTAssert(exampleHeadings.contains(name),
                      "Example '\(name)' not listed in examples.md")
        }
        for name in exampleHeadings {
            XCTAssert(exampleFileNames.contains(name),
                      "Example '\(name)' listed in examples.md does not exist")
        }
    }

    func testExamplesAllRunWithoutError() {
        class TestDelegate: EvaluationDelegate {
            func importGeometry(for _: URL) throws -> Geometry? { nil }
            func debugLog(_: [AnyHashable]) {}

            func resolveURL(for name: String) -> URL {
                examplesDirectory.appendingPathComponent(name)
            }
        }

        for file in exampleURLs {
            do {
                let input = try String(contentsOf: file, encoding: .utf8)
                let program = try parse(input)
                let delegate = TestDelegate()
                _ = try evaluate(program, delegate: delegate)
            } catch let error as LexerError {
                XCTFail("Error: \(error.message) in '\(file.lastPathComponent)'")
            } catch let error as ParserError {
                XCTFail("Error: \(error.message) in '\(file.lastPathComponent)'")
            } catch let error as RuntimeError {
                XCTFail("Error: \(error.message) in '\(file.lastPathComponent)'")
            } catch {
                XCTFail("Error: \(error) in '\(file.lastPathComponent)'")
            }
        }
    }
}
