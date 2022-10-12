//
//  Interpreter.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 26/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

// MARK: Public interface

public let version = "1.5.13"

public protocol EvaluationDelegate: AnyObject {
    func resolveURL(for path: String) -> URL
    func importGeometry(for url: URL) throws -> Geometry?
    func debugLog(_ values: [AnyHashable])
}

public func evaluate(
    _ program: Program,
    delegate: EvaluationDelegate?,
    cache: GeometryCache? = GeometryCache(),
    isCancelled: @escaping () -> Bool = { false }
) throws -> Scene {
    let context = EvaluationContext(
        source: program.source,
        delegate: delegate,
        isCancelled: isCancelled
    )
    try program.evaluate(in: context)
    return Scene(
        background: context.background ?? .color(.clear),
        children: context.children.compactMap { $0.value as? Geometry },
        cache: cache
    )
}

@available(*, renamed: "ProgramError")
public typealias ImportError = ProgramError

public enum ProgramError: Error, Equatable {
    case lexerError(LexerError)
    case parserError(ParserError)
    case runtimeError(RuntimeError)
    case unknownError
}

public extension ProgramError {
    init(_ error: Error) {
        switch error {
        case let error as ProgramError: self = error
        case let error as LexerError: self = .lexerError(error)
        case let error as ParserError: self = .parserError(error)
        case let error as RuntimeError: self = .runtimeError(error)
        default: self = .unknownError
        }
    }

    var message: String {
        switch self {
        case let .lexerError(error): return error.message
        case let .parserError(error): return error.message
        case let .runtimeError(error): return error.message
        case .unknownError: return "Unknown error"
        }
    }

    var range: SourceRange {
        switch self {
        case let .lexerError(error): return error.range
        case let .parserError(error): return error.range
        case let .runtimeError(error): return error.range
        case .unknownError: return "".startIndex ..< "".endIndex
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
            case .unknownSymbol, .unknownMember, .unknownFont, .typeMismatch,
                 .unexpectedArgument, .missingArgument, .unusedValue,
                 .assertionFailure, .fileNotFound, .fileAccessRestricted,
                 .fileTypeMismatch, .fileParsingError:
                return baseURL
            }
        case .lexerError, .parserError, .unknownError:
            return baseURL
        }
    }

    /// Returns the underlying error if the error was triggerred inside an imported file, etc.
    var underlyingError: ProgramError {
        switch self {
        case let .runtimeError(runtimeError):
            switch runtimeError.type {
            case let .importError(error, _, _):
                return error.underlyingError
            case .unknownSymbol, .unknownMember, .unknownFont, .typeMismatch,
                 .unexpectedArgument, .missingArgument, .unusedValue,
                 .assertionFailure, .fileNotFound, .fileAccessRestricted,
                 .fileTypeMismatch, .fileParsingError:
                return self
            }
        case .lexerError, .parserError, .unknownError:
            return self
        }
    }
}

public enum RuntimeErrorType: Error, Equatable {
    case unknownSymbol(String, options: [String])
    case unknownMember(String, of: String, options: [String])
    case unknownFont(String, options: [String])
    case typeMismatch(for: String, index: Int, expected: String, got: String)
    case unexpectedArgument(for: String, max: Int)
    case missingArgument(for: String, index: Int, type: String)
    case unusedValue(type: String)
    case assertionFailure(String)
    case fileNotFound(for: String, at: URL?)
    case fileAccessRestricted(for: String, at: URL)
    case fileTypeMismatch(for: String, at: URL, expected: String?)
    case fileParsingError(for: String, at: URL, message: String)
    indirect case importError(ProgramError, for: URL?, in: String)
}

public struct RuntimeError: Error, Equatable {
    public let type: RuntimeErrorType
    public let range: SourceRange

    public init(_ type: RuntimeErrorType, at range: SourceRange) {
        self.type = type
        self.range = range
    }
}

public extension RuntimeError {
    var message: String {
        switch type {
        case let .unknownSymbol(name, _):
            if Keyword(rawValue: name) == nil, Symbols.all[name] == nil, name != "option" {
                return "Unknown symbol '\(name)'"
            }
            return "Unexpected symbol '\(name)'"
        case let .unknownMember(name, type, _):
            return "Unknown \(type) member property '\(name)'"
        case let .unknownFont(name, _):
            return name.isEmpty ? "Font name cannot be blank" : "Unknown font '\(name)'"
        case .typeMismatch:
            return "Type mismatch"
        case .unexpectedArgument:
            return "Unexpected argument"
        case .missingArgument:
            return "Missing argument"
        case .unusedValue:
            return "Unused value"
        case .assertionFailure:
            return "Assertion failure"
        case let .fileNotFound(for: name, _):
            guard !name.isEmpty else {
                return "Empty file name"
            }
            return "File '\(name)' not found"
        case let .fileAccessRestricted(for: name, _):
            return "Unable to access file '\(name)'"
        case let .fileParsingError(for: name, _, _),
             let .fileTypeMismatch(for: name, _, _):
            return "Unable to open file '\(name)'"
        case let .importError(error, for: url, _):
            if case let .runtimeError(error) = error, case .importError = error.type {
                return error.message
            }
            let name = url.map { " '\($0.lastPathComponent)'" } ?? ""
            return "Error in imported file\(name): \(error.message)"
        }
    }

    var suggestion: String? {
        switch type {
        case let .unknownSymbol(name, options), let .unknownMember(name, _, options):
            return Self.alternatives[name.lowercased()]?
                .first(where: { options.contains($0) || Keyword(rawValue: $0) != nil })
                ?? name.bestMatches(in: options).first
        case let .unknownFont(name, options):
            return name.bestMatches(in: options).first
        case .typeMismatch,
             .unexpectedArgument,
             .missingArgument,
             .unusedValue,
             .assertionFailure,
             .fileNotFound,
             .fileAccessRestricted,
             .fileTypeMismatch,
             .fileParsingError,
             .importError:
            return nil
        }
    }

    var hint: String? {
        func nth(_ index: Int) -> String {
            switch index {
            case 1 ..< String.ordinals.count:
                return "\(String.ordinals[index]) "
            default:
                return ""
            }
        }
        func formatMessage(_ message: String) -> String? {
            guard let last = message.last else {
                return nil
            }
            if ".?!".contains(last) {
                return message
            }
            return "\(message)."
        }
        switch type {
        case let .unknownSymbol(name, _):
            var hint = ""
            if let symbol = Symbols.all[name] {
                hint = "The \(name) \(symbol.errorDescription) is not available in this context."
            } else if Keyword(rawValue: name) != nil || name == "option" {
                hint = "The \(name) command is not available in this context."
            }
            if let suggestion = suggestion {
                hint += (hint.isEmpty ? "" : " ") + "Did you mean '\(suggestion)'?"
            }
            return hint
        case .unknownMember:
            return suggestion.map { "Did you mean '\($0)'?" }
        case .unknownFont:
            if let suggestion = suggestion {
                return "Did you mean '\(suggestion)'?"
            }
            return ""
        case let .typeMismatch(for: name, index: index, expected: type, got: got):
            if got == "block" {
                return "The \(name) function does not expect a block argument."
            }
            let got = got.contains(",") ? got : "a \(got)"
            return "The \(nth(index))argument for \(name) should be a \(type), not \(got)."
        case let .unexpectedArgument(for: name, max: max):
            let hint: String
            if name.isEmpty {
                hint = "Function"
            } else if let symbol = Symbols.all[name] {
                hint = "The \(name) \(symbol.errorDescription)"
            } else {
                hint = "The \(name) function"
            }
            if max == 0 {
                return "\(hint) does not expect any arguments."
            } else if max == 1 {
                return "\(hint) expects only a single argument."
            } else {
                return "\(hint) expects a maximum of \(max) arguments."
            }
        case let .missingArgument(for: name, index: index, type: type):
            let hint: String
            if name.isEmpty {
                hint = "Function"
            } else if let symbol = Symbols.all[name] {
                hint = "The \(name) \(symbol.errorDescription)"
            } else {
                hint = "The \(name) function"
            }
            let type = (type == ValueType.any.errorDescription) ? "" : " of type \(type)"
            if index == 0 {
                return "\(hint) expects an argument\(type)."
            } else {
                return "\(hint) expects a \(nth(index))argument\(type)."
            }
        case let .unusedValue(type: type):
            return "A \(type) value was not expected in this context."
        case let .assertionFailure(message):
            return formatMessage(message)
        case let .fileNotFound(for: name, at: url):
            guard let url = url else {
                return nil
            }
            if name == url.path {
                return "Check that the file exists and is located here."
            }
            return "ShapeScript expected to find the file at '\(url.path)'."
                + " Check that it exists and is located here."
        case let .fileAccessRestricted(for: _, at: url):
            return "ShapeScript cannot read the file due to \(Self.osName) security restrictions."
                + " Please open the directory at '\(url.path)' to grant access."
        case let .fileParsingError(for: _, at: _, message: message):
            return formatMessage(message)
        case let .fileTypeMismatch(for: _, at: url, expected: type):
            guard let type = type else {
                return "The type of file at '\(url.path)' is not supported."
            }
            return "The file at '\(url.path)' is not a \(type) file."
        case let .importError(error, for: _, in: _):
            return error.hint
        }
    }

    var accessErrorURL: URL? {
        switch type {
        case let .fileAccessRestricted(for: _, at: url):
            return url
        case let .importError(error, _, _):
            return error.accessErrorURL
        case .typeMismatch,
             .unexpectedArgument,
             .missingArgument,
             .unusedValue,
             .assertionFailure,
             .fileNotFound,
             .fileTypeMismatch,
             .fileParsingError,
             .unknownSymbol,
             .unknownMember,
             .unknownFont:
            return nil
        }
    }

    static func wrap<T>(_ fn: @autoclosure () throws -> T, at range: SourceRange) throws -> T {
        do {
            return try fn()
        } catch let error as RuntimeErrorType {
            throw RuntimeError(error, at: range)
        }
    }
}

// MARK: Implementation

private struct EvaluationCancelled: Error {}

private extension Array where Element == String {
    var typesDescription: String {
        var types = Set(self).sorted()
        if let index = types.firstIndex(of: "block") {
            types.append(types.remove(at: index))
        }
        switch types.count {
        case 1:
            return types[0]
        case 2:
            return "\(types[0]) or \(types[1])"
        default:
            return "\(types.dropLast().joined(separator: ", ")), or \(types.last!)"
        }
    }
}

extension RuntimeErrorType {
    static func typeMismatch(
        for symbol: String,
        index: Int,
        expected types: [String],
        got: String
    ) -> RuntimeErrorType {
        let expected = types.typesDescription
        return .typeMismatch(for: symbol, index: index, expected: expected, got: got)
    }

    static func missingArgument(
        for symbol: String,
        index: Int,
        types: [String]
    ) -> RuntimeErrorType {
        let expected = types.typesDescription
        return .missingArgument(for: symbol, index: index, type: expected)
    }

    static func typeMismatch(
        for name: String,
        index: Int,
        expected: ValueType,
        got: ValueType
    ) -> RuntimeErrorType {
        let typeDescription: String
        switch expected {
        case let .list(type):
            typeDescription = type.errorDescription
        case let .tuple(types) where !types.isEmpty:
            typeDescription = types[0].errorDescription
        default:
            typeDescription = expected.errorDescription
        }
        return typeMismatch(
            for: name,
            index: index,
            expected: typeDescription,
            got: got.errorDescription
        )
    }

    static func missingArgument(
        for name: String,
        index: Int,
        type: ValueType
    ) -> RuntimeErrorType {
        let typeDescription: String
        switch type {
        case let .list(type):
            typeDescription = type.errorDescription
        case let .tuple(types) where !types.isEmpty:
            typeDescription = types[0].errorDescription
        default:
            typeDescription = type.errorDescription
        }
        return missingArgument(for: name, index: index, type: typeDescription)
    }

    static func unusedValue(type: ValueType) -> RuntimeErrorType {
        let typeDescription: String
        switch type {
        case let .list(type):
            typeDescription = type.errorDescription
        default:
            typeDescription = type.errorDescription
        }
        return unusedValue(type: typeDescription)
    }
}

private extension RuntimeError {
    static let alternatives = [
        "box": ["cube"],
        "rect": ["square"],
        "rectangle": ["square"],
        "triangle": ["polygon"],
        "ellipse": ["circle"],
        "elipse": ["circle"],
        "squircle": ["roundrect"],
        "rotate": ["orientation"],
        "rotation": ["orientation"],
        "orientation": ["rotate"],
        "translate": ["position"],
        "translation": ["position"],
        "position": ["translate"],
        "scale": ["size"],
        "size": ["scale"],
        "width": ["size", "x"],
        "height": ["size", "y"],
        "depth": ["size", "z"],
        "length": ["size", "count"],
        "radius": ["size"],
        "x": ["width", "position"],
        "y": ["height", "position"],
        "z": ["depth", "position"],
        "option": ["define"],
        "subtract": ["difference"],
        "subtraction": ["difference"],
        "head": ["first"],
        "tail": ["last", "allButFirst"],
        "rest": ["allButFirst"],
    ]

    static let osName: String = {
        #if os(macOS) || targetEnvironment(macCatalyst)
        return "macOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(iOS)
        return "iOS"
        #else
        return "system"
        #endif
    }()
}

extension Program {
    func evaluate(in context: EvaluationContext) throws {
        let oldSource = context.source
        let oldSourceIndex = context.sourceIndex
        context.source = source
        context.sourceIndex = nil
        defer {
            context.source = oldSource
            context.sourceIndex = oldSourceIndex
        }
        do {
            try statements.forEach { try $0.evaluate(in: context) }
        } catch is EvaluationCancelled {}
    }
}

private func evaluateParameters(
    _ parameters: [Expression],
    in context: EvaluationContext
) throws -> [(index: Int, value: Value)] {
    var values = [(Int, Value)]()
    loop: for (i, param) in parameters.enumerated() {
        guard i < parameters.count - 1, case let .identifier(name) = param.type,
              let symbol = context.symbol(for: name)
        else {
            try values.append((i, param.evaluate(in: context)))
            continue
        }
        switch symbol {
        case let .function((parameterType, returnType), fn) where parameterType != .void:
            let identifier = Identifier(name: name, range: param.range)
            let range = parameters[i + 1].range.lowerBound ..< parameters.last!.range.upperBound
            let param = Expression(type: .tuple(Array(parameters[(i + 1)...])), range: range)
            let arg = try evaluateParameter(param, as: parameterType, for: identifier, in: context)
            try RuntimeError.wrap({
                if returnType == .void, Symbols.all[name] != nil {
                    // Commands can't be used in expressions
                    throw RuntimeErrorType.unknownSymbol(name, options: context.expressionSymbols)
                }
                do {
                    switch try fn(arg, context) {
                    case let .tuple(tuple):
                        values += tuple.map { (i, $0) }
                    case let value:
                        values.append((i, value))
                    }
                } catch let RuntimeErrorType.unexpectedArgument(for: "", max: max) {
                    throw RuntimeErrorType.unexpectedArgument(for: name, max: max)
                } catch let RuntimeErrorType.missingArgument(for: "", index: index, type: type) {
                    throw RuntimeErrorType.missingArgument(for: name, index: index, type: type)
                }
            }(), at: range)
            break loop
        case let .block(type, fn) where type.childTypes != .void:
            let parameters = Array(parameters[(i + 1)...])
            let childContext = context.push(type)
            childContext.userSymbols.removeAll()
            let identifier = Identifier(name: name, range: param.range)
            try evaluateBlockParameters(
                parameters, for: identifier,
                type: type, in: context, childContext
            )
            try RuntimeError.wrap(values.append((i, fn(childContext))), at: param.range)
            break loop
        case .function, .block, .property, .constant, .placeholder:
            try values.append((i, param.evaluate(in: context)))
        }
    }
    return values
}

private func evaluateBlockParameters(
    _ parameters: [Expression],
    for identifier: Identifier,
    type: BlockType,
    in context: EvaluationContext,
    _ childContext: EvaluationContext
) throws {
    guard let first = parameters.first, let last = parameters.last else {
        return
    }
    let range = first.range.lowerBound ..< last.range.upperBound
    let children: [(Int, Value)]
    if type.childTypes.subtypes.contains(.text) {
        let param = Expression(type: .tuple(parameters), range: range)
        do {
            children = try [(0, param.evaluate(as: .text, for: identifier.name, in: context))]
        } catch {
            children = try evaluateParameters(parameters, in: context)
        }
    } else {
        children = try evaluateParameters(parameters, in: context)
    }
    for (j, child) in children {
        do {
            try childContext.addValue(child)
        } catch {
            var types = type.childTypes.subtypes.map { $0.errorDescription }
            if j == 0 {
                types.append("block")
            }
            throw RuntimeError(
                .typeMismatch(
                    for: identifier.name,
                    index: j,
                    expected: types,
                    got: child.type.errorDescription
                ),
                at: j < parameters.count ? parameters[j].range : range
            )
        }
    }
}

// TODO: find a better way to encapsulate this
private func evaluateParameter(_ parameter: Expression?,
                               as type: ValueType,
                               for identifier: Identifier,
                               in context: EvaluationContext) throws -> Value
{
    let (name, range) = (identifier.name, identifier.range)
    guard let parameter = parameter else {
        if type == .void {
            return .void
        }
        throw RuntimeError(
            .missingArgument(for: name, index: 0, type: type),
            at: range.upperBound ..< range.upperBound
        )
    }
    return try parameter.evaluate(as: type, for: identifier.name, in: context)
}

extension Definition {
    func evaluate(in context: EvaluationContext) throws -> Symbol {
        switch type {
        case let .expression(expression):
            let context = context.pushDefinition()
            let value = try expression.evaluate(in: context)
            switch value {
            case .tuple:
                return .constant(value)
            default:
                // Wrap all definitions as a single-value tuple
                // so that ordinal access and looping will work
                return .constant(.tuple([value]))
            }
        case let .function(names, block):
            let declarationContext = context
            let returnType: ValueType
            var params = Dictionary(uniqueKeysWithValues: names.map {
                ($0.name, ValueType.any)
            })
            do {
                let context = context.push(.custom(.all, [:], .any, .any))
                block.inferTypes(for: &params, in: context)
                for (name, type) in params {
                    context.define(name, as: .placeholder(type))
                }
                returnType = try block.staticType(in: context)
            }
            let paramTypes = names.map { params[$0.name] ?? .any }
            return .function(.tuple(paramTypes), returnType) { value, context in
                do {
                    let oldChildren = context.children
                    let oldChildTypes = context.childTypes
                    let oldSymbols = context.userSymbols
                    let oldSource = context.source
                    let oldBaseURL = context.baseURL
                    context.children = []
                    context.childTypes = .any
                    context.source = declarationContext.source
                    context.baseURL = declarationContext.baseURL
                    context.userSymbols = declarationContext.userSymbols
                    context.stackDepth += 1
                    defer {
                        context.children = oldChildren
                        context.childTypes = oldChildTypes
                        context.source = oldSource
                        context.baseURL = oldBaseURL
                        context.userSymbols = oldSymbols
                        context.stackDepth -= 1
                    }
                    if context.stackDepth > 25 {
                        throw RuntimeErrorType.assertionFailure("Too much recursion")
                    }
                    let values: [Value]
                    if case let .tuple(_values) = value {
                        values = _values
                    } else {
                        values = [value]
                    }
                    assert(values.count == names.count)
                    for (identifier, value) in zip(names, values) {
                        context.define(identifier.name, as: .constant(value))
                    }
                    try block.evaluate(in: context)
                    if context.children.count == 1 {
                        return context.children[0]
                    }
                    return .tuple(context.children)
                } catch {
                    if declarationContext.baseURL == context.baseURL {
                        throw error
                    }
                    throw RuntimeErrorType.importError(
                        ProgramError(error),
                        for: declarationContext.baseURL,
                        in: declarationContext.source
                    )
                }
            }
        case let .block(block):
            var options: Options? = [:]
            let returnType: ValueType
            do {
                let context = context.push(.custom(.definition, [:], .void, .any))
                returnType = try block.staticType(in: context, options: &options)
            } catch var error as RuntimeError {
                if case let .unknownSymbol(name, options: options) = error.type {
                    // TODO: find a less hacky way to limit the scope of option keyword
                    error = RuntimeError(
                        .unknownSymbol(name, options: options + ["option"]),
                        at: error.range
                    )
                }
                throw error
            }
            let source = context.source
            let sourceIndex = context.sourceIndex
            let baseURL = context.baseURL
            return .block(.custom(.user, options ?? [:], .void, returnType)) { _context in
                do {
                    let context = context.pushDefinition()
                    context.stackDepth = _context.stackDepth + 1
                    if context.stackDepth > 25 {
                        throw RuntimeErrorType.assertionFailure("Too much recursion")
                    }
                    for (name, symbol) in _context.userSymbols {
                        context.define(name, as: symbol)
                    }
                    context.children += _context.children
                    context.name = _context.name
                    context.material = _context.material
                    context.font = _context.font
                    context.transform = _context.transform
                    context.opacity = _context.opacity
                    context.detail = _context.detail
                    context.smoothing = _context.smoothing
                    context.baseURL = baseURL
                    context.source = source
                    context.sourceIndex = sourceIndex
                    for statement in block.statements {
                        if case let .option(identifier, expression) = statement.type {
                            if context.symbol(for: identifier.name) == nil {
                                context.define(
                                    identifier.name,
                                    as: .constant(try expression.evaluate(in: context))
                                )
                            }
                        } else {
                            try statement.evaluate(in: context)
                        }
                    }
                    let children = context.children
                    if children.count == 1, let value = children.first {
                        switch value {
                        case let .path(path):
                            guard context.name.isEmpty else {
                                return .mesh(Geometry(
                                    type: .path(path),
                                    name: context.name,
                                    transform: context.transform,
                                    material: .default,
                                    smoothing: nil,
                                    children: [],
                                    sourceLocation: context.sourceLocation
                                ))
                            }
                            return .path(path.transformed(by: context.transform))
                        case let .mesh(geometry):
                            return .mesh(Geometry(
                                type: geometry.type,
                                name: context.name,
                                transform: geometry.transform * context.transform,
                                material: geometry.material,
                                smoothing: geometry.smoothing,
                                children: geometry.children,
                                sourceLocation: context.sourceLocation,
                                debug: geometry.debug
                            ))
                        default:
                            if context.name.isEmpty {
                                return value
                            }
                            throw RuntimeErrorType.assertionFailure(
                                "Blocks that return a \(value.type.errorDescription) " +
                                    "value cannot be assigned a name"
                            )
                        }
                    } else if context.name.isEmpty,
                              // Manage backwards compatibility for blocks that return
                              // multiple meshes to be used inside difference block
                              !children.contains(where: { $0.type == .mesh }) ||
                              children.contains(where: { ![.mesh, .path].contains($0.type) })
                    {
                        return .tuple(children.map {
                            switch $0 {
                            case let .path(path):
                                return .path(path.transformed(by: context.transform))
                            case let .mesh(geometry):
                                return .mesh(geometry.transformed(by: context.transform))
                            default:
                                return $0
                            }
                        })
                    }
                    return .mesh(Geometry(
                        type: .group,
                        name: context.name,
                        transform: context.transform,
                        material: .default,
                        smoothing: context.smoothing,
                        children: try children.map {
                            switch $0 {
                            case let .path(path):
                                return Geometry(
                                    type: .path(path),
                                    name: nil,
                                    transform: .identity,
                                    material: .default,
                                    smoothing: nil,
                                    children: [],
                                    sourceLocation: context.sourceLocation
                                )
                            case let .mesh(geometry):
                                return geometry
                            default:
                                throw RuntimeErrorType.assertionFailure(
                                    "Blocks that return a \($0.type.errorDescription) " +
                                        "value cannot be assigned a name"
                                )
                            }
                        },
                        sourceLocation: context.sourceLocation
                    ))
                } catch var error {
                    if let e = error as? RuntimeError,
                       case let .unknownSymbol(name, options: options) = e.type
                    {
                        // TODO: find a less hacky way to limit the scope of option keyword
                        error = RuntimeError(
                            .unknownSymbol(name, options: options + ["option"]),
                            at: e.range
                        )
                    }
                    if baseURL == _context.baseURL {
                        throw error
                    }
                    throw RuntimeErrorType.importError(
                        ProgramError(error),
                        for: baseURL,
                        in: source
                    )
                }
            }
        }
    }
}

extension EvaluationContext {
    func addValue(_ value: Value) throws {
        if let value = try value.as(childTypes, in: self) {
            switch value {
            case let .mesh(m):
                children.append(.mesh(m.transformed(by: childTransform)))
            case let .vector(v):
                children.append(.vector(v.transformed(by: childTransform)))
            case let .point(p):
                children.append(.point(p.transformed(by: childTransform)))
            case let .polygon(p):
                children.append(.polygon(p
                        .transformed(by: childTransform)
                        .with(material: material)
                ))
            case let .path(path):
                children.append(.path(path.transformed(by: childTransform)))
            case _ where childTypes.subtypes.contains(.text):
                children.append(.text(TextValue(
                    string: value.stringValue,
                    font: self.value(for: "font")?.stringValue ?? font,
                    color: material.color,
                    linespacing: self.value(for: "linespacing")?.doubleValue
                )))
            case let .tuple(values) where values.count <= 1:
                children += values
            default:
                children.append(value)
            }
        } else {
            switch value {
            case let .path(path) where childTypes.subtypes.contains(.mesh):
                children.append(.mesh(Geometry(
                    type: .path(path),
                    name: name,
                    transform: childTransform,
                    material: .default, // not used for paths
                    smoothing: nil,
                    children: [],
                    sourceLocation: sourceLocation
                )))
            case let .tuple(values):
                try values.forEach(addValue)
            default:
                throw RuntimeErrorType.unusedValue(type: value.type)
            }
        }
    }
}

extension Block {
    func evaluate(in context: EvaluationContext) throws {
        for statement in statements {
            try statement.evaluate(in: context)
        }
    }
}

extension Statement {
    func evaluate(in context: EvaluationContext) throws {
        let sourceIndex = context.sourceIndex
        context.sourceIndex = range.lowerBound
        defer {
            context.sourceIndex = sourceIndex
        }
        switch type {
        case let .command(identifier, parameter):
            let name = identifier.name
            guard let symbol = context.symbol(for: name) else {
                throw RuntimeError(
                    .unknownSymbol(name, options: context.commandSymbols),
                    at: identifier.range
                )
            }
            switch symbol {
            case let .function((parameterType, _), fn):
                let argument = try evaluateParameter(parameter,
                                                     as: parameterType,
                                                     for: identifier,
                                                     in: context)
                try RuntimeError.wrap(context.addValue(fn(argument, context)), at: range)
            case let .property(type, setter, _):
                let argument = try evaluateParameter(parameter,
                                                     as: type,
                                                     for: identifier,
                                                     in: context)
                try RuntimeError.wrap(setter(argument, context), at: range)
            case let .block(type, fn):
                if let parameter = parameter {
                    let parameters: [Expression]
                    if case let .tuple(expressions) = parameter.type {
                        parameters = expressions
                    } else {
                        parameters = [parameter]
                    }
                    let childContext = context.push(type)
                    childContext.userSymbols.removeAll()
                    try evaluateBlockParameters(
                        parameters, for: identifier, type: type,
                        in: context, childContext
                    )
                    try RuntimeError.wrap(context.addValue(fn(childContext)), at: range)
                } else if type.childTypes != .void {
                    throw RuntimeError(.missingArgument(
                        for: name,
                        index: 0,
                        types: type.childTypes.subtypes.map { $0.errorDescription } + ["block"]
                    ), at: range)
                } else {
                    let childContext = context.push(type)
                    childContext.userSymbols.removeAll()
                    try RuntimeError.wrap(context.addValue(fn(childContext)), at: range)
                }
            case var .constant(v):
                if let parameter = parameter {
                    v = .tuple([v, try parameter.evaluate(in: context)])
                }
                try RuntimeError.wrap(context.addValue(v), at: range)
            case .placeholder:
                assertionFailure()
            }
        case let .expression(expression):
            try RuntimeError.wrap(context.addValue(expression.evaluate(in: context)), at: range)
        case let .define(identifier, definition):
            switch definition.type {
            case let .function(names, _):
                // In case of recursion
                let parameterType: ValueType = names.count == 1 ?
                    .any : .tuple(names.map { _ in .any })
                context.define(identifier.name, as: .function((parameterType, .any)) { _, _ in .void })
            case .block:
                // In case of recursion
                context.define(identifier.name, as: .block(.custom([:], [:], .void, .any)) { _ in .void })
            case .expression:
                break
            }
            context.define(identifier.name, as: try definition.evaluate(in: context))
        case .option:
            throw RuntimeError(.unknownSymbol("option", options: []), at: range)
        case let .forloop(identifier, in: expression, block):
            let value = try expression.evaluate(in: context)
            // TODO: evaluate(as: .sequence, ...) should be enough to make the below check
            // unneccessary, however because <type> can always be cast to .list(<type>)
            // it isn't. Need to find a static solution for this (or abandon this check)
            guard let sequence = value.sequenceValue else {
                throw RuntimeError(
                    .typeMismatch(
                        for: "range",
                        index: 0,
                        expected: .sequence,
                        got: value.type
                    ),
                    at: expression.range
                )
            }
            for value in sequence {
                if context.isCancelled() {
                    throw EvaluationCancelled()
                }
                try context.pushScope { context in
                    if let name = identifier?.name {
                        context.define(name, as: .constant(value))
                    }
                    try block.evaluate(in: context)
                }
            }
        case let .ifelse(condition, body, else: elseBody):
            let value = try condition.evaluate(
                as: .boolean,
                for: "condition",
                index: 0,
                in: context
            )
            try context.pushScope { context in
                if value.boolValue {
                    try body.evaluate(in: context)
                } else if let elseBody = elseBody {
                    try elseBody.evaluate(in: context)
                }
            }
        case let .import(expression):
            let pathValue = try expression.evaluate(
                as: .string,
                for: Keyword.import.rawValue,
                in: context
            )
            let path = pathValue.stringValue
            context.sourceIndex = expression.range.lowerBound
            try RuntimeError.wrap(context.importFile(at: path), at: expression.range)
        }
    }
}

extension Expression {
    func evaluate(in context: EvaluationContext) throws -> Value {
        switch type {
        case let .number(number):
            return .number(number)
        case let .string(string):
            return .string(string)
        case let .color(color):
            return .color(color)
        case let .identifier(name):
            guard let symbol = context.symbol(for: name) else {
                throw RuntimeError(
                    .unknownSymbol(name, options: context.expressionSymbols),
                    at: range
                )
            }
            switch symbol {
            case .function((.void, .void), _) where Symbols.all[name] != nil:
                // Commands can't be used in expressions
                throw RuntimeError(
                    .unknownSymbol(name, options: context.expressionSymbols),
                    at: range
                )
            case let .function((.void, _), fn):
                return try RuntimeError.wrap(fn(.void, context), at: range)
            case let .function((parameterType, _), _):
                // Functions with parameters can't be called without arguments
                throw RuntimeError(.missingArgument(
                    for: name,
                    index: 0,
                    type: parameterType
                ), at: range.upperBound ..< range.upperBound)
            case let .property(_, _, getter):
                return try RuntimeError.wrap(getter(context), at: range)
            case let .block(type, fn):
                guard type.childTypes.isOptional else {
                    // Blocks that require children can't be called without arguments
                    throw RuntimeError(.missingArgument(
                        for: name,
                        index: 0,
                        types: type.childTypes.subtypes.map { $0.errorDescription } + ["block"]
                    ), at: range.upperBound ..< range.upperBound)
                }
                return try RuntimeError.wrap(fn(context.push(type)), at: range)
            case let .constant(value):
                return value
            case .placeholder:
                assertionFailure()
                return .void
            }
        case let .block(identifier, block):
            let (name, range) = (identifier.name, identifier.range)
            guard let symbol = context.symbol(for: name) else {
                throw RuntimeError(.unknownSymbol(name, options: context.expressionSymbols), at: range)
            }
            switch symbol {
            case let .block(type, fn):
                if context.isCancelled() {
                    throw EvaluationCancelled()
                }
                let sourceIndex = context.sourceIndex
                let context = context.push(type)
                for statement in block.statements {
                    switch statement.type {
                    case let .command(identifier, parameter):
                        var name = identifier.name
                        guard let type = type.options[name] ?? {
                            switch name {
                            case "colour":
                                name = "color"
                                return type.options[name]
                            default:
                                return nil
                            }
                        }() else {
                            fallthrough
                        }
                        context.define(name, as: try .constant(
                            evaluateParameter(parameter,
                                              as: type,
                                              for: identifier,
                                              in: context)
                        ))
                    case .define, .forloop, .ifelse, .expression, .import:
                        try statement.evaluate(in: context)
                    case .option:
                        throw RuntimeError(.unknownSymbol("option", options: []), at: statement.range)
                    }
                }
                context.sourceIndex = sourceIndex
                return try RuntimeError.wrap(fn(context), at: range)
            case .property, .constant, .placeholder, .function((.void, _), _):
                throw RuntimeError(
                    .unexpectedArgument(for: name, max: 0),
                    at: block.range
                )
            case let .function((type, _), _):
                throw RuntimeError(.typeMismatch(
                    for: name,
                    index: 0,
                    expected: type.errorDescription,
                    got: "block"
                ), at: block.range)
            }
        case let .tuple(expressions):
            return try .tuple(evaluateParameters(expressions, in: context).map { $0.value })
        case let .prefix(op, expression):
            let value = try expression.evaluate(as: .number, for: String(op.rawValue), index: 0, in: context)
            switch op {
            case .minus:
                return .number(-value.doubleValue)
            case .plus:
                return .number(value.doubleValue)
            }
        case let .infix(lhs, .to, rhs):
            let start = try lhs.evaluate(as: .number, for: "start value", in: context)
            let end = try rhs.evaluate(as: .number, for: "end value", in: context)
            return .range(RangeValue(from: start.doubleValue, to: end.doubleValue))
        case let .infix(lhs, .step, rhs):
            let rangeValue = try lhs.evaluate(as: .range, for: "range value", in: context)
            let stepValue = try rhs.evaluate(as: .number, for: "step value", in: context)
            let range = rangeValue.value as! RangeValue
            guard let value = RangeValue(
                from: range.start,
                to: range.end,
                step: stepValue.doubleValue
            ) else {
                throw RuntimeError(
                    .assertionFailure("Step value must be nonzero"),
                    at: rhs.range
                )
            }
            return .range(value)
        case let .infix(lhs, .equal, rhs):
            let lhs = try lhs.evaluate(in: context)
            let rhs = try rhs.evaluate(in: context)
            return .boolean(lhs.value == rhs.value)
        case let .infix(lhs, .unequal, rhs):
            let lhs = try lhs.evaluate(in: context)
            let rhs = try rhs.evaluate(in: context)
            return .boolean(lhs.value != rhs.value)
        case let .infix(lhs, .and, rhs):
            return try .boolean(lhs.evaluate(
                as: .boolean,
                for: InfixOperator.and.rawValue,
                index: 0,
                in: context
            ).boolValue && rhs.evaluate(
                as: .boolean,
                for: InfixOperator.and.rawValue,
                index: 1,
                in: context
            ).boolValue)
        case let .infix(lhs, .or, rhs):
            return try .boolean(lhs.evaluate(
                as: .boolean,
                for: InfixOperator.or.rawValue,
                index: 0,
                in: context
            ).boolValue || rhs.evaluate(
                as: .boolean,
                for: InfixOperator.or.rawValue,
                index: 1,
                in: context
            ).boolValue)
        case let .infix(lhs, op, rhs):
            let lhs = try lhs.evaluate(as: .number, for: String(op.rawValue), index: 0, in: context)
            let rhs = try rhs.evaluate(as: .number, for: String(op.rawValue), index: 1, in: context)
            switch op {
            case .minus:
                return .number(lhs.doubleValue - rhs.doubleValue)
            case .plus:
                return .number(lhs.doubleValue + rhs.doubleValue)
            case .times:
                return .number(lhs.doubleValue * rhs.doubleValue)
            case .divide:
                return .number(lhs.doubleValue / rhs.doubleValue)
            case .lt:
                return .boolean(lhs.doubleValue < rhs.doubleValue)
            case .gt:
                return .boolean(lhs.doubleValue > rhs.doubleValue)
            case .lte:
                return .boolean(lhs.doubleValue <= rhs.doubleValue)
            case .gte:
                return .boolean(lhs.doubleValue >= rhs.doubleValue)
            case .to, .step, .equal, .unequal, .and, .or:
                throw RuntimeErrorType
                    .assertionFailure("\(op.rawValue) should be handled by earlier case")
            }
        case let .member(expression, member):
            var value = try expression.evaluate(in: context)
            if let memberValue = value[member.name] {
                assert(value.members.contains(member.name),
                       "\(value.type.errorDescription) does not have member '\(member.name)'")
                return memberValue
            }
            // TODO: find less hacky way to do this unwrap
            if case let .tuple(values) = value, values.count == 1 {
                value = values[0]
            }
            throw RuntimeError(.unknownMember(
                member.name,
                of: value.type.errorDescription,
                options: value.members
            ), at: member.range)
        }
    }

    func evaluate(as type: ValueType, for name: String, index: Int = 0, in context: EvaluationContext) throws -> Value {
        let value: Value, values: [(index: Int, value: Value)]
        do {
            if case let .tuple(expressions) = self.type {
                values = try evaluateParameters(expressions, in: context)
                if case let .tuple(types) = type, types.count == values.count {
                    return try .tuple(zip(values, types).map {
                        do {
                            if let value = try $0.value.as($1, in: context) {
                                return value
                            }
                            throw RuntimeErrorType.typeMismatch(
                                for: name,
                                index: $0.index,
                                expected: $1,
                                got: $0.value.type
                            )
                        } catch let error as RuntimeErrorType {
                            throw RuntimeError(error, at: expressions[$0.index].range)
                        }
                    })
                }
                value = .tuple(values.map { $0.value })
            } else {
                value = try evaluate(in: context)
                values = []
            }
        } catch var error as RuntimeError {
            if case .unknownSymbol(let name, var options) = error.type {
                options += InfixOperator.allCases.map { $0.rawValue }
                error = RuntimeError(.unknownSymbol(name, options: options), at: error.range)
            }
            throw error
        }
        if let value = try RuntimeError.wrap(value.as(type, in: context), at: range) {
            return value
        }
        switch (self.type, type) {
        case let (.tuple(expressions), .tuple(types)):
            if values.count > types.count {
                throw RuntimeError(.unexpectedArgument(
                    for: name,
                    max: types.count
                ), at: expressions[values[types.count].index].range)
            }
            let upperBound = expressions.last?.range.upperBound ?? range.upperBound
            throw RuntimeError(.missingArgument(
                for: name,
                index: values.count,
                type: types[values.count]
            ), at: upperBound ..< upperBound)
        case let (.tuple(expressions), .list(type)):
            return try .tuple(expressions.enumerated().map {
                try $1.evaluate(as: type, for: name, index: $0, in: context)
            })
        case let (.tuple(expressions), _) where expressions.count == 1:
            return try expressions[0].evaluate(as: type, for: name, in: context)
        case let (.tuple(expressions), type) where
            ValueType.color.isSubtype(of: type) && expressions.count > 4:
            throw RuntimeError(
                .unexpectedArgument(for: name, max: 4),
                at: expressions[4].range
            )
        case let (.tuple(expressions), type) where
            (ValueType.vector.isSubtype(of: type) ||
                ValueType.size.isSubtype(of: type) ||
                ValueType.rotation.isSubtype(of: type)) && expressions.count > 3:
            throw RuntimeError(
                .unexpectedArgument(for: name, max: 3),
                at: expressions[3].range
            )
        case let (.tuple(expressions), type) where expressions.count > 1:
            var value = value
            if InfixOperator(rawValue: name) == nil,
               PrefixOperator(rawValue: name) == nil
            {
                value = try expressions[0].evaluate(in: context)
                if value.isConvertible(to: type) {
                    throw RuntimeError(
                        .unexpectedArgument(for: name, max: 1),
                        at: expressions[1].range
                    )
                }
            }
            throw RuntimeError(.typeMismatch(
                for: name,
                index: index,
                expected: type,
                got: value.type
            ), at: range)
        case let (_, .tuple(types)) where types.count > 1:
            throw RuntimeError(
                .missingArgument(for: name, index: 1, type: types[1]),
                at: range.upperBound ..< range.upperBound
            )
        case (_, .void):
            throw RuntimeError(.unexpectedArgument(for: name, max: 0), at: range)
        default:
            throw RuntimeError(.typeMismatch(
                for: name,
                index: index,
                expected: type,
                got: value.type
            ), at: range)
        }
    }
}
