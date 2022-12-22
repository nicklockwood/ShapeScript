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
    .appendingPathComponent("docs")

private let helpSourceDirectory = helpDirectory
    .appendingPathComponent("src")

private let helpIndexURL = helpSourceDirectory
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

private let geometryLinks = [
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
    ("Lights", "lights.md"),
    ("Cameras", "cameras.md"),
]

private let syntaxLinks = [
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

private extension URL {
    func hasSuffix(_ suffix: String) -> Bool {
        deletingPathExtension().lastPathComponent.hasSuffix("-" + suffix)
    }

    func withSuffix(_ suffix: String) -> URL {
        let name = deletingPathExtension().lastPathComponent
        return deletingPathExtension()
            .deletingLastPathComponent()
            .appendingPathComponent(name + "-" + suffix)
            .appendingPathExtension(pathExtension)
    }

    func deletingSuffix(_ suffix: String) -> URL {
        guard hasSuffix(suffix) else {
            return self
        }
        let name = deletingPathExtension().lastPathComponent
        return deletingPathExtension()
            .deletingLastPathComponent()
            .appendingPathComponent(String(name.dropLast(suffix.count + 1)))
            .appendingPathExtension(pathExtension)
    }
}

private let urlRegex = try! NSRegularExpression(pattern: "\\]\\(([^\\)]*)\\)", options: [])

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

    func testVersionConstantUpdated() {
        XCTAssertEqual(ShapeScript.version, shapeScriptVersion)
    }

    // MARK: Help

    func testUpdateIndex() throws {
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
                let file = helpSourceDirectory.appendingPathComponent(path)
                let text = try String(contentsOf: file)
                let links = findSections(in: text).map { subheading, fragment in
                    "\n        - [\(subheading)](\(path)#\(fragment))"
                }.joined()
                return "    - [\(heading)](\(path))" + links
            }.joined(separator: "\n")
        }

        let indexMac = try """
        ShapeScript Help
        ---

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

        let indexIOS = try """
        ShapeScript Help
        ---

        - [Getting Started](getting-started.md)
        - [Camera Control](camera-control.md)
        - Geometry
        \(buildLinks(geometryLinks))
        - Syntax
        \(buildLinks(syntaxLinks))
        - [Examples](examples.md)
        - [Glossary](glossary.md)

        """

        for (index, url) in [
            (indexMac, helpIndexURL),
            (indexIOS, helpIndexURL.withSuffix("ios")),
        ] {
            let existing = try String(contentsOf: url)
            XCTAssertEqual(existing, index)
            try index.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func testHelpFooterLinks() throws {
        let indexLinks = [
            ("Getting Started", "getting-started.md"),
            ("Camera Control", "camera-control.md"),
        ] + geometryLinks + syntaxLinks + [
            ("Export", "export.md"),
            ("Examples", "examples.md"),
            ("Glossary", "glossary.md"),
        ]

        let urlRegex = try! NSRegularExpression(pattern: "Next: \\[([^\\]]+)\\]\\(([^\\)]*)\\)", options: [])

        for (i, (_, path)) in indexLinks.dropLast().enumerated() {
            let fileURL = helpSourceDirectory.appendingPathComponent(path)
            let text = try XCTUnwrap(String(contentsOf: fileURL))
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            guard let match = urlRegex.firstMatch(in: text, options: [], range: range) else {
                XCTFail("No Next: link found in \(path)")
                continue
            }
            let next: (name: String, path: String) = indexLinks[i + 1]
            let name = nsText.substring(with: match.range(at: 1))
            XCTAssertEqual(name, next.name, "Next link name in \(path) should be \(next.name)")
            let path = nsText.substring(with: match.range(at: 2))
            XCTAssertEqual(path, next.path, "Next link url in \(path) should be \(next.path)")
        }
    }

    func testHelpLinks() throws {
        let fm = FileManager.default
        let enumerator = try XCTUnwrap(fm.enumerator(atPath: helpSourceDirectory.path))

        var referencedImages = Set<String>()
        for case let file as String in enumerator where file.hasSuffix(".md") {
            let fileURL = helpSourceDirectory.appendingPathComponent(file)
            let text = try XCTUnwrap(String(contentsOf: fileURL))
            let nsText = text as NSString
            var range = NSRange(location: 0, length: nsText.length)
            for match in urlRegex.matches(in: text, options: [], range: range) {
                range = NSRange(location: match.range.upperBound, length: range.length - match.range.upperBound)
                var url = nsText.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespaces)
                XCTAssertFalse(url.isEmpty, "Empty url reference in \(file)")
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
                let absoluteURL = URL(fileURLWithPath: url, relativeTo: helpSourceDirectory)
                guard fm.fileExists(atPath: absoluteURL.path) else {
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

        let imagesEnumerator = try XCTUnwrap(fm.enumerator(atPath: imagesDirectory.path))
        for case let file as String in imagesEnumerator where file.hasSuffix(".png") {
            let unsuffixedFile = file.replacingOccurrences(of: "-ios.", with: ".")
            if !referencedImages.contains(file),
               !referencedImages.contains(unsuffixedFile)
            {
                XCTFail("Image \(file) not referenced in help")
            }
        }
    }

    func testHelpMergeConflicts() throws {
        let fm = FileManager.default
        let enumerator = try XCTUnwrap(fm.enumerator(atPath: helpSourceDirectory.path))

        for case let file as String in enumerator where file.hasSuffix(".md") {
            let fileURL = helpSourceDirectory.appendingPathComponent(file)
            let text = try XCTUnwrap(String(contentsOf: fileURL))
            if text.range(of: "<<<<") ?? text.range(of: ">>>>") ??
                text.range(of: "====") != nil
            {
                XCTFail("Merge conflict markers in \(file)")
            }
        }
    }

    func testExportMacHelp() throws {
        let fm = FileManager.default

        let outputDirectory = helpDirectory.appendingPathComponent("mac")
        try? fm.removeItem(at: outputDirectory)
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let enumerator = try XCTUnwrap(fm.enumerator(atPath: helpSourceDirectory.path))
        for case let file as String in enumerator {
            let fileURL = helpSourceDirectory.appendingPathComponent(file)
            guard fileURL.pathExtension == "md", !fileURL.hasSuffix("ios") else {
                enumerator.skipDescendants()
                continue
            }
            let outputURL = outputDirectory.appendingPathComponent(file)
            try fm.copyItem(at: fileURL, to: outputURL)
        }
    }

    func testExportIOSHelp() throws {
        let fm = FileManager.default

        let outputDirectory = helpDirectory.appendingPathComponent("ios")
        try? fm.removeItem(at: outputDirectory)
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let enumerator = try XCTUnwrap(fm.enumerator(atPath: helpSourceDirectory.path))
        for case var file as String in enumerator {
            let fileURL = helpSourceDirectory.appendingPathComponent(file)
            guard fileURL.pathExtension == "md" else {
                enumerator.skipDescendants()
                continue
            }
            if fileURL.hasSuffix("ios") {
                file = String(fileURL
                    .deletingPathExtension()
                    .lastPathComponent
                    .dropLast(4)) + ".md"
            } else if fm.fileExists(atPath: fileURL.withSuffix("ios").path) {
                continue
            }
            let text = try XCTUnwrap(String(contentsOf: fileURL))
            let nsText = NSMutableString(string: text)
            var range = NSRange(location: 0, length: nsText.length)
            var urlRanges = [NSRange]()
            for match in urlRegex.matches(in: text, options: [], range: range) {
                range = NSRange(location: match.range.upperBound, length: range.length - match.range.upperBound)
                urlRanges.append(match.range(at: 1))
            }
            for range in urlRanges.reversed() {
                guard var url = URL(string: nsText.substring(with: range)),
                      url.host == nil
                else {
                    continue
                }
                if !url.hasSuffix("ios") {
                    let isMac = url.hasSuffix("mac")
                    if isMac {
                        url = url.deletingSuffix("mac")
                    }
                    let iosURL = url.withSuffix("ios")
                    let absoluteURL = URL(fileURLWithPath: iosURL.path, relativeTo: fileURL)
                    if url.pathExtension == "png", fm.fileExists(atPath: absoluteURL.path) {
                        url = iosURL
                    } else if isMac {
                        let macFile = url.withSuffix("mac").lastPathComponent
                        XCTFail("File '\(macFile)' has no iOS equivalent")
                    }
                    nsText.replaceCharacters(in: range, with: url.absoluteString)
                }
                // Special case
                if url.lastPathComponent == "export.md", nsText
                    .substring(to: range.location).hasSuffix("Next: [Export](")
                {
                    nsText.replaceCharacters(in: range, with: "examples.md")
                }
            }
            let outputURL = outputDirectory.appendingPathComponent(file)
            try (nsText as String).write(to: outputURL, atomically: true, encoding: .utf8)

            if file != "export.md" {
                for key in ["View >", "macOS"] where nsText.contains(key) {
                    XCTFail("Reference to '\(key)' in '\(file)'")
                }
            }
        }
    }

    func testExportVersionedHelp() throws {
        let fm = FileManager.default
        let outputDirectory = helpDirectory.appendingPathComponent(shapeScriptVersion)
        guard fm.fileExists(atPath: outputDirectory.path) else {
            XCTFail("Help directory for \(shapeScriptVersion) not found")
            return
        }
        let attrs = try fm.attributesOfItem(atPath: outputDirectory.path)
        if attrs[.type] as? FileAttributeType == .typeSymbolicLink {
            return
        }
        try? fm.removeItem(at: outputDirectory)
        for subdir in ["mac", "ios"] {
            let helpDir = helpDirectory.appendingPathComponent(subdir)
            let versionedDir = outputDirectory.appendingPathComponent(subdir)
            try fm.createDirectory(at: versionedDir, withIntermediateDirectories: true)
            let enumerator = try XCTUnwrap(fm.enumerator(atPath: helpDir.path))
            for case let file as String in enumerator where file.hasSuffix(".md") {
                let fileURL = helpDir.appendingPathComponent(file)
                let text = try String(contentsOf: fileURL)
                let nsText = NSMutableString(string: text)
                var range = NSRange(location: 0, length: nsText.length)
                var urlRanges = [NSRange]()
                for match in urlRegex.matches(in: text, options: [], range: range) {
                    range = NSRange(location: match.range.upperBound, length: range.length - match.range.upperBound)
                    urlRanges.append(match.range(at: 1))
                }
                for range in urlRanges.reversed() {
                    guard let url = URL(string: nsText.substring(with: range)),
                          url.host == nil, url.pathExtension == "png"
                    else {
                        continue
                    }
                    nsText.replaceCharacters(in: range, with: "../\(url.absoluteString)")
                }
                let outputURL = versionedDir.appendingPathComponent(file)
                try (nsText as String).write(to: outputURL, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: Examples

    func testExamplesAllListedInHelp() throws {
        let examplesHelpURL = helpSourceDirectory.appendingPathComponent("examples.md")
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
