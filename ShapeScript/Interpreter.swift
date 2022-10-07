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

public let version = "1.5.9"

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

    /// If the error was related to a file import, return the URL of that file.
    var fileURL: URL? {
        switch underlyingError {
        case let .runtimeError(runtimeError):
            switch runtimeError.type {
            case let .fileAccessRestricted(for: _, at: url),
                 let .fileTypeMismatch(for: _, at: url, expected: _),
                 let .fileParsingError(for: _, at: url, message: _):
                return url
            case let .fileNotFound(for: _, at: url):
                return url
            case .unknownSymbol, .unknownMember, .unknownFont, .typeMismatch,
                 .unexpectedArgument, .missingArgument, .unusedValue,
                 .assertionFailure, .importError:
                return nil
            }
        case .parserError, .lexerError, .unknownError:
            return nil
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

    /// Returns true is the error was a file permission error (allowing these to be handled differently in the UI).
    var isPermissionError: Bool {
        switch underlyingError {
        case let .runtimeError(runtimeError):
            switch runtimeError.type {
            case .fileAccessRestricted:
                return true
            case .unknownSymbol, .unknownMember, .unknownFont, .typeMismatch,
                 .unexpectedArgument, .missingArgument, .unusedValue,
                 .assertionFailure, .fileNotFound, .importError,
                 .fileTypeMismatch, .fileParsingError:
                return false
            }
        case .parserError, .lexerError, .unknownError:
            return false
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
    indirect case importError(ProgramError, for: String, in: String)
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
        case let .importError(error, for: name, _):
            if case let .runtimeError(error) = error, case .importError = error.type {
                return error.message
            }
            return "Error in imported file '\(name)': \(error.message)"
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
            let got = got.contains(",") ? got : "a \(got)"
            return "The \(nth(index))argument for \(name) should be a \(type), not \(got)."
        case let .unexpectedArgument(for: name, max: max):
            let name = name.isEmpty ? "Function" : "The \(name) function"
            if max == 0 {
                return "\(name) does not expect any arguments."
            } else if max == 1 {
                return "\(name) expects only a single argument."
            } else {
                return "\(name) expects a maximum of \(max) arguments."
            }
        case let .missingArgument(for: name, index: index, type: type):
            var type = type
            switch type {
            case ValueType.pair.errorDescription:
                type = ValueType.number.errorDescription
            case ValueType.tuple.errorDescription:
                type = ""
            default:
                break
            }
            type = type.isEmpty ? "" : " of type \(type)"
            let name = name.isEmpty ? "Function" : "The \(name) function"
            if index == 0 {
                return "\(name) expects an argument\(type)."
            } else {
                return "\(name) expects a \(nth(index))argument\(type)."
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
        case .pair:
            typeDescription = ValueType.number.errorDescription
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
        case .pair:
            typeDescription = ValueType.number.errorDescription
        default:
            typeDescription = type.errorDescription
        }
        return missingArgument(for: name, index: index, type: typeDescription)
    }

    static func unusedValue(type: ValueType) -> RuntimeErrorType {
        let typeDescription: String
        switch type {
        case .pair:
            typeDescription = ValueType.number.errorDescription
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
        "length": ["size"],
        "radius": ["size"],
        "x": ["width", "position"],
        "y": ["height", "position"],
        "z": ["depth", "position"],
        "option": ["define"],
        "subtract": ["difference"],
        "subtraction": ["difference"],
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
        context.source = source
        defer { context.source = oldSource }
        do {
            try statements.forEach { try $0.evaluate(in: context) }
        } catch is EvaluationCancelled {}
    }
}

private func evaluateParameters(
    _ parameters: [Expression],
    in context: EvaluationContext
) throws -> [Value] {
    var values = [Value]()
    loop: for (i, param) in parameters.enumerated() {
        guard i < parameters.count - 1, case let .identifier(name) = param.type,
              let symbol = context.symbol(for: name)
        else {
            try values.append(param.evaluate(in: context))
            continue
        }
        switch symbol {
        case let .function(parameterType, fn) where parameterType != .void:
            let identifier = Identifier(name: name, range: param.range)
            let range = parameters[i + 1].range.lowerBound ..< parameters.last!.range.upperBound
            let param = Expression(type: .tuple(Array(parameters[(i + 1)...])), range: range)
            let arg = try evaluateParameter(param, as: parameterType, for: identifier, in: context)
            try RuntimeError.wrap({
                do {
                    switch try fn(arg, context) {
                    case let .tuple(tuple):
                        values += tuple
                    case let value:
                        values.append(value)
                    }
                } catch let RuntimeErrorType.unexpectedArgument(for: "", max: max) {
                    throw RuntimeErrorType.unexpectedArgument(for: name, max: max)
                } catch let RuntimeErrorType.missingArgument(for: "", index: index, type: type) {
                    throw RuntimeErrorType.missingArgument(for: name, index: index, type: type)
                }
            }(), at: range)
            break loop
        case let .block(type, fn) where !type.childTypes.isEmpty:
            let parameters = Array(parameters[(i + 1)...])
            let childContext = context.push(type)
            childContext.userSymbols.removeAll()
            let identifier = Identifier(name: name, range: param.range)
            try evaluateBlockParameters(
                parameters, for: identifier,
                type: type, in: context, childContext
            )
            try RuntimeError.wrap(values.append(fn(childContext)), at: param.range)
            break loop
        case .command, .function, .block, .property, .constant:
            try values.append(param.evaluate(in: context))
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
    let range = parameters[0].range.lowerBound ..< parameters.last!.range.upperBound
    let children: [Value]
    if type.childTypes.contains(.text) {
        let param = Expression(type: .tuple(parameters), range: range)
        do {
            children = try [param.evaluate(as: .text, for: identifier.name, in: context)]
        } catch {
            children = try evaluateParameters(parameters, in: context)
        }
    } else {
        children = try evaluateParameters(parameters, in: context)
    }
    for (j, child) in children.enumerated() {
        do {
            try childContext.addValue(child)
        } catch {
            var types = type.childTypes.map { $0.errorDescription }
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
            return .function(names.isEmpty ? .void : .tuple) { value, context in
                do {
                    let oldChildren = context.children
                    let oldChildTypes = context.childTypes
                    let oldSymbols = context.userSymbols
                    let oldSource = context.source
                    let oldBaseURL = context.baseURL
                    context.children = []
                    context.childTypes = ValueType.any
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
                    guard values.count == names.count else {
                        if values.count < names.count {
                            throw RuntimeErrorType
                                .missingArgument(for: "", index: values.count, type: "")
                        }
                        throw RuntimeErrorType
                            .unexpectedArgument(for: "", max: names.count)
                    }
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
                        for: declarationContext.baseURL?.lastPathComponent ?? "",
                        in: declarationContext.source
                    )
                }
            }
        case let .block(block):
            var options = Options()
            do {
                let context = context.push(.custom(.user, [:]))
                context.random = RandomSequence(seed: context.random.seed)
                for statement in block.statements {
                    switch statement.type {
                    case let .option(identifier, expression):
                        let value = try expression.evaluate(in: context)
                        options[identifier.name] = value.type
                        context.define(identifier.name, as: .constant(value))
                    case .define:
                        try statement.evaluate(in: context)
                    case .command, .forloop, .ifelse, .expression, .import:
                        break
                    }
                }
            }
            let source = context.source
            let baseURL = context.baseURL
            return .block(.custom(.user, options)) { _context in
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
                        for: baseURL?.lastPathComponent ?? "",
                        in: source
                    )
                }
            }
        }
    }
}

extension EvaluationContext {
    func addValue(_ value: Value) throws {
        switch value {
        case _ where childTypes.contains { value.isConvertible(to: $0) }:
            switch value {
            case let .mesh(m):
                children.append(.mesh(m.transformed(by: childTransform)))
            case let .vector(v):
                children.append(.vector(v.transformed(by: childTransform)))
            case let .point(v):
                children.append(.point(v.transformed(by: childTransform)))
            case let .path(path):
                children.append(.path(path.transformed(by: childTransform)))
            case _ where !childTypes.contains(value.type) && childTypes.contains(.text):
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
        case let .path(path) where childTypes.contains(.mesh):
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
            case let .command(type, fn):
                let argument = try evaluateParameter(parameter,
                                                     as: type,
                                                     for: identifier,
                                                     in: context)
                try RuntimeError.wrap(fn(argument, context), at: range)
            case let .function(type, fn):
                let argument = try evaluateParameter(parameter,
                                                     as: type,
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
                } else if !type.childTypes.isEmpty {
                    throw RuntimeError(.missingArgument(
                        for: name,
                        index: 0,
                        types: type.childTypes.map { $0.errorDescription } + ["block"]
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
            }
        case let .expression(expression):
            try RuntimeError.wrap(context.addValue(expression.evaluate(in: context)), at: range)
        case let .define(identifier, definition):
            context.define(identifier.name, as: try definition.evaluate(in: context))
        case .option:
            throw RuntimeError(.unknownSymbol("option", options: []), at: range)
        case let .forloop(identifier, in: expression, block):
            let value = try expression.evaluate(in: context)
            guard let sequence = value.sequenceValue else {
                throw RuntimeError(
                    .typeMismatch(
                        for: "range",
                        index: 0,
                        expected: ["range", "tuple"],
                        got: value.type.errorDescription
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
            try RuntimeError.wrap(context.importModel(at: path), at: expression.range)
        }
    }
}

extension Expression {
    func staticType(in context: EvaluationContext) throws -> ValueType? {
        switch type {
        case .number:
            return .number
        case .string:
            return .string
        case .color:
            return .color
        case let .identifier(name):
            guard let symbol = context.symbol(for: name) else {
                throw RuntimeError(
                    .unknownSymbol(name, options: context.expressionSymbols),
                    at: range
                )
            }
            switch symbol {
            case .command:
                return .void
            case .function, .block:
                return nil
            case let .property(type, _, _):
                return type
            case let .constant(value):
                return value.type
            }
        case let .block(identifier, block):
            let (name, range) = (identifier.name, identifier.range)
            guard let symbol = context.symbol(for: name) else {
                throw RuntimeError(.unknownSymbol(name, options: context.expressionSymbols), at: range)
            }
            switch symbol {
            case .command:
                return .void
            case .block, .function:
                return nil
            case .property, .constant:
                throw RuntimeError(
                    .unexpectedArgument(for: name, max: 0),
                    at: block.range
                )
            }
        case let .tuple(expressions):
            switch expressions.count {
            case 0:
                return .void
            case 1:
                return try expressions[0].staticType(in: context)
            default:
                guard case let .identifier(name) = expressions[0].type else {
                    return .tuple
                }
                guard let symbol = context.symbol(for: name) else {
                    throw RuntimeError(
                        .unknownSymbol(name, options: context.expressionSymbols),
                        at: range
                    )
                }
                switch symbol {
                case .command:
                    return .void
                case .function, .block:
                    return nil
                case .property, .constant:
                    return .tuple
                }
            }
        case .prefix(.minus, _),
             .prefix(.plus, _),
             .infix(_, .minus, _),
             .infix(_, .plus, _),
             .infix(_, .times, _),
             .infix(_, .divide, _):
            return .number
        case .infix(_, .to, _), .infix(_, .step, _):
            return .range
        case .infix(_, .equal, _),
             .infix(_, .unequal, _),
             .infix(_, .lt, _),
             .infix(_, .gt, _),
             .infix(_, .lte, _),
             .infix(_, .gte, _),
             .infix(_, .and, _),
             .infix(_, .or, _):
            return .boolean
        case .member:
            // TODO: This should be possible to get
            return nil
        case let .subexpression(expression):
            return try expression.staticType(in: context)
        }
    }

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
            case .command:
                // Commands can't be used in expressions
                throw RuntimeError(
                    .unknownSymbol(name, options: context.expressionSymbols),
                    at: range
                )
            case let .function(parameterType, fn):
                guard parameterType == .void else {
                    // Functions with parameters can't be called without arguments
                    throw RuntimeError(.missingArgument(
                        for: name,
                        index: 0,
                        type: parameterType.errorDescription
                    ), at: range.upperBound ..< range.upperBound)
                }
                return try RuntimeError.wrap(fn(.void, context), at: range)
            case let .property(_, _, getter):
                return try RuntimeError.wrap(getter(context), at: range)
            case let .block(type, fn):
                guard type.childTypes.isEmpty else {
                    // Blocks that require children can't be called without arguments
                    throw RuntimeError(.missingArgument(
                        for: name,
                        index: 0,
                        types: type.childTypes.map { $0.errorDescription } + ["block"]
                    ), at: range.upperBound ..< range.upperBound)
                }
                return try RuntimeError.wrap(fn(context.push(type)), at: range)
            case let .constant(value):
                return value
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
            case let .function(type, _), let .command(type, _):
                throw RuntimeError(.typeMismatch(
                    for: name,
                    index: 0,
                    expected: type.errorDescription,
                    got: "block"
                ), at: block.range)
            case .property, .constant:
                throw RuntimeError(
                    .unexpectedArgument(for: name, max: 0),
                    at: block.range
                )
            }
        case let .tuple(expressions):
            return try .tuple(evaluateParameters(expressions, in: context))
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
        case let .subexpression(expression):
            return try expression.evaluate(in: context)
        }
    }

    func evaluate(as type: ValueType, for name: String, index: Int = 0, in context: EvaluationContext) throws -> Value {
        var parameters = [self]
        if case let .tuple(expressions) = self.type {
            parameters = expressions
        }
        func unwrap(_ value: Value) -> Value {
            if case let .tuple(values) = value {
                if values.count == 1 {
                    return unwrap(values[0])
                }
                return .tuple(values.map(unwrap))
            } else {
                return value
            }
        }
        let values: [Value]
        do {
            values = try evaluateParameters(parameters, in: context).map(unwrap)
        } catch var error as RuntimeError {
            if case .unknownSymbol(let name, var options) = error.type {
                options += InfixOperator.allCases.map { $0.rawValue }
                error = RuntimeError(.unknownSymbol(name, options: options), at: error.range)
            }
            throw error
        }
        assert(values.count <= parameters.count)
        func numerify(max: Int, min: Int) throws -> [Double] {
            if parameters.count > max {
                throw RuntimeError(.unexpectedArgument(for: name, max: max), at: parameters[max].range)
            } else if parameters.count < min {
                let upperBound = parameters.last?.range.upperBound ?? range.upperBound
                throw RuntimeError(
                    .missingArgument(for: name, index: min - 1, type: .number),
                    at: upperBound ..< upperBound
                )
            }
            var values = values
            if values.count == 1, case let .tuple(elements) = values[0] {
                if elements.count > max {
                    let range: SourceRange
                    if case let .tuple(expressions) = parameters[0].type {
                        range = expressions[max].range
                    } else {
                        range = parameters[0].range
                    }
                    throw RuntimeError(.unexpectedArgument(for: name, max: max), at: range)
                }
                values = elements
            }
            if values.count > 1, values[0].type == type ||
                ((values[0].value as? [Any])?.allSatisfy { $0 is Double } == true)
            {
                if parameters.count > 1 {
                    throw RuntimeError(
                        .unexpectedArgument(for: name, max: 1),
                        at: parameters[1].range
                    )
                }
                let types = [type.errorDescription] + values.dropFirst().map {
                    $0.type.errorDescription
                }
                throw RuntimeError(.typeMismatch(
                    for: name,
                    index: index,
                    expected: type.errorDescription,
                    got: types.joined(separator: ", ")
                ), at: range)
            }
            var numbers = [Double]()
            for (i, value) in values.enumerated() {
                guard case let .number(number) = value else {
                    // TODO: this seems like a hack - what's the actual solution?
                    let i = Swift.min(parameters.count - 1, i)
                    throw RuntimeError(
                        .typeMismatch(
                            for: name,
                            index: index + i,
                            expected: i == 0 ? type : .number,
                            got: value.type
                        ),
                        at: parameters[i].range
                    )
                }
                numbers.append(number)
            }
            return numbers
        }
        if parameters.isEmpty {
            // TODO: can this actually happen?
            if type != .void {
                throw RuntimeError(.missingArgument(
                    for: name,
                    index: index,
                    type: type
                ), at: range)
            }
            return .void
        }
        if values.count == 1, values[0].type == type {
            return values[0]
        }
        switch type {
        case .color:
            // TODO: find less hacky way to do this unwrap
            if values.count == 1, case let .tuple(values) = values[0],
               values.count == 2, let alpha = values[1].value as? Double
            {
                switch values[0] {
                case let .color(color):
                    return .color(color.withAlpha(alpha))
                case let .tuple(values) where (1 ... 4).contains(values.count) &&
                    values.allSatisfy { $0.value is Double }:
                    let color = Color(unchecked: values.map { $0.doubleValue })
                    return .color(color.withAlpha(alpha))
                default:
                    break
                }
            }
            if values.count == 2, parameters.count == 2 {
                let color = try parameters[0].evaluate(as: .color, for: name, in: context)
                let alpha = try parameters[1].evaluate(as: .number, for: name, in: context)
                return .color(color.colorValue.withAlpha(alpha.doubleValue))
            }
            let numbers = try numerify(max: 4, min: 1)
            return .color(Color(unchecked: numbers))
        case .colorOrTexture:
            if Value.tuple(values).isConvertible(to: .color) {
                return try evaluate(as: .color, for: name, in: context)
            }
            return try evaluate(as: .texture, for: name, in: context)
        case .vector:
            let numbers = try numerify(max: 3, min: 1)
            return .vector(Vector(numbers))
        case .size:
            let numbers = try numerify(max: 3, min: 1)
            return .size(Vector(size: numbers))
        case .rotation:
            let numbers = try numerify(max: 3, min: 1)
            return .rotation(Rotation(unchecked: numbers))
        case .pair:
            let numbers = try numerify(max: 2, min: 2)
            return .tuple(numbers.map { .number($0) })
        case .tuple:
            return .tuple(values)
        case .string where Value.tuple(values).isConvertible(to: .string):
            return .string(Value.tuple(values).stringValue)
        case .text where Value.tuple(values).isConvertible(to: .text):
            return .text(TextValue(
                string: Value.tuple(values).stringValue,
                font: context.value(for: "font")?.stringValue ?? context.font,
                color: context.material.color,
                linespacing: context.value(for: "linespacing")?.doubleValue
            ))
        case .texture where Value.tuple(values).isConvertible(to: .string):
            let name = Value.tuple(values).stringValue
            if name.isEmpty {
                return .texture(nil)
            }
            return try RuntimeError.wrap(.texture(.file(
                name: name, url: try context.resolveURL(for: name)
            )), at: range)
        case .font where Value.tuple(values).isConvertible(to: .string):
            let name = Value.tuple(values).stringValue
            let range = parameters.first!.range.lowerBound ..< parameters.last!.range.upperBound
            return try RuntimeError.wrap(.string(context.resolveFont(name)), at: range)
        case .paths:
            return try .tuple(values.enumerated().flatMap { i, value -> [Value] in
                switch value {
                case .path:
                    return [value]
                case let .tuple(values):
                    guard values.allSatisfy({ $0.type == .path }) else {
                        throw RuntimeError(
                            .typeMismatch(
                                for: name,
                                index: index + i,
                                expected: type,
                                got: value.type
                            ),
                            at: parameters[i].range
                        )
                    }
                    return values
                default:
                    throw RuntimeError(
                        .typeMismatch(
                            for: name,
                            index: index + i,
                            expected: type,
                            got: value.type
                        ),
                        at: parameters[i].range
                    )
                }
            })
        case .boolean, .number, .string, .text, .texture, .font, .path,
             .mesh, .point, .range, .bounds:
            if values.count > 1, parameters.count > 1 {
                throw RuntimeError(
                    .unexpectedArgument(for: name, max: 1),
                    at: parameters[1].range
                )
            }
            let value = values[0]
            if value.type != type {
                throw RuntimeError(
                    .typeMismatch(
                        for: name,
                        index: index,
                        expected: type,
                        got: value.type
                    ),
                    at: range
                )
            }
            // TODO: work out when/why this fallback is needed
            throw RuntimeError(
                .typeMismatch(
                    for: name,
                    index: index,
                    expected: type,
                    got: values[0].type
                ),
                at: parameters[0].range
            )
        case .void:
            if values.isEmpty || values.count == 1 && values[0].isConvertible(to: .void) {
                return .void
            }
            throw RuntimeError(
                .unexpectedArgument(for: name, max: 0),
                at: parameters[0].range
            )
        }
    }
}
