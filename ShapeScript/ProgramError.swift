//
//  ProgramError.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 07/05/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import Foundation

public enum ProgramError: Error, Equatable {
    case lexerError(LexerError)
    case parserError(ParserError)
    case runtimeError(RuntimeError)
    case unknownError(String?)
}

public extension ProgramError {
    init(_ error: Error) {
        switch error {
        case let error as ProgramError: self = error
        case let error as LexerError: self = .lexerError(error)
        case let error as ParserError: self = .parserError(error)
        case let error as RuntimeError: self = .runtimeError(error)
        default:
            let message = error.localizedDescription
            self = .unknownError(message.hasSuffix(".") ? "\(message.dropLast())" : message)
        }
    }

    var message: String {
        switch self {
        case let .lexerError(error): return error.message
        case let .parserError(error): return error.message
        case let .runtimeError(error): return error.message
        case let .unknownError(message): return message ?? "Unknown error"
        }
    }

    var range: SourceRange? {
        switch self {
        case let .lexerError(error): return error.range
        case let .parserError(error): return error.range
        case let .runtimeError(error): return error.range
        case .unknownError: return nil
        }
    }

    var hint: String? {
        switch self {
        case let .lexerError(error): return error.hint
        case let .parserError(error): return error.hint
        case let .runtimeError(error): return error.hint
        case .unknownError: return nil
        }
    }

    /// If the error relates to file access permissions, returns the URL of that file.
    var accessErrorURL: URL? {
        switch underlyingError {
        case let .runtimeError(runtimeError):
            return runtimeError.accessErrorURL
        case .parserError, .lexerError, .unknownError:
            return nil
        }
    }

    /// Returns the URL of the .shape file in which the error occured.
    func shapeFileURL(relativeTo baseURL: URL) -> URL {
        switch self {
        case let .runtimeError(runtimeError):
            switch runtimeError.type {
            case let .importError(error, url, _):
                guard let url = url, url.pathExtension == "shape" else {
                    return baseURL
                }
                return error.shapeFileURL(relativeTo: url)
            case .unknownSymbol, .unknownMember, .invalidIndex, .unknownFont,
                 .typeMismatch, .forwardReference, .unexpectedArgument,
                 .missingArgument, .unusedValue, .assertionFailure,
                 .fileNotFound, .fileTimedOut, .fileAccessRestricted,
                 .fileTypeMismatch, .fileParsingError, .circularImport:
                return baseURL
            }
        case .lexerError, .parserError, .unknownError:
            return baseURL
        }
    }

    /// Returns the underlying error if the error was triggered inside an imported file, etc.
    var underlyingError: ProgramError {
        switch self {
        case let .runtimeError(runtimeError):
            switch runtimeError.type {
            case let .importError(error, _, _):
                return error.underlyingError
            case .unknownSymbol, .unknownMember, .invalidIndex, .unknownFont,
                 .typeMismatch, .forwardReference, .unexpectedArgument, .missingArgument,
                 .unusedValue, .assertionFailure, .fileNotFound, .fileTimedOut,
                 .fileAccessRestricted, .fileTypeMismatch, .fileParsingError,
                 .circularImport:
                return self
            }
        case .lexerError, .parserError, .unknownError:
            return self
        }
    }

    /// Returns the the range at which the error occurred within the specified source string.
    /// If the error occurred at a known location inside an imported file,
    /// the range and source for that file will be returned instead.
    func rangeAndSource(with source: String) -> (SourceRange, source: String)? {
        if case let .runtimeError(runtimeError) = self,
           case let .importError(error, for: _, in: source) = runtimeError.type,
           error.range != nil
        {
            return error.rangeAndSource(with: source)
        }
        return range.map { ($0, source) }
    }

    /// Returns the error message and line number on which it occured.
    func messageAndLocation(with source: String) -> String {
        guard let (range, source) = rangeAndSource(with: source) else {
            return message
        }
        let (line, _) = source.lineAndColumn(at: range.lowerBound)
        return "\(message) on line \(line)."
    }

    /// Returns the source line where the error occurred and range of the error within that line.
    func errorLineAndRange(
        with source: String,
        includingIndent: Bool = false
    ) -> (line: String, lineRange: SourceRange)? {
        guard let (range, source) = rangeAndSource(with: source) else {
            return nil
        }
        let lineRange = source.lineRange(
            at: range.lowerBound,
            includingIndent: includingIndent
        )
        if lineRange.isEmpty {
            return nil
        }
        let sourceLine = String(source[lineRange])
        let lowerBound = max(range.lowerBound, lineRange.lowerBound)
        let upperBound = min(range.upperBound, lineRange.upperBound)
        let offset = source.distance(from: lineRange.lowerBound, to: lowerBound)
        let length = source.distance(from: lowerBound, to: upperBound)
        let start = sourceLine.index(sourceLine.startIndex, offsetBy: offset)
        let end = sourceLine.index(start, offsetBy: length)
        return (sourceLine, start ..< end)
    }

    /// Returns the source line where the error occurred, with the error itself underlined.
    func annotatedErrorLine(
        with source: String,
        includingIndent: Bool = false
    ) -> String? {
        guard let (line, range) = errorLineAndRange(
            with: source,
            includingIndent: includingIndent
        ) else {
            return nil
        }
        let indentString = line[..<range.lowerBound]
        let errorString = line[range]
        let underline = String(
            repeating: " ",
            count: indentString.count + emojiSpacing(for: indentString)
        ) + String(
            repeating: "^",
            count: max(1, errorString.count + emojiSpacing(for: errorString))
        )
        return "\(line)\n\(underline)"
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
