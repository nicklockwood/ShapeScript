//
//  ProgramError.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 01/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Cocoa
import ShapeScript

protocol ProgramError {
    var message: String { get }
    var range: Range<String.Index> { get }
    var hint: String? { get }
}

extension LexerError: ProgramError {}
extension ParserError: ProgramError {}
extension RuntimeError: ProgramError {}
extension ImportError: ProgramError {}

extension ProgramError {
    func rangeAndSource(with source: String) -> (Range<String.Index>?, source: String) {
        switch self {
        case let error as ImportError:
            if case let .runtimeError(error) = error {
                return error.rangeAndSource(with: source)
            }
            return (error.range, source)
        case let error as ProgramError:
            switch (error as? RuntimeError)?.type {
            case let .importError(error, for: _, in: source)?:
                return error.rangeAndSource(with: source)
            default:
                return (error.range, source)
            }
        default:
            return (nil, source)
        }
    }
}

extension Error {
    func message(with source: String) -> NSAttributedString {
        var source = source
        let errorType: String
        let message: String, range: Range<String.Index>?, hint: String?
        switch self {
        case let error as ProgramError:
            (range, source) = error.rangeAndSource(with: source)
            switch (error as? RuntimeError)?.type {
            case .fileAccessRestricted?:
                errorType = "Permission Required"
            default:
                errorType = "Error"
            }
            message = error.message
            hint = error.hint
        default:
            errorType = "Error"
            message = localizedDescription
            range = nil
            hint = nil
        }

        var location = "."
        var lineRange: Range<String.Index>?
        if let range = range {
            let (line, _) = source.lineAndColumn(at: range.lowerBound)
            location = " on line \(line)."
            let lr = source.lineRange(at: range.lowerBound)
            if !lr.isEmpty {
                lineRange = lr
            }
        }

        let errorMessage = NSMutableAttributedString()
        errorMessage.append(NSAttributedString(string: "\(errorType)\n\n", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 17, weight: .bold),
        ]))
        let body = message + location
        errorMessage.append(NSAttributedString(string: "\(body)\n\n", attributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.7),
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
        ]))
        if let lineRange = lineRange, let range = range,
           let font = NSFont(name: "Courier", size: 15)
        {
            let sourceLine = String(source[lineRange])
            let start = source.distance(from: lineRange.lowerBound, to: range.lowerBound) +
                emojiSpacing(for: source[lineRange.lowerBound ..< range.lowerBound])
            let end = min(range.upperBound, lineRange.upperBound)
            let length = max(1, source.distance(from: range.lowerBound, to: end)) +
                emojiSpacing(for: source[range.lowerBound ..< end])
            var underline = String(repeating: " ", count: max(0, start))
            underline += String(repeating: "^", count: length)
            errorMessage.append(NSAttributedString(
                string: "\(sourceLine)\n\(underline)\n\n",
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: font,
                ]
            ))
        }
        if let hint = hint {
            errorMessage.append(NSAttributedString(string: "\(hint)\n\n", attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.7),
                .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            ]))
        }
        return errorMessage
    }
}

private func numberOfEmoji<S: StringProtocol>(in string: S) -> Int {
    string.reduce(0) { count, c in
        let scalars = c.unicodeScalars
        if scalars.count > 1 || (scalars.first?.value ?? 0) > 0x238C {
            return count + 1
        }
        return count
    }
}

private func emojiSpacing<S: StringProtocol>(for string: S) -> Int {
    Int(Double(numberOfEmoji(in: string)) * 1.25)
}
