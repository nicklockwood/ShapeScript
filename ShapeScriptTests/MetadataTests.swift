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
                if parts.count == 2 {
                    url = parts[0]
                    fragment = parts[1]
                    if url.isEmpty {
                        url = fileURL.path
                    }
                }
                if !url.hasPrefix("http") {
                    let absoluteURL = URL(fileURLWithPath: url, relativeTo: helpDirectory)
                    if !FileManager.default.fileExists(atPath: absoluteURL.path) {
                        XCTFail("\(url) referenced in \(file) does not exist")
                    }
                    if !fragment.isEmpty {
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
    }
}
