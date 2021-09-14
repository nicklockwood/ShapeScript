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

private let shapeScriptVersion: String = {
    let string = try! String(contentsOf: projectURL)
    let start = string.range(of: "MARKETING_VERSION = ")!.upperBound
    let end = string.range(of: ";", range: start ..< string.endIndex)!.lowerBound
    return String(string[start ..< end])
}()

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
            ("Loops", "loops.md"),
            ("Blocks", "blocks.md"),
            ("Scope", "scope.md"),
            ("Import", "import.md"),
        ]

        func findSections(in string: String) -> [(String, String)] {
            let headings = string.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("## ") }

            return headings.compactMap {
                let heading = String($0.dropFirst(3))
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
                guard !fragment.isEmpty else {
                    continue
                }
                let text = try XCTUnwrap(String(contentsOf: absoluteURL))
                let title = "## \(fragment.replacingOccurrences(of: "-", with: " "))"
                if text.range(of: title, options: [.regularExpression, .caseInsensitive]) == nil {
                    if !url.hasSuffix(file) {
                        XCTFail("anchor \(url)#\(fragment) referenced in \(file) does not exist")
                    } else {
                        XCTFail("anchor #\(fragment) referenced in \(file) does not exist")
                    }
                }
            }
        }
    }
}
