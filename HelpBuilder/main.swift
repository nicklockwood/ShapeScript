//
//  main.swift
//  HelpBuilder
//
//  Created by Nick Lockwood on 12/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Foundation
import ShapeScript

private let projectDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let appProjectDirectory = projectDirectory.deletingLastPathComponent()

private let macHelpSourceDirectory = projectDirectory
    .appendingPathComponent("docs/mac/")

private let iosHelpSourceDirectory = projectDirectory
    .appendingPathComponent("docs/ios/")

private let docsImagesDirectory = projectDirectory
    .appendingPathComponent("docs/images")

private let macHelpHTMLDirectory = appProjectDirectory
    .appendingPathComponent("ShapeScriptHelp/_site/English.lproj")

private let iosHelpHTMLDirectory = projectDirectory
    .appendingPathComponent("Viewer/iOS/Documentation")

private let macHelpImageDirectories = [
    appProjectDirectory
        .appendingPathComponent("ShapeScriptHelp/_site/images"),
    appProjectDirectory
        .appendingPathComponent("Assets/ShapeScript.help/Contents/Resources/images"),
]

private let iosHelpImageDirectory = iosHelpHTMLDirectory.appendingPathComponent("images")

private let macHeader = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
    <head>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width initial-scale=1"/>
    <title>{title}</title>
    <meta name="description" content="{description}"/>
    <link rel="stylesheet" href="../css/main.css"/>
    <script src="../nav.js"></script>
</head>
<body class="help-page show-banner">
<header class="banner">
    <nav id="menu" class="dynamic">
        <ul>
            <li><a href="overview.html">Overview</a></li>
            <li><a href="getting-started.html">Getting Started</a></li>
            <li><a href="camera-control.html">Camera Control</a></li>

            <li class="group">
                <a class="name">Geometry</a>
                <ul class="list">
                    <li><a href="primitives.html">Primitives</a></li>
                    <li><a href="options.html">Options</a></li>
                    <li><a href="materials.html">Materials</a></li>
                    <li><a href="transforms.html">Transforms</a></li>
                    <li><a href="bounds.html">Bounds</a></li>
                    <li><a href="groups.html">Groups</a></li>
                    <li><a href="meshes.html">Meshes</a></li>
                    <li><a href="paths.html">Paths</a></li>
                    <li><a href="text.html">Text</a></li>
                    <li><a href="builders.html">Builders</a></li>
                    <li><a href="csg.html">Constructive Solid Geometry</a></li>
                    <li><a href="lights.html">Lights</a></li>
                    <li><a href="cameras.html">Cameras</a></li>
                </ul>
            </li>

            <li class="group">
                <a class="name">Syntax</a>
                <ul class="list">
                    <li><a href="comments.html">Comments</a></li>
                    <li><a href="literals.html">Literals</a></li>
                    <li><a href="symbols.html">Symbols</a></li>
                    <li><a href="expressions.html">Expressions</a></li>
                    <li><a href="functions.html">Functions</a></li>
                    <li><a href="commands.html">Commands</a></li>
                    <li><a href="control-flow.html">Control Flow</a></li>
                    <li><a href="blocks.html">Blocks</a></li>
                    <li><a href="scope.html">Scope</a></li>
                    <li><a href="debugging.html">Debugging</a></li>
                    <li><a href="import.html">Import</a></li>
                </ul>
            </li>

            <li><a href="export.html">Export</a></li>
            <li><a href="cli.html">Command Line Tool</a></li>
            <li><a href="examples.html">Examples</a></li>
            <li><a href="glossary.html">Glossary</a></li>
        </ul>
    </nav>
</header>
<main>
"""

private let iosHeader = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1"/>
    <title>{title}</title>
    <meta name="description" content="{description}"/>
    <link rel="stylesheet" href="documentation.css"/>
</head>
<body>
<main>
"""

private let footer = """
</main>
<footer>
</footer>
</body>
</html>
"""

private let iosCSS = """
:root {
    color-scheme: light dark;
    --tint-color: CanvasText;
    font: -apple-system-body;
}

body {
    margin: 0;
    color: CanvasText;
    background: Canvas;
}

main {
    box-sizing: border-box;
    max-width: 840px;
    margin: 0 auto;
    padding: 24px 20px 48px;
}

h1, h2, h3, h4, h5, h6 {
    font: -apple-system-headline;
    margin: 1.4em 0 0.5em;
}

h1 {
    font: -apple-system-title1;
    margin-top: 0;
}

p {
    margin: 0 0 0.75em;
}

ul, ol {
    margin: 0 0 0.75em;
    padding-inline-start: 1.5em;
}

li {
    margin: 0;
}

p, li {
    line-height: 1.45;
}

a {
    color: var(--tint-color);
    font-weight: 500;
    text-decoration: none;
}

a:active {
    opacity: 0.65;
}

code {
    font-family: ui-monospace, "SF Mono", Menlo, monospace;
    font-size: 0.8823529412em;
}

pre {
    overflow-x: auto;
    margin: 0 0 0.75em;
    padding: 10px 12px;
    color: CanvasText;
    background: color-mix(in srgb, CanvasText 8%, Canvas);
    tab-size: 4;
    white-space: pre;
    -webkit-overflow-scrolling: touch;
}

pre code {
    display: block;
    line-height: 1.25;
}

.tok-keyword {
    color: #AF52DE;
}

.tok-number {
    color: #FF9500;
}

.tok-string, .tok-color {
    color: #FF3B30;
}

.tok-comment {
    color: #8E8E93;
}

.tok-stdlib, .tok-member {
    color: #5856D6;
}

@media (prefers-color-scheme: dark) {
    .tok-stdlib, .tok-member {
        color: #5AC8FA;
    }
}

img {
    max-width: 100%;
    height: auto;
}

table {
    display: block;
    max-width: 100%;
    overflow-x: auto;
    margin: 0 0 1em;
    border-collapse: collapse;
    -webkit-overflow-scrolling: touch;
}

th, td {
    padding: 6px 20px 6px 0;
    text-align: left;
    vertical-align: top;
    line-height: 1.4;
}

th:last-child, td:last-child {
    padding-right: 0;
}

th {
    font-weight: 600;
}

thead th {
    border-bottom: 1px solid color-mix(in srgb, CanvasText 12%, Canvas);
}

tbody tr + tr {
    border-top: 1px solid color-mix(in srgb, CanvasText 12%, Canvas);
}

nav#footer-links {
    margin-top: 32px;
    padding-top: 16px;
    border-top: 1px solid color-mix(in srgb, CanvasText 18%, Canvas);
}
"""

struct HelpBuilder {
    func run() throws {
        let arguments = Set(CommandLine.arguments.dropFirst())
        guard arguments.isSubset(of: [
            "--ios-viewer",
            "--mac-helpbook",
            "--validate-ios-output",
            "--validate-mac-output",
            "--validate-output",
            "--all",
            "--help",
        ]) else {
            throw HelpBuilderError.invalidArguments
        }
        if arguments.contains("--help") {
            print("""
            Usage: swift run helpbuilder [--ios-viewer] [--mac-helpbook] [--validate-ios-output] [--validate-mac-output] [--validate-output]

            With no options, HelpBuilder regenerates the bundled iOS viewer documentation.
            --mac-helpbook also regenerates the app-wrapper Help Book HTML when run from ShapeScriptApp.
            --validate-ios-output validates the generated iOS viewer documentation output.
            --validate-mac-output validates the generated Mac Help Book HTML output.
            --validate-output validates both generated documentation outputs.
            """)
            return
        }

        let builder = Self()
        let shouldExportAll = arguments.contains("--all")
        if arguments.isEmpty || arguments.contains("--ios-viewer") || shouldExportAll {
            try builder.exportIOSHelp()
        }
        if arguments.contains("--mac-helpbook") || shouldExportAll {
            try builder.exportMacHelp()
        }
        let outputValidator = DocumentationOutputValidator()
        if arguments.contains("--validate-ios-output") || arguments.contains("--validate-output") || shouldExportAll {
            try outputValidator.validateIOSViewerDocumentation()
        }
        if arguments.contains("--validate-mac-output") || arguments.contains("--validate-output") || shouldExportAll {
            try outputValidator.validateMacHelpBook()
        }
    }

    private func exportMacHelp() throws {
        guard FileManager.default.fileExists(atPath: macHelpHTMLDirectory.deletingLastPathComponent().path) else {
            throw HelpBuilderError.missingAppWrapper
        }
        let renderer = DocumentationRenderer(header: macHeader, footer: footer)
        let images = try exportHTML(
            from: macHelpSourceDirectory,
            to: macHelpHTMLDirectory,
            renderer: renderer,
            skipIndex: true
        )
        for helpImageDirectory in macHelpImageDirectories {
            try syncImages(images, to: helpImageDirectory)
        }
    }

    private func exportIOSHelp() throws {
        let renderer = DocumentationRenderer(
            header: iosHeader,
            footer: footer,
            requireFooterLink: false,
            includeIndexFooterLink: true,
            highlightShapeScriptCode: true,
            rewriteLinkPath: { path in
                rewriteEmbeddedDocumentationLink(path)
            },
            rewriteImagePath: { path in
                "images/\(URL(string: path)?.lastPathComponent ?? path)"
            }
        )
        let images = try exportHTML(
            from: iosHelpSourceDirectory,
            to: iosHelpHTMLDirectory,
            renderer: renderer,
            skipIndex: false
        )
        try iosCSS.write(
            to: iosHelpHTMLDirectory.appendingPathComponent("documentation.css"),
            atomically: true,
            encoding: .utf8
        )
        try syncImages(images, to: iosHelpImageDirectory)
    }

    private func exportHTML(
        from sourceDirectory: URL,
        to outputDirectory: URL,
        renderer: DocumentationRenderer,
        skipIndex: Bool
    ) throws -> Set<String> {
        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let enumerator = fm.enumerator(atPath: sourceDirectory.path)!
        var images = Set<String>()

        for case let file as String in enumerator where file.hasSuffix(".md") {
            let sourceURL = sourceDirectory.appendingPathComponent(file)
            let fileName = sourceURL.deletingPathExtension().lastPathComponent
            guard !skipIndex || fileName != "index" else {
                continue
            }

            let htmlURL = outputDirectory
                .appendingPathComponent(file)
                .deletingPathExtension()
                .appendingPathExtension("html")
            let description = try previousDescription(at: htmlURL)
            let source = try String(contentsOf: sourceURL)
            try images.formUnion(DocumentationMarkdown.imageReferences(in: source))
            let page = try renderer.render(
                markdown: source,
                fileName: fileName,
                description: description
            )
            try renderer.documentHTML(for: page).write(
                to: htmlURL,
                atomically: true,
                encoding: .utf8
            )
        }

        return images
    }

    private func previousDescription(at htmlURL: URL) throws -> String {
        guard let previousHTML = try? String(contentsOf: htmlURL) else {
            return ""
        }
        let descriptionRegex = try NSRegularExpression(
            pattern: #"<meta name="description" content="([^"]+)"/>"#
        )
        let nsHTML = previousHTML as NSString
        guard let match = descriptionRegex.firstMatch(
            in: previousHTML,
            range: NSRange(location: 0, length: nsHTML.length)
        ) else {
            return ""
        }
        return nsHTML.substring(with: match.range(at: 1))
    }

    private func syncImages(_ images: Set<String>, to outputDirectory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let existingImages = try fm.contentsOfDirectory(atPath: outputDirectory.path)
            .filter { !$0.hasPrefix(".") }
        for image in existingImages where !images.contains(image) {
            try fm.removeItem(at: outputDirectory.appendingPathComponent(image))
        }

        for image in images.sorted() {
            let sourceURL = docsImagesDirectory.appendingPathComponent(image)
            guard fm.fileExists(atPath: sourceURL.path) else {
                throw HelpBuilderError.missingImage(image)
            }
            let outputURL = outputDirectory.appendingPathComponent(image)
            if fm.fileExists(atPath: outputURL.path) {
                try fm.removeItem(at: outputURL)
            }
            try fm.copyItem(at: sourceURL, to: outputURL)
        }
    }
}

private func rewriteEmbeddedDocumentationLink(_ path: String) -> String {
    guard path.hasPrefix("../") else {
        return path
    }
    let baseURL = URL(string: "https://shapescript.info/\(ShapeScript.version)/ios/")!
    return URL(string: path, relativeTo: baseURL)?.absoluteURL.absoluteString ?? path
}

enum HelpBuilderError: Error, CustomStringConvertible {
    case invalidArguments
    case missingAppWrapper
    case missingImage(String)
    case validationFailed([String])

    var description: String {
        switch self {
        case .invalidArguments:
            "Usage: swift run helpbuilder [--ios-viewer] [--mac-helpbook] [--validate-ios-output] [--validate-mac-output] [--validate-output]"
        case .missingAppWrapper:
            "Cannot export Mac Help Book HTML because the ShapeScriptApp wrapper directories were not found."
        case let .missingImage(image):
            "Image referenced by help docs does not exist: \(image)"
        case let .validationFailed(issues):
            "Generated documentation validation failed:\n\(issues.joined(separator: "\n"))"
        }
    }
}

try HelpBuilder().run()
