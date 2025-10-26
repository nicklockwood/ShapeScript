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

public let version: String = "1.9.2"

public func evaluate(
    _ program: Program,
    delegate: EvaluationDelegate?,
    cache: GeometryCache? = GeometryCache(),
    isCancelled: @escaping () -> Bool = { false }
) throws -> Scene {
    let (scene, error) = evaluate(
        program,
        delegate: delegate,
        cache: cache,
        isCancelled: isCancelled
    )
    if let error {
        throw error
    }
    return scene
}

@_disfavoredOverload
public func evaluate(
    _ program: Program,
    delegate: EvaluationDelegate?,
    cache: GeometryCache?,
    isCancelled: @escaping () -> Bool
) -> (Scene, Error?) {
    let context = EvaluationContext(
        source: program.source,
        delegate: delegate,
        isCancelled: isCancelled
    )
    let result = Result { try program.evaluate(in: context) }
    let scene = Scene(
        background: context.background ?? .color(.clear),
        children: context.children.compactMap { $0.value as? Geometry },
        cache: cache
    )
    switch result {
    case .success:
        return (scene, nil)
    case let .failure(error):
        return (scene, error)
    }
}

public enum RuntimeErrorType: Error, Equatable {
    case unknownSymbol(String, options: [String])
    case unknownMember(String, of: String, options: [String])
    case invalidIndex(Double, range: Range<Int>)
    case unknownFont(String, options: [String])
    case typeMismatch(for: String, index: Int, expected: String, got: String)
    case forwardReference(String)
    case unexpectedArgument(for: String, max: Int)
    case missingArgument(for: String, index: Int, type: String)
    case unusedValue(type: String)
    case assertionFailure(String)
    case fileNotFound(for: String, at: URL?)
    case fileTimedOut(for: String, at: URL)
    case fileAccessRestricted(for: String, at: URL)
    case fileTypeMismatch(for: String, at: URL, expected: String?)
    case fileParsingError(for: String, at: URL, message: String)
    case circularImport(for: URL)
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
            return "Member '\(name)' not found in \(type)"
        case let .invalidIndex(index, _):
            return "Index \(index.logDescription) out of bounds"
        case let .unknownFont(name, _):
            return name.isEmpty ? "Font name cannot be blank" : "Unknown font '\(name)'"
        case .typeMismatch:
            return "Type mismatch"
        case .forwardReference:
            return "Forward reference"
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
        case let .fileTimedOut(for: name, _):
            return "File '\(name)' timed out"
        case let .fileAccessRestricted(for: name, _):
            return "Unable to access file '\(name)'"
        case let .fileParsingError(for: name, _, _),
             let .fileTypeMismatch(for: name, _, _):
            return "Unable to open file '\(name)'"
        case .circularImport:
            return "Circular import"
        case let .importError(error, for: url, _):
            if case let .runtimeError(error) = error, case .importError = error.type {
                return error.message
            }
            let name = url.map { " '\($0.lastPathComponent)'" } ?? ""
            let error = error.range.map { _ in ": \(error.message)" } ?? ""
            return "Error in imported file\(name)\(error)"
        }
    }

    var suggestion: String? {
        switch type {
        case let .unknownSymbol(name, options), let .unknownMember(name, _, options):
            let alternative = Self.alternatives[name.lowercased()]?
                .first(where: { options.contains($0) || Keyword(rawValue: $0) != nil })
            if Symbols.all[name] != nil {
                return alternative
            }
            let ordinals = !name.isOrdinal && options.contains { $0.isOrdinal } ? String.ordinals : []
            return alternative ?? name.bestMatches(in: options + ordinals).first
        case let .unknownFont(name, options):
            return name.bestMatches(in: options).first
        case .typeMismatch,
             .forwardReference,
             .unexpectedArgument,
             .missingArgument,
             .invalidIndex,
             .unusedValue,
             .assertionFailure,
             .fileNotFound,
             .fileTimedOut,
             .fileAccessRestricted,
             .fileTypeMismatch,
             .fileParsingError,
             .circularImport,
             .importError:
            return nil
        }
    }

    var hint: String? {
        func nthArgument(_ index: Int) -> String {
            switch index {
            case 0 ..< String.ordinals.count:
                return "\(String.ordinals[index]) argument"
            default:
                return "argument"
            }
        }
        func theSymbol(_ name: String) -> String {
            if name.components(separatedBy: " ").count == 2 {
                return "The \(name)"
            } else if name.isEmpty {
                return "Symbol"
            } else if let symbol = Symbols.all[name] {
                return "The '\(name)' \(symbol.errorDescription)"
            }
            return "The '\(name)' symbol"
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
                hint = "The '\(name)' \(symbol.errorDescription) is not available in this context."
            } else if Keyword(rawValue: name) != nil || name == "option" {
                hint = "The '\(name)' command is not available in this context."
            }
            if let suggestion {
                hint += (hint.isEmpty ? "" : " ") + "Did you mean '\(suggestion)'?"
            }
            return hint
        case let .unknownMember(name, of: _, options: options):
            if let index = name.ordinalIndex, index > 0 {
                for i in (0 ..< index).reversed() where options.contains(String.ordinals[i]) {
                    guard String.ordinals(upTo: i).allSatisfy(options.contains) else {
                        break
                    }
                    return "Valid range is 'first' to '\(String.ordinals[i])'."
                }
            }
            return suggestion.map { "Did you mean '\($0)'?" }
        case let .invalidIndex(_, range: range):
            return range.upperBound == 0 ? nil : "Valid range is \(range.lowerBound) to \(range.upperBound - 1)."
        case .unknownFont:
            if let suggestion {
                return "Did you mean '\(suggestion)'?"
            }
            return ""
        case let .typeMismatch(for: name, index: i, expected: type, got: got):
            let description: String
            if InfixOperator(rawValue: name) != nil, (0 ... 1).contains(i) {
                description = "\(i == 0 ? "left" : "right") operand for '\(name)'"
            } else if !["if condition", "loop bounds"].contains(name) {
                description = "\(nthArgument(i)) for '\(name)'"
            } else {
                description = name
            }
            let got = got.contains(",") ? got : aOrAn(got)
            return "The \(description) should be \(aOrAn(type)), not \(got)."
        case let .forwardReference(name):
            return "The symbol '\(name)' was used before it was defined."
        case let .unexpectedArgument(for: name, max: max):
            if max == 0 {
                return "\(theSymbol(name)) does not expect any arguments."
            } else if max == 1 {
                return "\(theSymbol(name)) expects only a single argument."
            } else {
                return "\(theSymbol(name)) expects a maximum of \(max) arguments."
            }
        case let .missingArgument(for: name, index: i, type: type):
            let type = (type == ValueType.any.errorDescription) ? "" : " of type \(type)"
            return "\(theSymbol(name)) expects \(aOrAn(nthArgument(i > 0 ? i : -1)))\(type)."
        case let .unusedValue(type: type):
            return "\(aOrAn(type, capitalized: true)) value was not expected in this context."
        case let .assertionFailure(message):
            return formatMessage(message)
        case let .fileNotFound(for: name, at: url):
            guard let url else {
                return nil
            }
            if name == url.path {
                return "Check that the file exists and is located here."
            }
            return "ShapeScript expected to find the file at '\(url.path)'."
                + " Check that it exists and is located here."
        case let .fileTimedOut(for: _, at: url):
            return "ShapeScript was unable to download the file at '\(url.path)'."
                + " Check your network settings."
        case let .fileAccessRestricted(for: _, at: url):
            return "ShapeScript cannot read the file due to \(Self.osName) security restrictions."
                + " Please open the directory at '\(url.path)' to grant access."
        case let .fileParsingError(for: _, at: _, message: message):
            return formatMessage(message)
        case let .fileTypeMismatch(for: _, at: url, expected: type):
            guard let type else {
                return "The type of file at '\(url.path)' is not supported."
            }
            return "The file at '\(url.path)' is not \(aOrAn(type)) file."
        case .circularImport:
            return "Files cannot import themselves."
        case let .importError(error, for: _, in: _):
            if error.range == nil {
                return error.message
            }
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
             .forwardReference,
             .unexpectedArgument,
             .missingArgument,
             .unusedValue,
             .assertionFailure,
             .fileNotFound,
             .fileTimedOut,
             .fileTypeMismatch,
             .fileParsingError,
             .circularImport,
             .unknownSymbol,
             .unknownMember,
             .invalidIndex,
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

private func aOrAn(_ string: String, capitalized: Bool = false) -> String {
    guard let first = string.first else {
        return capitalized ? "An" : "an"
    }
    let beginsWithVowel = "AEIOUaeiou".contains(first)
    let prefix = beginsWithVowel ? "an" : "a"
    return "\(capitalized ? prefix.capitalized : prefix) \(string)"
}

extension RuntimeErrorType {
    static func typeMismatch(
        for symbol: String,
        expected: String,
        got: String
    ) -> RuntimeErrorType {
        .typeMismatch(for: symbol, index: -1, expected: expected, got: got)
    }

    static func typeMismatch(
        for name: String,
        index: Int = -1,
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
        for symbol: String,
        type: String
    ) -> RuntimeErrorType {
        .missingArgument(for: symbol, index: 0, type: type)
    }

    static func missingArgument(
        for name: String,
        index: Int = 0,
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
        switch type {
        case let .list(type):
            return unusedValue(type: type)
        default:
            return unusedValue(type: type.errorDescription)
        }
    }

    static func unknownMember(_ name: String, of value: Value) -> RuntimeErrorType {
        let value = value.unwrapped(recursive: true)
        assert(
            !value.members.contains(name),
            "\(value.errorDescription) should have member '\(name)'"
        )
        return unknownMember(name, of: value.errorDescription, options: value.members)
    }

    static func fileError(_ error: Error, for path: String, at url: URL) -> RuntimeErrorType {
        var error = error
        while let nsError = error as NSError? {
            if nsError.domain == NSCocoaErrorDomain, nsError.code == 259 {
                // Not a recognized model file format
                break
            }
            var underlyingError: Error?
            #if !os(Linux)
            if #available(macOS 11.3, iOS 14.5, tvOS 14.5, *) {
                underlyingError = nsError.underlyingErrors.first
            }
            #endif
            underlyingError = underlyingError ?? nsError.userInfo[NSUnderlyingErrorKey] as? Error
            if let underlyingError {
                error = underlyingError
            } else {
                break
            }
        }
        return RuntimeErrorType.fileParsingError(
            for: path, at: url, message: error.localizedDescription
        )
    }
}

private extension RuntimeError {
    static let alternatives: [String: [String]] = [
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
        "position": ["translate", "bounds", "center"],
        "faces": ["polygons"],
        "vertices": ["points"],
        "scale": ["size"],
        "size": ["scale", "bounds"],
        "width": ["size", "x"],
        "height": ["size", "y"],
        "depth": ["size", "z"],
        "length": ["size", "count"],
        "magnitude": ["length"],
        "norm": ["length"],
        "radius": ["size"],
        "sine": ["sin"],
        "cosine": ["cos"],
        "x": ["width", "position"],
        "y": ["height", "position"],
        "z": ["depth", "position"],
        "option": ["define"],
        "subtract": ["difference"],
        "subtraction": ["difference"],
        "sweep": ["extrude"],
        "head": ["first"],
        "tail": ["last", "allButFirst"],
        "rest": ["allButFirst"],
        "srand": ["seed"],
        "srnd": ["seed"],
        "rands": ["rnd", "seed"],
        "rand": ["rnd"],
        "random": ["rnd"],
        "noise": ["rnd"],
        "signum": ["sign"],
        "echo": ["print"],
        "default": ["else"],
        "metalness": ["metallicity"],
        "metallicness": ["metallicity"],
        "smoothness": ["roughness"],
        "emission": ["glow"],
        "emissiveness": ["glow"],
        "alpha": ["opacity"],
    ].merging(ParserError.alternatives.mapValues { [$0] }) { $1 }

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
        let oldBaseURL = context.baseURL
        context.source = source
        context.sourceIndex = nil
        context.baseURL = fileURL ?? oldBaseURL
        defer {
            context.source = oldSource
            context.sourceIndex = oldSourceIndex
            context.baseURL = oldBaseURL
        }
        statements.gatherDefinitions(in: context)
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
        case let .function((parameterType, _), fn) where parameterType != .void:
            let identifier = Identifier(name: name, range: param.range)
            let range = parameters[i + 1].range.lowerBound ..< parameters.last!.range.upperBound
            let param = Expression(type: .tuple(Array(parameters[(i + 1)...])), range: range)
            let arg = try evaluateParameter(param, as: parameterType, for: identifier, in: context)
            try RuntimeError.wrap({
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
        case .function, .block, .property, .constant, .option, .placeholder:
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
            throw RuntimeError(
                .typeMismatch(
                    for: identifier.name,
                    index: j > 0 ? j : -1,
                    expected: j == 0 ? type.childTypes.errorDescriptionOrBlock : type.childTypes.errorDescription,
                    got: child.type.errorDescription
                ),
                at: j < parameters.count ? parameters[j].range : range
            )
        }
    }
}

// TODO: find a better way to encapsulate this
private func evaluateParameter(
    _ parameter: Expression?,
    as type: ValueType,
    for identifier: Identifier,
    in context: EvaluationContext
) throws -> Value {
    let (name, range) = (identifier.name, identifier.range)
    guard let parameter else {
        if type.isOptional {
            return .void
        }
        throw RuntimeError(
            .missingArgument(for: name, type: type),
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
            var params = Dictionary(names.map { ($0.name, ValueType.any) }) { $1 }
            do {
                let context = context.push(.init(.all, [:], .any, .any))
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
                    let wasFunctionScope = context.isFunctionScope
                    context.children = []
                    context.childTypes = .any
                    context.source = declarationContext.source
                    context.baseURL = declarationContext.baseURL
                    context.userSymbols = declarationContext.userSymbols
                    context.stackDepth += 1
                    context.isFunctionScope = true
                    defer {
                        context.children = oldChildren
                        context.childTypes = oldChildTypes
                        context.source = oldSource
                        context.baseURL = oldBaseURL
                        context.userSymbols = oldSymbols
                        context.stackDepth -= 1
                        context.isFunctionScope = wasFunctionScope
                    }
                    if context.stackDepth > 25 {
                        throw RuntimeErrorType.assertionFailure("Too much recursion")
                    }
                    let values = [value].flattened(recursive: false)
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
            var options: Options! = [:]
            var childTypes: ValueType = .void
            let returnType: ValueType
            do {
                let context = context.push(.init(.definition, [:], .void, .any))
                returnType = try block.staticType(
                    in: context,
                    options: &options,
                    childTypes: &childTypes
                )
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
            var symbols = Symbols.font // TODO: should this be supported?
            if returnType.contains(where: { $0.isSubtype(of: .union([.mesh, .path, .polygon])) }) {
                symbols.merge(.shape) { $1 }
            }
            if ValueType.mesh.isSubtype(of: childTypes) ||
                ValueType.path.isSubtype(of: childTypes) ||
                ValueType.polygon.isSubtype(of: childTypes) ||
                ValueType.point.isSubtype(of: childTypes)
            {
                symbols.merge(.definition) { $1 }
            }
            return .block(.init(symbols, options, childTypes, returnType)) { _context in
                do {
                    let context = context.pushDefinition()
                    context.stackDepth = _context.stackDepth + 1
                    if context.stackDepth > 48 {
                        throw RuntimeErrorType.assertionFailure("Too much recursion")
                    }
                    for (name, symbol) in _context.userSymbols {
                        switch symbol {
                        case .option:
                            // Only options are copied from call scope
                            context.define(name, as: symbol)
                        case .block, .function, .property, .constant, .placeholder:
                            break
                        }
                    }
                    context.define("children", as: .constant(.tuple(_context.children)))
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
                    block.statements.gatherDefinitions(in: context)
                    for statement in block.statements {
                        if case let .option(identifier, expression) = statement.type {
                            if case .option? = context.symbol(for: identifier.name) {
                                // Ignore default
                            } else {
                                try context.define(
                                    identifier.name,
                                    as: .constant(expression.evaluate(in: context))
                                )
                            }
                        } else {
                            try statement.evaluate(in: context)
                        }
                    }
                    let children = context.children.unwrapped(recursive: true)
                    if children.count == 1 {
                        switch children[0] {
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
                            // TODO: why not just use `geometry.transformed(by: context.transform)`?
                            // TODO: why `context.sourceLocation` and not `geometry.sourceLocation`?
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
                        case let .polygon(polygon):
                            return .polygon(polygon.transformed(by: context.transform))
                        case let value:
                            return value
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
                            case let .polygon(polygon):
                                return .polygon(polygon.transformed(by: context.transform))
                            default:
                                return $0
                            }
                        })
                    }
                    return try .mesh(Geometry(
                        type: .group,
                        name: context.name,
                        transform: context.transform,
                        material: .default,
                        smoothing: context.smoothing,
                        children: children.map {
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
                                    "Blocks that return \(aOrAn($0.errorDescription)) " +
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
            let childTransform: Transform = isFunctionScope ? .identity : childTransform
            func valueForAdding(_ value: Value) -> Value? {
                switch value {
                case let .tuple(values):
                    let values = values.compactMap(valueForAdding)
                    return values.isEmpty ? nil : .tuple(values)
                case let .mesh(m):
                    return .mesh(m.transformed(by: childTransform))
                case let .vector(v):
                    return .vector(v.transformed(by: childTransform))
                case let .point(p):
                    return .point(p.transformed(by: childTransform))
                case let .polygon(p):
                    return .polygon(p.transformed(by: childTransform).vertexColorsToMaterial(material: material))
                case let .path(path):
                    return .path(path.transformed(by: childTransform))
                case _ where childTypes.subtypes.contains(.text):
                    return .text(TextValue(
                        string: value.stringValue,
                        font: self.value(for: "font")?.stringValue ?? font,
                        color: material.color,
                        linespacing: self.value(for: "linespacing")?.doubleValue
                    ))
                default:
                    return value
                }
            }
            valueForAdding(value).map { children.append($0) }
        } else if case let .tuple(values) = value {
            try values.forEach(addValue)
        } else {
            throw RuntimeErrorType.unusedValue(type: value.type)
        }
    }
}

extension Block {
    func evaluate(in context: EvaluationContext) throws {
        statements.gatherDefinitions(in: context)
        try statements.forEach { try $0.evaluate(in: context) }
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
            var name = identifier.name
            if let type = context.options[name] ?? {
                if let altName = EvaluationContext.altNames[name],
                   let type = context.options["color"]
                {
                    name = altName
                    return type
                }
                if let type = context.options["*"] {
                    context.options[name] = .any
                    return type
                }
                return nil
            }() {
                return try context.define(name, as: .option(
                    evaluateParameter(
                        parameter,
                        as: type,
                        for: identifier,
                        in: context
                    )
                ))
            }
            guard let symbol = context.symbol(for: name) else {
                throw RuntimeError(
                    .unknownSymbol(name, options: context.commandSymbols),
                    at: identifier.range
                )
            }
            switch symbol {
            case let .function((parameterType, _), fn):
                let argument = try evaluateParameter(
                    parameter,
                    as: parameterType,
                    for: identifier,
                    in: context
                )
                try RuntimeError.wrap(context.addValue(fn(argument, context)), at: range)
            case let .property(type, setter, getter):
                if parameter == nil {
                    let value = try RuntimeError.wrap(getter(context), at: range)
                    do {
                        return try RuntimeError.wrap(context.addValue(value), at: range)
                    } catch let error as RuntimeError {
                        guard case .unusedValue = error.type else {
                            throw error
                        }
                    }
                }
                let argument = try evaluateParameter(
                    parameter,
                    as: type,
                    for: identifier,
                    in: context
                )
                try RuntimeError.wrap(setter(argument, context), at: range)
            case let .block(type, fn):
                if let parameter {
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
                } else if !type.childTypes.isOptional {
                    throw RuntimeError(.missingArgument(
                        for: name,
                        type: type.childTypes.errorDescriptionOrBlock
                    ), at: range.upperBound ..< range.upperBound)
                } else {
                    let childContext = context.push(type)
                    childContext.userSymbols.removeAll()
                    try RuntimeError.wrap(context.addValue(fn(childContext)), at: range)
                }
            case let .constant(value), let .option(value):
                var value = value
                if let parameter {
                    value = try .tuple([value, parameter.evaluate(in: context)])
                }
                try RuntimeError.wrap(context.addValue(value), at: range)
            case .placeholder:
                throw RuntimeError(.forwardReference(name), at: identifier.range)
            }
        case let .expression(type):
            let expression = Expression(type: type, range: range)
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
                context.define(identifier.name, as: .block(.init([:], [:], .void, .any)) { _ in .void })
            case .expression:
                break
            }
            try context.define(identifier.name, as: definition.evaluate(in: context))
        case .option:
            throw RuntimeError(.unknownSymbol("option", options: []), at: range)
        case let .forloop(identifier, in: expression, block):
            let value = try expression.evaluate(in: context)
            // TODO: evaluate(as: .sequence, ...) should be enough to make the below check
            // unnecessary, however because <type> can always be cast to .list(<type>)
            // it isn't. Need to find a static solution for this (or abandon this check)
            guard let sequence = value.sequenceValue else {
                throw RuntimeError(
                    .typeMismatch(
                        for: "loop bounds",
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
            try context.pushScope { context in
                let value = try condition.evaluate(
                    as: .boolean,
                    for: "if condition",
                    in: context
                )
                if value.boolValue {
                    try body.evaluate(in: context)
                } else if let elseBody {
                    try elseBody.evaluate(in: context)
                }
            }
        case let .switchcase(condition, cases, else: elseBody):
            try context.pushScope { context in
                let value = try condition.evaluate(
                    as: .any,
                    for: "switch condition",
                    in: context
                )
                if let lastCaseBody = cases.last?.body {
                    for statement in lastCaseBody.statements {
                        if case let .command(identifier, nil) = statement.type,
                           identifier.name == "default"
                        {
                            throw RuntimeError(
                                .unknownSymbol("default", options: []),
                                at: identifier.range
                            )
                        }
                    }
                }
                for caseStatement in cases {
                    let pattern = try caseStatement.pattern.evaluate(
                        as: .any,
                        for: "case pattern",
                        in: context
                    )
                    let type = value.type
                    if pattern.as(type) != value {
                        switch pattern {
                        case let .range(range) where type == .number:
                            if !range.contains(value.doubleValue) {
                                continue
                            }
                        case let .tuple(values):
                            if !values.contains(where: {
                                $0.as(type) == value
                            }) {
                                continue
                            }
                        default:
                            continue
                        }
                    }
                    try caseStatement.body.evaluate(in: context)
                    return
                }
                try elseBody?.evaluate(in: context)
            }
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
            case let .function((parameterType, _), fn):
                if parameterType.isOptional {
                    return try RuntimeError.wrap(fn(.void, context), at: range)
                }
                // Functions with parameters can't be called without arguments
                throw RuntimeError(.missingArgument(
                    for: name,
                    type: parameterType
                ), at: range.upperBound ..< range.upperBound)
            case let .property(_, _, getter):
                return try RuntimeError.wrap(getter(context), at: range)
            case let .block(type, fn):
                guard type.childTypes.isOptional else {
                    // Blocks that require children can't be called without arguments
                    throw RuntimeError(.missingArgument(
                        for: name,
                        type: type.childTypes.errorDescriptionOrBlock
                    ), at: range.upperBound ..< range.upperBound)
                }
                return try RuntimeError.wrap(fn(context.push(type)), at: range)
            case let .constant(value), let .option(value):
                return value
            case .placeholder:
                throw RuntimeError(.forwardReference(name), at: range)
            }
        case let .block(identifier, block):
            let (name, range) = (identifier.name, identifier.range)
            guard let symbol = context.symbol(for: name) else {
                throw RuntimeError(
                    .unknownSymbol(name, options: context.expressionSymbols),
                    at: range
                )
            }
            switch symbol {
            case let .block(type, fn):
                if context.isCancelled() {
                    throw EvaluationCancelled()
                }
                let newContext = context.push(type)
                defer {
                    // TODO: find better solution for this
                    context.background = newContext.background
                }
                try newContext.pushScope { newContext in
                    block.statements.gatherDefinitions(in: newContext)
                    for statement in block.statements {
                        try statement.evaluate(in: newContext)
                    }
                }
                return try RuntimeError.wrap(fn(newContext), at: range)
            case let .constant(value), let .option(value):
                guard let value = value.as(.list(.path)) ?? value.as(.list(.mesh)),
                      case let .tuple(values) = value
                else {
                    throw RuntimeError(.unexpectedArgument(for: name, max: 0), at: block.range)
                }
                let sourceIndex = context.sourceIndex
                let newContext = context.push(.init(.transform, [:], .mesh, value.type))
                block.statements.gatherDefinitions(in: newContext)
                for statement in block.statements {
                    try statement.evaluate(in: newContext)
                }
                newContext.sourceIndex = sourceIndex
                if values.first?.type == .path {
                    return .tuple(values.map {
                        .path(($0.value as! Path).transformed(by: newContext.transform))
                    })
                }
                return .tuple(values.map {
                    .mesh(($0.value as! Geometry).transformed(by: newContext.transform))
                })
            case let .property(type, setter, _):
                let blockType = BlockType([:], type.memberTypes, .void, type)
                let newContext = context.push(blockType)
                try newContext.pushScope { newContext in
                    block.statements.gatherDefinitions(in: newContext)
                    for statement in block.statements {
                        try statement.evaluate(in: newContext)
                    }
                }
                let values = Dictionary(uniqueKeysWithValues: newContext.options.keys.compactMap { key in
                    newContext.value(for: key).map { (key, $0) }
                })
                guard let instance = type.instance(with: values) else {
                    throw RuntimeError(.typeMismatch(
                        for: name,
                        expected: type.errorDescription,
                        got: "block"
                    ), at: block.range)
                }
                try RuntimeError.wrap(setter(instance, context), at: range)
                return type.isSubtype(of: context.childTypes) ? instance : .void
            case .function((.void, _), _):
                throw RuntimeError(.unexpectedArgument(for: name, max: 0), at: block.range)
            case let .function((type, _), _):
                throw RuntimeError(.typeMismatch(
                    for: name,
                    expected: type.errorDescription,
                    got: "block"
                ), at: block.range)
            case .placeholder:
                throw RuntimeError(.forwardReference(name), at: identifier.range)
            }
        case let .tuple(expressions):
            guard let identifier = expressions.first,
                  case let .identifier(name) = identifier.type,
                  let type = context.options[name],
                  expressions.count > 1
            else {
                return try .tuple(evaluateParameters(expressions, in: context).map(\.value))
            }
            let params = Array(expressions.dropFirst())
            let param = Expression(
                type: .tuple(params),
                range: params[0].range.lowerBound ..< params.last!.range.upperBound
            )
            let value = try param.evaluate(as: type, for: name, in: context)
            context.define(name, as: .option(value))
            return .void
        case let .prefix(op, expression):
            let value = try expression.evaluate(as: .numberOrVector, for: op.rawValue, in: context)
            switch op {
            case .minus:
                switch value {
                case let .tuple(values):
                    return .tuple(values.map {
                        switch $0 {
                        case let .number(value):
                            return .number(-value)
                        case let .radians(value):
                            return .radians(-value)
                        default:
                            assertionFailure()
                            return value
                        }
                    })
                case let .number(value):
                    return .number(-value)
                case let .radians(value):
                    return .radians(-value)
                default:
                    assertionFailure()
                    return value
                }
            case .plus:
                return value
            }
        case let .infix(lhs, .to, rhs):
            let start = try lhs.evaluate(as: .number, for: "to", index: 0, in: context)
            let end = try rhs.evaluate(as: .number, for: "to", index: 1, in: context)
            return .range(RangeValue(from: start.doubleValue, to: end.doubleValue))
        case let .infix(lhs, .step, rhs):
            let rangeType = ValueType.union([.range, .partialRange])
            let rangeValue = try lhs.evaluate(as: rangeType, for: "step", index: 0, in: context)
            let stepValue = try rhs.evaluate(as: .number, for: "step", index: 1, in: context)
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
        case let .infix(lhs, .in, rhs):
            let lhs = try lhs.evaluate(in: context)
            let collectionType = ValueType.union([.partialRange, .sequence, .anyObject])
            let rhs = try rhs.evaluate(as: collectionType, for: "in", index: 1, in: context)
            switch rhs {
            case let .range(range) where lhs.isConvertible(to: .number):
                return .boolean(range.contains(lhs.doubleValue))
            case let .tuple(values) where values.contains(lhs):
                return .boolean(true)
            default:
                return .boolean(rhs[lhs.stringValue, context.isCancelled] != nil)
            }
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
            func evaluate(_ exp: Expression, as type: ValueType, at index: Int = 0) throws -> Value {
                try exp.evaluate(as: type, for: op.rawValue, index: index, in: context)
            }
            func doubleValue(for exp: Expression, at index: Int = 0) throws -> Double {
                try evaluate(exp, as: .number, at: index).doubleValue
            }
            func numberOrVectorValue(for exp: Expression, at index: Int = 0) throws -> Value {
                try evaluate(exp, as: .numberOrVector, at: index)
            }
            func apply(_ lhs: Value, _ rhs: Value, _ fn: (Double, Double) -> Double) -> Value {
                switch (lhs, rhs, op) {
                case let (.number(lhs), .radians(rhs), .plus), let (.number(lhs), .radians(rhs), .minus),
                     let (.radians(lhs), .number(rhs), .plus), let (.radians(lhs), .number(rhs), .minus),
                     let (.radians(lhs), .radians(rhs), .times), // TODO: should this be an error?
                     let (.radians(lhs), .radians(rhs), .divide), // TODO: should this be halfTurns?
                     let (.number(lhs), .number(rhs), _):
                    return .number(fn(lhs, rhs)) // TODO: should this be an error?
                case let (.number(lhs), .radians(rhs), .divide):
                    return .radians(fn(lhs, rhs)) // TODO: should this be a reciprocal radians type?
                case let (.radians(lhs), .radians(rhs), _), let (.number(lhs), .radians(rhs), _),
                     let (.radians(lhs), .number(rhs), _):
                    return .radians(fn(lhs, rhs))
                case let (.tuple(lhs), _, _) where lhs.count == 1:
                    return apply(lhs[0], rhs, fn)
                case let (_, .tuple(rhs), _) where rhs.count == 1:
                    return apply(lhs, rhs[0], fn)
                case let (.tuple(lhs), .tuple(rhs), _):
                    return .tuple(zip(lhs, rhs).map { apply($0, $1, fn) })
                case let (.tuple(lhs), .number, _):
                    return .tuple(lhs.map { apply($0, rhs, fn) })
                case let (.number, .tuple(rhs), _):
                    return .tuple(rhs.map { apply(lhs, $0, fn) })
                default:
                    assertionFailure()
                    return .number(0)
                }
            }
            func tupleApply(_ fn: (Double, Double) -> Double, widen: Bool) throws -> Value {
                let lhs = try numberOrVectorValue(for: lhs)
                let rhs = try numberOrVectorValue(for: rhs, at: 1)
                switch (apply(lhs, rhs, fn), lhs) {
                case let (.tuple(values), .tuple(lhs)) where widen:
                    return .tuple(values + lhs[values.count...])
                case let (value, _):
                    return value
                }
            }
            func tupleOrTextureApply(_ fn: (Double, Double) -> Double) throws -> Value {
                let lhs = try evaluate(lhs, as: .union([
                    .number,
                    .radians,
                    .list(.number),
                    .list(.radians),
                    .texture,
                ]))
                switch lhs {
                case let .texture(texture):
                    guard let texture else {
                        return .texture(nil)
                    }
                    let rhs = try doubleValue(for: rhs)
                    return .texture(texture.withIntensity(fn(texture.intensity, rhs)))
                default:
                    let rhs = try numberOrVectorValue(for: rhs, at: 1)
                    return apply(lhs, rhs, fn)
                }
            }

            switch op {
            case .minus:
                return try tupleApply(-, widen: true)
            case .plus:
                return try tupleApply(+, widen: true)
            case .times:
                return try tupleOrTextureApply(*)
            case .divide:
                return try tupleOrTextureApply(/)
            case .modulo:
                return try tupleApply(fmod, widen: false)
            case .lt:
                return try .boolean(doubleValue(for: lhs) < doubleValue(for: rhs, at: 1))
            case .gt:
                return try .boolean(doubleValue(for: lhs) > doubleValue(for: rhs, at: 1))
            case .lte:
                return try .boolean(doubleValue(for: lhs) <= doubleValue(for: rhs, at: 1))
            case .gte:
                return try .boolean(doubleValue(for: lhs) >= doubleValue(for: rhs, at: 1))
            case .in, .to, .step, .equal, .unequal, .and, .or:
                throw RuntimeErrorType.assertionFailure("\(op.rawValue) should be handled by earlier case")
            }
        case let .member(expression, member):
            let value = try expression.evaluate(in: context)
            if let memberValue = value[member.name, context.isCancelled] {
                assert([.void, .number(0)].contains(memberValue) || value.hasMember(member.name))
                return memberValue
            }
            // TODO: if hasMember() == true, should we return void instead of an error?
            throw RuntimeError(.unknownMember(member.name, of: value), at: member.range)
        case let .subscript(lhs, rhs):
            let value = try lhs.evaluate(in: context)
            let indexType = ValueType.union([.number, .range, .partialRange, .string])
            let index = try rhs.evaluate(as: indexType, for: "index", in: context)
            switch index {
            case let .number(number):
                let index = Int(truncating: number as NSNumber)
                guard let member = value[index] else {
                    throw RuntimeError(.invalidIndex(number, range: value.indices), at: rhs.range)
                }
                return member
            case let .range(range):
                let indices = value.indices
                if !indices.contains(Int(truncating: range.start as NSNumber)) {
                    throw RuntimeError(.invalidIndex(range.start, range: indices), at: rhs.range)
                }
                let stride = range.stride ?? stride(
                    from: range.start,
                    through: range.stepIsPositive ? Double(indices.last ?? 0) : 0,
                    by: range.step ?? 1
                )
                return try .tuple(stride.map {
                    let index = Int(truncating: $0 as NSNumber)
                    guard let member = value[index] else {
                        throw RuntimeError(.invalidIndex($0, range: indices), at: rhs.range)
                    }
                    return member
                })
            default:
                if let member = value[index.stringValue, context.isCancelled] {
                    return member
                }
                throw RuntimeError(.unknownMember(index.logDescription, of: value), at: rhs.range)
            }
        case let .import(expression):
            let pathValue = try expression.evaluate(
                as: .string,
                for: Keyword.import.rawValue,
                in: context
            )
            let path = pathValue.stringValue
            context.sourceIndex = expression.range.lowerBound
            return try RuntimeError.wrap(context.importFile(at: path), at: expression.range)
        }
    }

    func evaluate(
        as type: ValueType,
        for name: String,
        index: Int = -1,
        in context: EvaluationContext
    ) throws -> Value {
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
                value = .tuple(values.map(\.value))
            } else {
                value = try evaluate(in: context)
                values = []
            }
        } catch var error as RuntimeError {
            if case .unknownSymbol(let name, var options) = error.type {
                options += InfixOperator.allCases.map(\.rawValue)
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
        case let (.tuple(expressions), type) where ValueType.rotation.isSubtype(of: type):
            if let index = values.firstIndex(where: {
                !$0.value.isConvertible(to: .halfturns)
            }) {
                throw RuntimeError(.typeMismatch(
                    for: name,
                    index: index,
                    expected: .halfturns,
                    got: values[index].value.type
                ), at: expressions[index].range)
            }
            throw RuntimeError(.typeMismatch(
                for: name,
                index: index,
                expected: type,
                got: value.type
            ), at: range)
        case let (.tuple(expressions), type) where expressions.count > 1:
            var value = value
            if InfixOperator(rawValue: name) == nil,
               PrefixOperator(rawValue: name) == nil
            {
                value = try expressions[0].evaluate(in: context)
                if value.isConvertible(to: type) {
                    var i = 0
                    var values = [value]
                    while value.isConvertible(to: type), i < expressions.count - 1 {
                        i += 1
                        try values.append(expressions[i].evaluate(in: context))
                        value = .tuple(values)
                    }
                    throw RuntimeError(
                        .unexpectedArgument(for: name, max: i),
                        at: expressions[i].range
                    )
                }
            }
            throw RuntimeError(.typeMismatch(
                for: name,
                index: index,
                expected: type,
                got: value.type
            ), at: range)
        case let (_, .tuple(types)) where types.count > 1 && !types[1].isOptional:
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
