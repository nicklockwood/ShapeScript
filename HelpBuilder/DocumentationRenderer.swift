//
//  DocumentationRenderer.swift
//  HelpBuilder
//
//  Created by Nick Lockwood on 12/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Foundation
import Markdown

struct DocumentationPage {
    let fileName: String
    var title: String = ""
    var description: String = ""
    var bodyHTML: String
}

enum DocumentationMarkdown {
    static func renderBodyHTML(from markdown: String) -> String {
        HTMLFormatter.format(Document(parsing: markdown))
    }

    static func imageReferences(in markdown: String) throws -> Set<String> {
        let regex = try NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)]+)\)"#)
        let nsMarkdown = markdown as NSString
        let range = NSRange(location: 0, length: nsMarkdown.length)
        var images = Set<String>()
        for match in regex.matches(in: markdown, range: range) {
            let imagePath = nsMarkdown.substring(with: match.range(at: 1))
            guard !imagePath.hasPrefix("http"),
                  let url = URL(string: imagePath),
                  url.lastPathComponent.isEmpty == false,
                  url.pathComponents.contains("images")
            else {
                continue
            }
            images.insert(url.lastPathComponent)
        }
        return images
    }
}

struct DocumentationRenderer {
    var header: String
    var footer: String
    var requireFooterLink: Bool = true
    var includeIndexFooterLink: Bool = false
    var rewriteMarkdownLinks: Bool = true
    var rewriteImagePath: ((String) -> String)?

    func render(markdown: String, fileName: String, description: String = "") throws -> DocumentationPage {
        var page = DocumentationPage(
            fileName: fileName,
            description: description,
            bodyHTML: DocumentationMarkdown.renderBodyHTML(from: markdown)
        )
        page.bodyHTML = try processBody(page.bodyHTML, page: &page)
        if page.description.isEmpty {
            page.description = page.title
        }
        return page
    }

    func documentHTML(for page: DocumentationPage) -> String {
        """
        \(processHeader(header, page: page))
        \(page.bodyHTML)
        \(footer)
        """
    }

    private func processBody(_ html: String, page: inout DocumentationPage) throws -> String {
        var body = rewriteMarkdownLinks ?
            html.replacingOccurrences(of: ".md", with: ".html") :
            html
        if let rewriteImagePath {
            let imageRegex = try NSRegularExpression(pattern: #"<img src="([^"]+)""#)
            let nsBody = body as NSString
            let range = NSRange(location: 0, length: nsBody.length)
            for match in imageRegex.matches(in: body, range: range).reversed() {
                let path = nsBody.substring(with: match.range(at: 1))
                guard let replacementRange = Range(match.range, in: body) else {
                    continue
                }
                body.replaceSubrange(
                    replacementRange,
                    with: "<img src=\"\(rewriteImagePath(path))\""
                )
            }
        }
        body = try processSingleParagraphListItems(in: body)

        let headingRegex = try NSRegularExpression(pattern: #"<h2>([^<]+)</h2>"#)
        guard let match = headingRegex.firstMatch(
            in: body,
            range: NSRange(location: 0, length: (body as NSString).length)
        ) else {
            if page.fileName == "index" {
                page.title = "ShapeScript Help"
                return body
            }
            throw DocumentationRenderError.missingTitle(page.fileName)
        }
        let nsBody = body as NSString
        page.title = nsBody.substring(with: match.range(at: 1))
        if let range = Range(match.range, in: body) {
            body.replaceSubrange(
                range,
                with: "<h1><a name=\"\(page.fileName)\"></a>\(page.title)</h1>"
            )
        }

        let subheadingRegex = try NSRegularExpression(pattern: #"<h([2-9])>([^<]+)"#)
        while let match = subheadingRegex.firstMatch(
            in: body,
            range: NSRange(location: 0, length: (body as NSString).length)
        ) {
            let nsBody = body as NSString
            let headingLevel = nsBody.substring(with: match.range(at: 1))
            let heading = nsBody.substring(with: match.range(at: 2))
            let fragment = try headingFragment(heading)
            guard let range = Range(match.range, in: body) else {
                break
            }
            body.replaceSubrange(range, with: "<h\(headingLevel) id=\"\(fragment)\">\(heading)")
        }

        let footerRegex = try NSRegularExpression(
            pattern: #"<hr />\n<p><a href="index.html">Index</a> \| Next: <a href="([^"]+)">([^"]+)</a></p>"#
        )
        guard let match = footerRegex.firstMatch(
            in: body,
            range: NSRange(location: 0, length: (body as NSString).length)
        ) else {
            body = try processIndexFooter(in: body)
            if page.fileName == "glossary" || !requireFooterLink {
                return body
            }
            throw DocumentationRenderError.missingFooter(page.fileName)
        }
        let nsBodyAfterSubheadings = body as NSString
        let nextURL = nsBodyAfterSubheadings.substring(with: match.range(at: 1))
        let nextTitle = nsBodyAfterSubheadings.substring(with: match.range(at: 2))
        if let range = Range(match.range, in: body) {
            let indexLink = includeIndexFooterLink ?
                "<a href=\"index.html\">Index</a> | " :
                ""
            body.replaceSubrange(
                range,
                with: "<nav id=\"footer-links\">\(indexLink)Next: <a href=\"\(nextURL)\">\(nextTitle)</a></nav>"
            )
        }

        return body
    }

    private func processIndexFooter(in html: String) throws -> String {
        guard includeIndexFooterLink else {
            return html
        }
        var html = html
        let indexFooterRegex = try NSRegularExpression(
            pattern: #"<hr />\n<p><a href="index.html">Index</a></p>"#
        )
        guard let match = indexFooterRegex.firstMatch(
            in: html,
            range: NSRange(location: 0, length: (html as NSString).length)
        ), let range = Range(match.range, in: html) else {
            return html
        }
        html.replaceSubrange(
            range,
            with: "<nav id=\"footer-links\"><a href=\"index.html\">Index</a></nav>"
        )
        return html
    }

    private func processSingleParagraphListItems(in html: String) throws -> String {
        let regex = try NSRegularExpression(pattern: #"<li><p>([^\n]*?)</p>\n</li>"#)
        var html = html
        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        for match in regex.matches(in: html, range: range).reversed() {
            guard let range = Range(match.range, in: html),
                  let contentRange = Range(match.range(at: 1), in: html)
            else {
                continue
            }
            html.replaceSubrange(range, with: "<li>\(html[contentRange])</li>")
        }
        return html
    }

    private func processHeader(_ header: String, page: DocumentationPage) -> String {
        header
            .replacingOccurrences(of: "{title}", with: page.title)
            .replacingOccurrences(of: "{description}", with: page.description)
            .replacingOccurrences(
                of: "<li><a href=\"\(page.fileName).html",
                with: "<li class=\"active\"><a href=\"\(page.fileName).html"
            )
    }
}

enum DocumentationRenderError: Error, CustomStringConvertible {
    case invalidFragment(String)
    case missingTitle(String)
    case missingFooter(String)

    var description: String {
        switch self {
        case let .invalidFragment(fragment):
            "Invalid fragment: \(fragment)"
        case let .missingTitle(fileName):
            "No title in \(fileName)"
        case let .missingFooter(fileName):
            "No footer in \(fileName)"
        }
    }
}

func headingFragment(_ heading: some StringProtocol) throws -> String {
    let fragment = heading.lowercased()
        .replacingOccurrences(of: "'", with: "")
        .replacingOccurrences(of: " ", with: "-")
    guard !fragment.contains(where: {
        !"abcdefghijklmnopqrstuvwxyz0123456789_-/".contains($0)
    }) else {
        throw DocumentationRenderError.invalidFragment(fragment)
    }
    return fragment
}
