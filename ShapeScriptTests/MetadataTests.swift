//
//  MetadataTests.swift
//  ShapeScriptTests
//
//  Created by Nick Lockwood on 10/07/2021.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
import XCTest

private let projectDirectory: URL = testsDirectory.deletingLastPathComponent()

private let changelogURL = projectDirectory
    .appendingPathComponent("CHANGELOG.md")

private let whatsNewMacURL = projectDirectory
    .appendingPathComponent("Viewer/Mac/WhatsNew.rtf")

private let whatsNewIOSURL = projectDirectory
    .appendingPathComponent("Viewer/iOS/WhatsNew.rtf")

private let podspecURL: URL = projectDirectory
    .appendingPathComponent("ShapeScript.podspec.json")

private let projectURL: URL = projectDirectory
    .appendingPathComponent("ShapeScript.xcodeproj")
    .appendingPathComponent("project.pbxproj")

private let helpDirectory: URL = projectDirectory
    .appendingPathComponent("docs")

private let helpSourceDirectory: URL = helpDirectory
    .appendingPathComponent("src")

private let helpIndexURL: URL = helpSourceDirectory
    .appendingPathComponent("index.md")

private let imagesDirectory: URL = helpDirectory
    .appendingPathComponent("images")

private let examplesDirectory: URL = projectDirectory
    .appendingPathComponent("Examples")

private let exampleURLs: [URL] = try! FileManager.default
    .contentsOfDirectory(atPath: examplesDirectory.path)
    .map { URL(fileURLWithPath: $0, relativeTo: examplesDirectory) }
    .filter { $0.pathExtension == "shape" }

private let projectVersion: String = {
    let string = try! String(contentsOf: projectURL)
    let start = string.range(of: "MARKETING_VERSION = ")!.upperBound
    let end = string.range(of: ";", range: start ..< string.endIndex)!.lowerBound
    return String(string[start ..< end])
}()

private let changelogTitles: [Substring] = {
    let changelog = try! String(contentsOf: changelogURL, encoding: .utf8)
    var range = changelog.startIndex ..< changelog.endIndex
    var matches = [Substring]()
    while let match = changelog.range(
        of: "## \\[[^]]+\\]\\([^)]+\\) \\([^)]+\\)",
        options: .regularExpression,
        range: range
    ) {
        matches.append(changelog[match])
        range = match.upperBound ..< changelog.endIndex
    }
    return matches
}()

private func findHeadings(in string: String) -> [String] {
    string.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.hasPrefix("## ") }
        .map { String($0.dropFirst(3)) }
}

private let headerLinks: [(String, String)] = [
    ("Getting Started", "getting-started.md"),
    ("Camera Control", "camera-control.md"),
]

private let geometryLinks: [(String, String)] = [
    ("Primitives", "primitives.md"),
    ("Options", "options.md"),
    ("Materials", "materials.md"),
    ("Transforms", "transforms.md"),
    ("Bounds", "bounds.md"),
    ("Meshes", "meshes.md"),
    ("Paths", "paths.md"),
    ("Text", "text.md"),
    ("Builders", "builders.md"),
    ("Constructive Solid Geometry", "csg.md"),
    ("Groups", "groups.md"),
    ("Lights", "lights.md"),
    ("Cameras", "cameras.md"),
]

private let syntaxLinks: [(String, String)] = [
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

private let footerLinks: [(String, String)] = [
    ("Examples", "examples.md"),
    ("Glossary", "glossary.md"),
]

private let versions: [String] = {
    let fm = FileManager.default
    var versions = Set([projectVersion])
    let files = try! fm.contentsOfDirectory(atPath: helpDirectory.path)
    for file in files where file.hasPrefix("1.") {
        versions.insert(file)
    }
    return versions.sorted(by: {
        $0.localizedStandardCompare($1) == .orderedAscending
    })
}()

private extension URL {
    func hasSuffix(_ suffix: String) -> Bool {
        deletingPathExtension().lastPathComponent.hasSuffix(suffix)
    }

    func appendingSuffix(_ suffix: String) -> URL {
        let name = deletingPathExtension().lastPathComponent
        return deletingPathExtension()
            .deletingLastPathComponent()
            .appendingPathComponent(name + suffix)
            .appendingPathExtension(pathExtension)
    }

    func deletingSuffix(_ suffix: String) -> URL {
        guard hasSuffix(suffix) else {
            return self
        }
        let name = deletingPathExtension().lastPathComponent
        return deletingPathExtension()
            .deletingLastPathComponent()
            .appendingPathComponent(String(name.dropLast(suffix.count)))
            .appendingPathExtension(pathExtension)
    }
}

private let urlRegex = try! NSRegularExpression(pattern: "\\]\\(([^\\)]*)\\)", options: [])

class MetadataTests: XCTestCase {
    // MARK: Releases

    func testProjectVersionMatchesChangelog() throws {
        let changelog = try String(contentsOf: changelogURL, encoding: .utf8)
        let range = try XCTUnwrap(changelog.range(of: "releases/tag/"))
        XCTAssertTrue(
            changelog[range.upperBound...].hasPrefix(projectVersion),
            "Project version \(projectVersion) does not match most recent tag in CHANGELOG.md"
        )
    }

    func testLatestVersionInChangelog() throws {
        let changelog = try String(contentsOf: changelogURL, encoding: .utf8)
        XCTAssertTrue(changelog.contains("[\(projectVersion)]"), "CHANGELOG.md does not mention latest release")
        XCTAssertTrue(
            changelog.contains("(https://github.com/nicklockwood/ShapeScript/releases/tag/\(projectVersion))"),
            "CHANGELOG.md does not include correct link for latest release"
        )
    }

    func testLatestVersionInPodspec() throws {
        let podspec = try String(contentsOf: podspecURL, encoding: .utf8)
        XCTAssertTrue(
            podspec.contains("\"version\": \"\(projectVersion)\""),
            "Podspec version does not match latest release"
        )
        XCTAssertTrue(
            podspec.contains("\"tag\": \"\(projectVersion)\""),
            "Podspec tag does not match latest release"
        )
    }

    func testVersionConstantUpdated() {
        XCTAssertEqual(ShapeScript.version, projectVersion)
    }

    func testChangelogDatesAreAscending() throws {
        var lastDate: Date?
        let dateParser = DateFormatter()
        dateParser.timeZone = TimeZone(identifier: "UTC")
        dateParser.locale = Locale(identifier: "en_GB")
        dateParser.dateFormat = " (yyyy-MM-dd)"
        for title in changelogTitles {
            let dateRange = try XCTUnwrap(title.range(of: " \\([^)]+\\)$", options: .regularExpression))
            let dateString = String(title[dateRange])
            let date = try XCTUnwrap(dateParser.date(from: dateString))
            if let lastDate, date > lastDate {
                XCTFail("\(title) has newer date than subsequent version (\(date) vs \(lastDate))")
                return
            }
            lastDate = date
        }
    }

    func testUpdateWhatsNew() throws {
        let changelog = try String(contentsOf: changelogURL, encoding: .utf8)
        var releases = [(version: String, date: String, notes: [String])]()
        var notes = [String]()
        for line in changelog.split(separator: "\n") {
            if line.hasPrefix("## [") {
                if !notes.isEmpty, !releases.isEmpty {
                    releases[releases.count - 1].notes = notes
                    notes.removeAll()
                }
                let versionStart = try XCTUnwrap(line.firstIndex(of: "["))
                let versionEnd = try XCTUnwrap(line.firstIndex(of: "]"))
                let version = line[line.index(after: versionStart) ..< versionEnd]
                let dateStart = try XCTUnwrap(line.lastIndex(of: "("))
                let dateEnd = try XCTUnwrap(line.lastIndex(of: ")"))
                let date = line[line.index(after: dateStart) ..< dateEnd]
                releases.append((String(version), String(date), []))
            } else if line.hasPrefix("-") {
                notes.append(String(line[line.index(after: line.startIndex)...]))
            }
        }
        if !notes.isEmpty, !releases.isEmpty {
            releases[releases.count - 1].notes = notes
            notes.removeAll()
        }

        let macBody = releases.map {
            #"""
            \f1\b\fs28 \cf2 ShapeScript \#($0.version) \'97 \#($0.date)\
            \
            \pard\tx220\tx720\pardeftab720\li720\fi-720\partightenfactor0
            \cf2 \kerning1\expnd0\expndtw0\#($0.notes.map {
                #"""
                   \'95
                \f0\b0 \expnd0\expndtw0\kerning0
                 \#($0).\
                \
                """#
            }.joined())
            """#
        }.joined(separator: "\n")

        let macWhatsNew = #"""
        {\rtf1\ansi\ansicpg1252\cocoartf2639
        \cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fnil\fcharset0 HelveticaNeue;\f1\fnil\fcharset0 HelveticaNeue-Bold;}
        {\colortbl;\red255\green255\blue255;\red0\green0\blue0;}
        {\*\expandedcolortbl;;\cssrgb\c0\c0\c0\cname textColor;}
        \paperw11900\paperh16840\margl1440\margr1440\vieww24140\viewh18420\viewkind0
        \deftab720
        \pard\pardeftab720\qc\partightenfactor0

        \f0\fs50 \cf2 \expnd0\expndtw0\kerning0
        What's New in ShapeScript?\
        \
        \pard\tx220\tx720\pardeftab720\li720\fi-720\partightenfactor0

        \#(macBody)
        }
        """#
        try macWhatsNew.write(to: whatsNewMacURL, atomically: true, encoding: .utf8)

        let iosBody = releases.map {
            #"""
            \f0\b \cf2 ShapeScript \#($0.version) \'97 \#($0.date)\
            \
            \pard\tx220\tx720\pardeftab720\li720\fi-720\partightenfactor0
            \cf2 \kerning1\expnd0\expndtw0
            \f1\b0 \expnd0\expndtw0\kerning0\#($0.notes.map {
                #"""
                   \'95
                \f1\b0 \expnd0\expndtw0\kerning0
                 \#($0).\
                \
                """#
            }.joined())
            """#
        }.joined(separator: "\n")

        let iosWhatsNew = #"""
        {\rtf1\ansi\ansicpg1252\cocoartf2639
        \cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fnil\fcharset0 HelveticaNeue-Bold;\f1\fnil\fcharset0 HelveticaNeue;}
        {\colortbl;\red255\green255\blue255;\red0\green0\blue0;}
        {\*\expandedcolortbl;;\cssrgb\c0\c0\c0\cname textColor;}
        \paperw11900\paperh16840\margl1440\margr1440\vieww24140\viewh18420\viewkind0
        \deftab720

        \#(iosBody)
        }
        """#
        try iosWhatsNew.write(to: whatsNewIOSURL, atomically: true, encoding: .utf8)
    }

    // MARK: Help

    func testUpdateIndex() throws {
        func findSections(in string: String) -> [(String, String)] {
            findHeadings(in: string).compactMap { heading in
                let fragment = heading.lowercased()
                    .replacingOccurrences(of: "'", with: "")
                    .replacingOccurrences(of: " ", with: "-")
                XCTAssert(!fragment.contains(where: {
                    !"abcdefghijklmnopqrstuvwxyz0123456789_-/".contains($0)
                }))
                return (heading, fragment)
            }
        }

        func buildLinks(_ links: [(String, String)], indent: Int) throws -> String {
            try links.map { heading, path in
                let file = helpSourceDirectory.appendingPathComponent(path)
                let text = try String(contentsOf: file)
                let indent = String(repeating: " ", count: indent * 4)
                let links = findSections(in: text).map { subheading, fragment in
                    "\n\(indent)    - [\(subheading)](\(path)#\(fragment))"
                }.joined()
                return "\(indent)- [\(heading)](\(path))" + links
            }.joined(separator: "\n")
        }

        let index = try """
        ShapeScript Help
        ---

        \(buildLinks(headerLinks, indent: 0))
        - Geometry
        \(buildLinks(geometryLinks, indent: 1))
        - Syntax
        \(buildLinks(syntaxLinks, indent: 1))
        \(buildLinks([("Export", "export.md")], indent: 0))
        \(buildLinks(footerLinks, indent: 0))

        """

        let existing = try String(contentsOf: helpIndexURL)
        XCTAssertEqual(existing, index)
        try index.write(to: helpIndexURL, atomically: true, encoding: .utf8)
    }

    func testHelpFooterLinks() throws {
        let indexLinks = headerLinks + geometryLinks + syntaxLinks + [
            ("Export", "export.md"),
        ] + footerLinks

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
                guard !url.hasPrefix("http") else {
                    continue
                }
                var fragment = ""
                let parts = url.components(separatedBy: "#")
                if parts.count == 2 {
                    url = parts[0]
                    fragment = parts[1]
                    if url.isEmpty {
                        url = fileURL.path
                    }
                }
                let absoluteURL = URL(fileURLWithPath: url, relativeTo: helpSourceDirectory)
                if url.hasSuffix(".png") {
                    referencedImages.insert(absoluteURL.lastPathComponent)
                }
                guard fm.fileExists(atPath: absoluteURL.path) else {
                    XCTFail("\(url) referenced in \(file) does not exist")
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

        let obsoleteImages = ["subtext-ios.png"]
        let imagesEnumerator = try XCTUnwrap(fm.enumerator(atPath: imagesDirectory.path))
        for case let file as String in imagesEnumerator where file.hasSuffix(".png") {
            let fileNames = [
                file,
                file.replacingOccurrences(
                    of: "-1\\.\\d\\.\\d\\.",
                    with: ".",
                    options: .regularExpression
                ),
                file.replacingOccurrences(
                    of: "-ios(-1\\.\\d\\.\\d)?\\.",
                    with: ".",
                    options: .regularExpression
                ),
            ]
            if !referencedImages.contains(where: fileNames.contains) {
                if !obsoleteImages.contains(where: fileNames.contains) {
                    XCTFail("Image \(file) not referenced in help")
                }
            } else if obsoleteImages.contains(where: fileNames.contains) {
                XCTFail("Obsolete image \(file) still referenced in help")
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
            guard fileURL.pathExtension == "md", !fileURL.hasSuffix("-ios") else {
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
            if fileURL.hasSuffix("-ios") {
                file = fileURL.deletingSuffix("-ios").lastPathComponent
            } else if fm.fileExists(atPath: fileURL.appendingSuffix("-ios").path) {
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
                if url.pathExtension == "png" {
                    let isMac = url.hasSuffix("-mac")
                    if isMac {
                        url = url.deletingSuffix("-mac")
                    }
                    if !url.hasSuffix("-ios") {
                        let iosURL = url.appendingSuffix("-ios")
                        let absoluteURL = URL(fileURLWithPath: iosURL.path, relativeTo: fileURL)
                        if fm.fileExists(atPath: absoluteURL.path) {
                            url = iosURL
                        }
                    }
                    for version in versions.reversed() {
                        let iosURL = url.appendingSuffix("-\(version)")
                        let absoluteURL = URL(fileURLWithPath: iosURL.path, relativeTo: fileURL)
                        if fm.fileExists(atPath: absoluteURL.path) {
                            url = iosURL
                            break
                        }
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
        let outputDirectory = helpDirectory.appendingPathComponent(projectVersion)
        guard fm.fileExists(atPath: outputDirectory.path) else {
            XCTFail("Help directory for \(projectVersion) not found")
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
