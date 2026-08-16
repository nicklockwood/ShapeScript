//
//  ShapeScriptSyntaxHighlighter.swift
//  HelpBuilder
//
//  Created by Nick Lockwood on 12/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Foundation
import ShapeScript

enum ShapeScriptSyntaxHighlighter {
    static func highlightCodeBlocks(in html: String) throws -> String {
        let regex = try NSRegularExpression(
            pattern: #"<pre><code class="language-swift">([\s\S]*?)</code></pre>"#
        )
        var html = html
        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        for match in regex.matches(in: html, range: range).reversed() {
            let code = nsHTML.substring(with: match.range(at: 1))
            guard let replacementRange = Range(match.range, in: html) else {
                continue
            }
            html.replaceSubrange(
                replacementRange,
                with: """
                <pre><code class="language-shapescript">\(highlight(code))</code></pre>
                """
            )
        }
        return html
    }

    private static func highlight(_ input: String) -> String {
        var html = ""
        var cursor = input.startIndex

        for token in semanticTokens(for: input) {
            let gap = cursor ..< token.range.lowerBound
            if !gap.isEmpty {
                html += input[gap].htmlEscaped
            }
            html += highlighted(input[token.range], as: token.syntaxClass)
            cursor = token.range.upperBound
        }

        let tail = cursor ..< input.endIndex
        if !tail.isEmpty {
            html += input[tail].htmlEscaped
        }
        return html
    }

    private static func highlighted(_ string: some StringProtocol, as syntaxClass: SyntaxClass?) -> String {
        guard let syntaxClass else {
            return string.htmlEscaped
        }
        return #"<span class="\#(syntaxClass.rawValue)">\#(string.htmlEscaped)</span>"#
    }
}

private struct SemanticToken {
    var syntaxClass: SyntaxClass?
    var range: ShapeScript.SourceRange
}

private func semanticTokens(for input: String) -> [SemanticToken] {
    var stack = [Set<String>()]
    var isSwitch = [false]
    var lastKeyword: String?
    var lastToken: ShapeScript.Token?
    return (try? tokenize(input).flatMap { token -> [SemanticToken] in
        defer { lastToken = token }
        var syntaxClass = token.type.syntaxClass
        switch token.type {
        case .lbrace:
            stack.append(stack.last!)
            isSwitch.append(lastKeyword == "switch")
        case .rbrace where stack.count > 1:
            stack.removeLast()
            isSwitch.removeLast()
        case .linebreak, .eof:
            lastKeyword = nil
        case let .keyword(name):
            lastKeyword = name.rawValue
        case let .identifier(name):
            if lastKeyword == "option",
               case .identifier("option")? = lastToken?.type
            {
                stack[stack.count - 1].insert(name)
                lastKeyword = nil
                break
            }
            if isSwitch.last == true, name == "case" {
                syntaxClass = .keyword
                break
            }
            if case .keyword(.define)? = lastToken?.type {
                stack[stack.count - 1].insert(name)
                lastKeyword = nil
                break
            } else if case .dot = lastToken?.type {
                syntaxClass = .member
                break
            }
            if stack.last!.contains(name) {
                break
            }
            switch name {
            case "in", "to", "step", "option", "not", "true", "false", "switch":
                // contextual keywords
                syntaxClass = .keyword
                lastKeyword = name
            case _ where ShapeScript.stdlibSymbols.contains(name):
                syntaxClass = .stdlib
            default:
                break
            }
        default:
            break
        }
        let lastBound = lastToken?.range.upperBound ?? input.startIndex
        let lastRange = lastBound ..< token.range.lowerBound
        if !lastRange.isEmpty, input[lastRange].contains("/") {
            return [
                SemanticToken(syntaxClass: .default, range: lastRange),
                SemanticToken(syntaxClass: syntaxClass, range: token.range),
            ]
        }
        return [SemanticToken(syntaxClass: syntaxClass, range: token.range)]
    }) ?? []
}

private extension ShapeScript.TokenType {
    var syntaxClass: SyntaxClass? {
        switch self {
        case .keyword:
            .keyword
        case .hexColor:
            .color
        case .number:
            .number
        case .string:
            .string
        case .linebreak, .eof:
            nil
        case .dot, .prefix, .infix, .lbrace, .rbrace, .lparen, .rparen, .call,
             .lbracket, .rbracket, .subscript, .identifier:
            nil
        }
    }
}

private enum SyntaxClass: String {
    case `default` = "tok-default"
    case keyword = "tok-keyword"
    case string = "tok-string"
    case number = "tok-number"
    case color = "tok-color"
    case member = "tok-member"
    case stdlib = "tok-stdlib"
}

private extension StringProtocol {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
