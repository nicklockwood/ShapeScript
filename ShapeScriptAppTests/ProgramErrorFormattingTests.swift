//
//  ProgramErrorFormattingTests.swift
//  ShapeScriptAppTests
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

@testable import ShapeScript
@testable import Viewer
import Cocoa
import XCTest

final class ProgramErrorFormattingTests: XCTestCase {
    func testLongSourceLineStopsAfterLastHighlightedFragment() throws {
        let source = "cube { unknown " + String(repeating: "12345 ", count: 40) + " }"
        let range = try XCTUnwrap(source.range(of: "unknown"))
        let error = ProgramError.runtimeError(RuntimeError(.custom("Invalid expression"), at: range))
        let message = error.message(with: source)
        XCTAssertTrue(message.string.contains(source))
        let excerpt = ErrorExcerpt(line: source, range: range)
        let font = try XCTUnwrap(NSFont(name: "Courier", size: 15))
        let wrapped = excerpt.layout(width: 180, attributes: [.font: font])
        let lines = wrapped.string.split(separator: "\n")
        let sourceLines = lines.filter { !$0.allSatisfy { $0 == "^" } }
        let visibleSource = sourceLines.map(String.init).joined()
        XCTAssertTrue(source.hasPrefix(visibleSource))
        XCTAssertLessThan(visibleSource.count, source.count)
        XCTAssertFalse(wrapped.string.contains("…"))
        let caretIndex = try XCTUnwrap(lines.firstIndex { $0.contains("^") })
        XCTAssertTrue(lines[caretIndex - 1].contains("unknown"))
        XCTAssertEqual(caretIndex, lines.count - 1)
        let wide = excerpt.layout(width: 400, attributes: [.font: font]).string
        XCTAssertGreaterThan(wide.count, wrapped.string.count)
    }

    func testTruncationKeepsWholeFragmentAfterHighlight() throws {
        let source = "unknown tail " + String(repeating: "extra ", count: 20)
        let range = try XCTUnwrap(source.range(of: "unknown"))
        let font = try XCTUnwrap(NSFont(name: "Courier", size: 15))
        let excerpt = ErrorExcerpt(line: source, range: range)
        let lines = excerpt.layout(width: 140, attributes: [.font: font]).string.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("unknown tail"))
        XCTAssertEqual(lines[1], "^^^^^^^")
    }

    func testShortSourceLineRetainsOriginalAnnotation() throws {
        let source = "print \"🌍\" unknown"
        let range = try XCTUnwrap(source.range(of: "unknown"))
        let error = ProgramError.runtimeError(RuntimeError(.custom("Invalid expression"), at: range))
        let expected = try XCTUnwrap(error.annotatedErrorLine(with: source))
        XCTAssertTrue(error.message(with: source).string.contains(expected))
        XCTAssertFalse(error.message(with: source).string.contains("…"))
    }

    func testEmptyErrorRangeShowsCaretAtEndOfLine() {
        let source = "cube {"
        let error = ProgramError.runtimeError(RuntimeError(
            .custom("Expected closing brace"), at: source.endIndex ..< source.endIndex
        ))
        XCTAssertTrue(error.message(with: source).string.contains("cube {\n      ^\n"))
    }

    func testWrappedErrorHasCaretsUnderEveryAffectedFragment() throws {
        let source = String(repeating: "x", count: 50)
        let excerpt = ErrorExcerpt(line: source, range: source.startIndex ..< source.endIndex)
        let font = try XCTUnwrap(NSFont(name: "Courier", size: 15))
        let output = excerpt.layout(width: 90, attributes: [.font: font])
        let lines = output.string.split(separator: "\n")
        XCTAssertGreaterThan(lines.count, 2)
        XCTAssertEqual(lines.count % 2, 0)
        for index in stride(from: 0, to: lines.count, by: 2) {
            XCTAssertTrue(lines[index].allSatisfy { $0 == "x" })
            XCTAssertEqual(lines[index + 1], Substring(String(repeating: "^", count: lines[index].count)))
        }
        XCTAssertEqual(lines.enumerated().filter { $0.offset % 2 == 0 }.map { String($0.element) }.joined(), source)
    }

    func testWrappedPrefixKeepsCaretsImmediatelyBelowError() throws {
        let source = "print \"🌍\" " + String(repeating: "1 ", count: 40) + "unknown"
        let range = try XCTUnwrap(source.range(of: "unknown"))
        let excerpt = ErrorExcerpt(line: source, range: range)
        let font = try XCTUnwrap(NSFont(name: "Courier", size: 15))
        let lines = excerpt.layout(width: 160, attributes: [.font: font]).string.split(separator: "\n")
        XCTAssertTrue(lines[lines.count - 2].contains("unknown"))
        XCTAssertEqual(lines.last, "^^^^^^^")
    }

    func testUnexpectedEOFHighlightsLastContentLine() throws {
        for suffix in ["", "\n", "\r\n", "\n\n", "\n \t"] {
            let source = "cube {" + suffix
            do {
                _ = try parse(source)
                XCTFail("Expected a parse error")
            } catch {
                let error = ProgramError(error)
                XCTAssertEqual(error.message, "Unexpected end of file")
                let (line, range) = try XCTUnwrap(error.errorLineAndRange(with: source))
                XCTAssertEqual(line, "cube {")
                XCTAssertEqual(range, line.endIndex ..< line.endIndex)
                let message = error.message(with: source)
                XCTAssertTrue(message.string.contains("cube {\n      ^\n"))
                let wrapped = message.wrappingErrorExcerpt(toWidth: 180)
                XCTAssertTrue(wrapped.string.contains("cube {\n^\n"))
            }
        }
    }
}
