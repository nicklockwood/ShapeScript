//
//  DocumentationOutputValidator.swift
//  HelpBuilder
//
//  Created by Nick Lockwood on 12/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Foundation

struct DocumentationOutputValidator {
    private let projectDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private var appProjectDirectory: URL {
        projectDirectory.deletingLastPathComponent()
    }

    private var iosViewerHelpDirectory: URL {
        projectDirectory.appendingPathComponent("Viewer/iOS/Help")
    }

    private var macHelpBookDirectory: URL {
        appProjectDirectory.appendingPathComponent("ShapeScriptHelp/_site")
    }

    func validateIOSViewerHelp() throws {
        var issues = [String]()
        let fm = FileManager.default
        let outputDirectory = iosViewerHelpDirectory

        guard fm.fileExists(atPath: outputDirectory.path) else {
            throw HelpBuilderError.validationFailed([
                "Missing iOS viewer documentation directory: \(outputDirectory.path)",
            ])
        }

        let cssURL = outputDirectory.appendingPathComponent("documentation.css")
        if !fm.fileExists(atPath: cssURL.path) {
            issues.append("Missing stylesheet: \(relativePath(cssURL, relativeTo: outputDirectory))")
        }

        let htmlFiles = try fm.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "html" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        if htmlFiles.isEmpty {
            issues.append("No HTML files found in \(relativePath(outputDirectory, relativeTo: outputDirectory))")
        }

        let requiredPages = ["index.html", "editor-help.html"]
        for fileName in requiredPages {
            let url = outputDirectory.appendingPathComponent(fileName)
            if !fm.fileExists(atPath: url.path) {
                issues.append("Missing required page: \(relativePath(url, relativeTo: outputDirectory))")
            }
        }

        let singleParagraphListItemRegex = try NSRegularExpression(
            pattern: #"<li><p>[^\n]*?</p>\n</li>"#
        )
        for htmlURL in htmlFiles {
            let html = try String(contentsOf: htmlURL)
            validateIOSViewerHTML(html, at: htmlURL, issues: &issues)

            if html.contains(#"language-swift"#) {
                issues.append(
                    "\(relativePath(htmlURL, relativeTo: outputDirectory)) contains a Swift code block; ShapeScript samples should be highlighted as language-shapescript"
                )
            }
            if html.contains(#"<pre><code class="language-shapescript">"#),
               !html.contains(#"class="tok-"#)
            {
                issues.append(
                    "\(relativePath(htmlURL, relativeTo: outputDirectory)) contains ShapeScript code without syntax highlighting spans"
                )
            }

            let range = NSRange(location: 0, length: (html as NSString).length)
            if singleParagraphListItemRegex.firstMatch(in: html, range: range) != nil {
                issues.append(
                    "\(relativePath(htmlURL, relativeTo: outputDirectory)) contains a single-paragraph list item wrapped in <p>"
                )
            }

            try validateLocalReferences(
                in: html,
                from: htmlURL,
                rootedAt: outputDirectory,
                issues: &issues
            )
        }

        if !issues.isEmpty {
            throw HelpBuilderError.validationFailed(issues)
        }
    }

    func validateMacHelpBook() throws {
        var issues = [String]()
        let localizedDirectory = macHelpBookDirectory.appendingPathComponent("English.lproj")

        guard FileManager.default.fileExists(atPath: localizedDirectory.path) else {
            throw HelpBuilderError.validationFailed([
                "Missing Mac Help Book directory: \(localizedDirectory.path)",
            ])
        }

        try validateLocalReferences(
            inHTMLFilesUnder: localizedDirectory,
            rootedAt: macHelpBookDirectory,
            issues: &issues
        )

        if !issues.isEmpty {
            throw HelpBuilderError.validationFailed(issues)
        }
    }

    private func validateIOSViewerHTML(
        _ html: String,
        at htmlURL: URL,
        issues: inout [String]
    ) {
        let relativeHTMLPath = relativePath(htmlURL, relativeTo: iosViewerHelpDirectory)
        if !html.contains(#"<link rel="stylesheet" href="documentation.css"/>"#) {
            issues.append("\(relativeHTMLPath) does not reference documentation.css")
        }
        if !html.contains(#"<main>"#) || !html.contains(#"</main>"#) {
            issues.append("\(relativeHTMLPath) is missing the expected <main> wrapper")
        }
        if htmlURL.lastPathComponent != "index.html", !html.contains(#"<nav id="footer-links">"#) {
            issues.append("\(relativeHTMLPath) is missing footer navigation")
        }
    }

    private func validateLocalReferences(
        inHTMLFilesUnder directory: URL,
        rootedAt rootDirectory: URL,
        issues: inout [String]
    ) throws {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            issues.append("Could not enumerate HTML files under \(directory.path)")
            return
        }

        for case let htmlURL as URL in enumerator where htmlURL.pathExtension == "html" {
            let html = try String(contentsOf: htmlURL)
            try validateLocalReferences(
                in: html,
                from: htmlURL,
                rootedAt: rootDirectory,
                issues: &issues
            )
        }
    }

    private func validateLocalReferences(
        in html: String,
        from htmlURL: URL,
        rootedAt rootDirectory: URL,
        issues: inout [String]
    ) throws {
        let regex = try NSRegularExpression(pattern: #"(?:href|src)="([^"]+)""#)
        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)

        for match in regex.matches(in: html, range: range) {
            let reference = nsHTML.substring(with: match.range(at: 1))
            guard shouldValidate(reference) else {
                continue
            }

            let parts = reference.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            let path = parts.first.map(String.init) ?? ""
            let fragment = parts.count > 1 ? String(parts[1]) : nil
            let targetURL = path.isEmpty ? htmlURL : htmlURL.deletingLastPathComponent()
                .appendingPathComponent(path)
                .standardizedFileURL
            let relativeHTMLPath = relativePath(htmlURL, relativeTo: rootDirectory)

            guard isDescendant(targetURL, of: rootDirectory) else {
                issues.append("\(relativeHTMLPath) references file outside generated documentation: \(reference)")
                continue
            }

            guard FileManager.default.fileExists(atPath: targetURL.path) else {
                issues.append("\(relativeHTMLPath) references missing file: \(reference)")
                continue
            }

            if let fragment, !fragment.isEmpty, targetURL.pathExtension == "html" {
                let targetHTML = try String(contentsOf: targetURL)
                let encodedFragment = fragment.htmlEscapedForAttribute
                if !targetHTML.contains(#"id="\#(encodedFragment)""#),
                   !targetHTML.contains(#"name="\#(encodedFragment)""#)
                {
                    issues.append("\(relativeHTMLPath) references missing fragment: \(reference)")
                }
            }
        }
    }

    private func shouldValidate(_ reference: String) -> Bool {
        guard !reference.isEmpty, !reference.hasPrefix("#") else {
            return false
        }
        if let url = URL(string: reference), url.scheme != nil {
            return url.isFileURL
        }
        return true
    }

    private func relativePath(_ url: URL, relativeTo directory: URL) -> String {
        let path = url.standardizedFileURL.path
        let rootPath = directory.standardizedFileURL.path + "/"
        return path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : path
    }

    private func isDescendant(_ url: URL, of directory: URL) -> Bool {
        let rootPath = directory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }
}

private extension String {
    var htmlEscapedForAttribute: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
