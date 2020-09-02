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

public protocol EvaluationDelegate: AnyObject {
    func resolveURL(for path: String) -> URL
    func importGeometry(for url: URL) throws -> Geometry?
    func debugLog(_ values: [Any?])
}

public func evaluate(_ program: Program, delegate: EvaluationDelegate?) throws -> [Geometry] {
    let context = EvaluationContext(source: program.source, delegate: delegate)
    try program.evaluate(in: context)
    return context.children.map { $0.value as! Geometry }
}

public enum ImportError: Error, Equatable {
    case lexerError(LexerError)
    case parserError(ParserError)
    case runtimeError(RuntimeError)
    case unknownError

    public init(_ error: Error) {
        switch error {
        case let error as LexerError: self = .lexerError(error)
        case let error as ParserError: self = .parserError(error)
        case let error as RuntimeError: self = .runtimeError(error)
        default: self = .unknownError
        }
    }

    public var range: Range<String.Index>? {
        switch self {
        case let .lexerError(error): return error.range
        case let .parserError(error): return error.range
        case let .runtimeError(error): return error.range
        default: return nil
        }
    }

    public var message: String? {
        switch self {
        case let .lexerError(error): return error.message
        case let .parserError(error): return error.message
        case let .runtimeError(error): return error.message
        default: return nil
        }
    }
}

public enum RuntimeErrorType: Error, Equatable {
    case unknownSymbol(String, options: [String])
    case typeMismatch(for: String, index: Int, expected: String, got: String)
    case unexpectedArgument(for: String, max: Int)
    case missingArgument(for: String, index: Int, type: String)
    case unusedValue(type: String)
    case fileNotFound(for: String, at: URL?)
    case fileAccessRestricted(for: String, at: URL)
    case fileTypeMismatch(for: String, at: URL, expected: String?)
    case fileParsingError(for: String, at: URL, message: String)
    indirect case importError(ImportError, for: String, in: String)
}

private func bestMatches(for symbol: String, in suggestions: [String]) -> [String] {
    func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        var dist = [[Int]]()
        for i in 0 ... lhs.count {
            dist.append([i])
        }
        for j in 1 ... rhs.count {
            dist[0].append(j)
        }
        for i in 1 ... lhs.count {
            let lhs = lhs[lhs.index(lhs.startIndex, offsetBy: i - 1)]
            for j in 1 ... rhs.count {
                if lhs == rhs[rhs.index(rhs.startIndex, offsetBy: j - 1)] {
                    dist[i].append(dist[i - 1][j - 1])
                } else {
                    dist[i].append(min(min(dist[i - 1][j] + 1, dist[i][j - 1] + 1), dist[i - 1][j - 1] + 1))
                }
            }
        }
        return dist[lhs.count][rhs.count]
    }
    let lowercasedSymbol = symbol.lowercased()
    // Sort suggestions by Levenshtein distance
    return suggestions
        .compactMap { string -> (String, Int)? in
            let lowercaseString = string.lowercased()
            let distance = levenshtein(lowercaseString, lowercasedSymbol)
            guard distance <= lowercasedSymbol.count / 2 ||
                !lowercaseString.commonPrefix(with: lowercasedSymbol).isEmpty
            else {
                return nil
            }
            return (string, distance)
        }
        .sorted { $0.1 < $1.1 }
        .map { $0.0 }
}

public struct RuntimeError: Error, Equatable {
    public let type: RuntimeErrorType
    public let range: Range<String.Index>

    public var message: String {
        switch type {
        case let .unknownSymbol(name, _):
            if Keyword(rawValue: name) == nil, Symbols.all[name] == nil {
                return "Unknown symbol '\(name)'"
            }
            return "Unexpected symbol '\(name)'"
        case .typeMismatch:
            return "Type mismatch"
        case .unexpectedArgument:
            return "Unexpected argument"
        case .missingArgument:
            return "Missing argument"
        case .unusedValue:
            return "Unused value"
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
        case let .importError(_, for: name, _):
            return "Error in imported file '\(name)'"
        }
    }

    public var suggestion: String? {
        guard case let .unknownSymbol(name, options) = type else {
            return nil
        }
        let alternatives = [
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
        ]
        return alternatives[name.lowercased()]?
            .first(where: { options.contains($0) || Keyword(rawValue: $0) != nil })
            ?? bestMatches(for: name, in: options).first
    }

    public var hint: String? {
        func nth(_ index: Int) -> String {
            switch index {
            case 1: return "second "
            case 2: return "third "
            case 3: return "fourth "
            case 4: return "fifth "
            default: return ""
            }
        }
        switch type {
        case let .unknownSymbol(name, _):
            var hint = Keyword(rawValue: name) == nil && Symbols.all[name] == nil ? "" :
                "The \(name) command is not available in this context."
            if let suggestion = suggestion {
                hint = (hint.isEmpty ? "" : "\(hint) ") + "Did you mean '\(suggestion)'?"
            }
            return hint
        case let .typeMismatch(for: name, index: index, expected: type, got: got):
            return "The \(nth(index))argument for \(name) should be a \(type), not a \(got)."
        case let .unexpectedArgument(for: name, max: max):
            if max == 0 {
                return "The \(name) command does not expect any arguments."
            } else if max == 1 {
                return "The \(name) command expects only a single argument."
            } else {
                return "\(name) command expects a maximum of \(max) arguments."
            }
        case let .missingArgument(for: name, index: index, type: type):
            let type = (type == ValueType.pair.rawValue) ? ValueType.number.rawValue : type
            if index == 0 {
                return "The \(name) command expects an argument of type \(type)."
            } else {
                return "The \(name) command expects a \(nth(index))argument of type \(type)."
            }
        case let .unusedValue(type: type):
            return "A \(type) value was not expected in this context."
        case let .fileNotFound(for: _, at: url):
            guard let url = url else {
                return nil
            }
            return "ShapeScript expected to find the file at '\(url.path)'. Check that it exists and is located here."
        case let .fileAccessRestricted(for: _, at: url):
            return "ShapeScript cannot read the file due to macOS security restrictions. Please open the directory at '\(url.path)' to grant access."
        case let .fileParsingError(for: _, at: _, message: message):
            return message
        case let .fileTypeMismatch(for: _, at: url, expected: type):
            guard let type = type else {
                return "The type of file at '\(url.path)' is not supported."
            }
            return "The file at '\(url.path)' is not a \(type) file."
        case let .importError(error, for: _, in: source):
            guard let message = error.message, let range = error.range else {
                return nil
            }
            let line = source.lineAndColumn(at: range.lowerBound).line
            return "\(message) at line \(line)."
        }
    }

    init(_ type: RuntimeErrorType, at range: Range<String.Index>) {
        self.type = type
        self.range = range
    }
}

// MARK: Implementation

enum ValueType: String {
    case color
    case texture
    case number
    case vector
    case size
    case string
    case path
    case paths // Hack to support multiple paths
    case mesh
    case tuple
    case point
    case pair // Hack to support common math functions
    case void
}

enum Value {
    case color(Color)
    case texture(Texture?)
    case number(Double)
    case vector(Vector)
    case size(Vector)
    case string(String?) // TODO: handle optionals in a better way than this
    case path(Path)
    case paths([Path])
    case mesh(Geometry)
    case point(PathPoint)
    case tuple([Value])
    case pair(Double, Double)
    case void

    var value: Any {
        switch self {
        case let .color(color): return color
        case let .texture(texture): return texture as Any
        case let .number(number): return number
        case let .vector(vector): return vector
        case let .size(size): return size
        case let .string(string): return string as Any
        case let .path(path): return path
        case let .paths(paths): return paths
        case let .mesh(mesh): return mesh
        case let .point(point): return point
        case let .tuple(values): return values.map { $0.value }
        case let .pair(pair): return pair
        case .void: return ()
        }
    }

    var doubleValue: Double {
        return value as! Double
    }

    var intValue: Int {
        return Int(truncating: doubleValue as NSNumber)
    }

    var type: ValueType {
        switch self {
        case .color: return .color
        case .texture: return .texture
        case .number: return .number
        case .vector: return .vector
        case .size: return .size
        case .string: return .string
        case .path: return .path
        case .paths: return .paths
        case .mesh: return .mesh
        case .point: return .point
        case .tuple: return .tuple
        case .pair: return .pair
        case .void: return .void
        }
    }

    var members: [String] {
        switch self {
        case .vector:
            return ["x", "y", "z"]
        case .size:
            return ["width", "height", "depth"]
        case .color:
            return ["red", "green", "blue", "alpha"]
        case .tuple:
            return [
                "x", "y", "z",
                "width", "height", "depth",
                "red", "green", "blue", "alpha",
            ]
        default:
            return []
        }
    }

    subscript(_ name: String) -> Value? {
        switch self {
        case let .vector(vector):
            switch name {
            case "x": return .number(vector.x)
            case "y": return .number(vector.y)
            case "z": return .number(vector.z)
            default: return nil
            }
        case let .size(size):
            switch name {
            case "width": return .number(size.x)
            case "height": return .number(size.y)
            case "depth": return .number(size.z)
            default: return nil
            }
        case let .color(color):
            switch name {
            case "red": return .number(color.r)
            case "green": return .number(color.g)
            case "blue": return .number(color.b)
            case "alpha": return .number(color.a)
            default: return nil
            }
        case let .tuple(values):
            let values = values.map { $0.doubleValue }
            switch name {
            case "x", "y", "z":
                return Value.vector(Vector(values))[name]
            case "width", "height", "depth":
                return Value.size(Vector(size: values))[name]
            case "red", "green", "blue", "alpha":
                return Value.color(Color(unchecked: values))[name]
            default:
                return nil
            }
        default:
            return nil
        }
    }
}

typealias Options = [String: ValueType]

enum BlockType {
    case builder
    case group
    case path
    case text
    indirect case custom(BlockType?, Options)

    static let primitive = BlockType.custom(nil, [:])

    var options: Options {
        switch self {
        case let .custom(baseType, options):
            return (baseType?.options ?? [:]).merging(options) { $1 }
        case .builder, .group, .path, .text:
            return [:]
        }
    }

    var childTypes: Set<ValueType> {
        switch self {
        case .builder: return [.path, .paths]
        case .group: return [.mesh]
        case .path: return [.point, .path, .paths]
        case .text: return [.string]
        case let .custom(baseType, _):
            return baseType?.childTypes ?? []
        }
    }

    var symbols: Symbols {
        switch self {
        case .group: return .group
        case .builder: return .builder
        case .path: return .path
        case .text: return .text
        case let .custom(baseType, _):
            return baseType?.symbols ?? .primitive
        }
    }
}

extension Program {
    func evaluate(in context: EvaluationContext) throws {
        let oldSource = context.source
        context.source = source
        try statements.forEach { try $0.evaluate(in: context) }
        context.source = oldSource
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
            .missingArgument(for: name, index: 0, type: type.rawValue),
            at: range.upperBound ..< range.upperBound
        )
    }
    var parameters = [parameter]
    if case let .tuple(expressions) = parameter.type {
        parameters = expressions
    }
    var values = [Value]()
    for (i, param) in parameters.enumerated() {
        if case let .identifier(identifier) = param.type {
            let (name, range) = (identifier.name, identifier.range)
            if case let .command(parameterType, fn)? = context.symbol(for: name), parameterType != .void {
                guard i < parameters.count - 1 else {
                    throw RuntimeError(
                        .missingArgument(for: identifier.name, index: 0, type: parameterType.rawValue),
                        at: param.range.upperBound ..< param.range.upperBound
                    )
                }
                var range = parameters[i + 1].range.lowerBound ..< parameters.last!.range.upperBound
                let param = Expression(type: .tuple(Array(parameters[(i + 1)...])), range: range)
                let arg = try evaluateParameter(param, as: parameterType, for: identifier, in: context)
                try values.append(fn(arg, context))
                // collapse params
                range = parameters[i].range.lowerBound ..< parameters.last!.range.upperBound
                parameters[i...] = [Expression(type: .tuple(Array(parameters[i...])), range: range)]
                break
            }
        }
        try values.append(param.evaluate(in: context))
    }
    func numerify(max: Int, min: Int) throws -> [Double] {
        var values = values
        if parameters.count > max {
            throw RuntimeError(.unexpectedArgument(for: name, max: max), at: parameters[max].range)
        } else if parameters.count < min {
            let upperBound = parameters.last?.range.upperBound ?? range.upperBound
            throw RuntimeError(
                .missingArgument(for: name, index: min - 1, type: ValueType.number.rawValue),
                at: upperBound ..< upperBound
            )
        }
        if values.count == 1, case let .tuple(elements) = values[0] {
            if elements.count > max {
                let range: Range<String.Index>
                if case let .tuple(expressions) = parameters[0].type {
                    range = expressions[max].range
                } else {
                    range = parameters[0].range
                }
                throw RuntimeError(.unexpectedArgument(for: name, max: max), at: range)
            }
            values = elements
        }
        var numbers = [Double]()
        for (i, value) in values.enumerated() {
            guard case let .number(number) = value else {
                let i = Swift.min(parameters.count - 1, i)
                let type = (i == 0) ? type.rawValue : ValueType.number.rawValue
                throw RuntimeError(
                    .typeMismatch(
                        for: name,
                        index: i,
                        expected: type,
                        got: value.type.rawValue
                    ),
                    at: parameters[i].range
                )
            }
            numbers.append(number)
        }
        return numbers
    }
    if parameters.isEmpty {
        if type != .void {
            throw RuntimeError(
                .missingArgument(for: name, index: 0, type: type.rawValue),
                at: range.upperBound ..< range.upperBound
            )
        }
        return .void
    }
    if parameters.count == 1, values[0].type == type {
        return values[0]
    }
    switch type {
    case .color:
        let numbers = try numerify(max: 4, min: 1)
        return .color(Color(unchecked: numbers))
    case .vector:
        let numbers = try numerify(max: 3, min: 1)
        return .vector(Vector(numbers))
    case .size:
        let numbers = try numerify(max: 3, min: 1)
        return .size(Vector(size: numbers))
    case .pair:
        let numbers = try numerify(max: 2, min: 2)
        return .pair(numbers[0], numbers[1])
    case .tuple where values[0].type != .tuple:
        return .tuple(values)
    case .texture where values.count == 1 && values[0].type == .string:
        let name = values[0].value as? String
        do {
            return try .texture(name.map {
                .file(name: $0, url: try context.resolveURL(for: $0))
            })
        } catch let error as RuntimeErrorType {
            throw RuntimeError(error, at: parameters[0].range)
        }
    case .number, .string, .texture, .path, .paths, .mesh, .point, .tuple:
        if parameters.count > 1 {
            throw RuntimeError(
                .unexpectedArgument(for: name, max: 1),
                at: parameters[1].range
            )
        }
        let value = values[0]
        if value.type != type {
            switch (value.type, type) {
            case (.path, .paths):
                return Value.paths([value.value as! Path])
            default:
                throw RuntimeError(
                    .typeMismatch(
                        for: name,
                        index: 0,
                        expected: type.rawValue,
                        got: value.type.rawValue
                    ),
                    at: parameters[0].range
                )
            }
        }
        return value
    case .void:
        throw RuntimeError(
            .unexpectedArgument(for: name, max: 0),
            at: parameters[0].range
        )
    }
}

extension Definition {
    func evaluate(in context: EvaluationContext) throws -> Symbol {
        switch type {
        case let .expression(expression):
            let context = context.pushDefinition()
            return try .constant(expression.evaluate(in: context))
        case let .block(block):
            var options = Options()
            for statement in block.statements {
                if case let .option(identifier, expression) = statement.type {
                    let value = try expression.evaluate(in: context) // TODO: get static type w/o evaluating
                    options[identifier.name] = value.type
                }
            }
            let source = context.source
            let baseURL = context.baseURL
            return .block(.custom(nil, options)) { context in
                do {
                    let context = context.pushDefinition()
                    context.source = source
                    for statement in block.statements {
                        if case let .option(identifier, expression) = statement.type {
                            if context.symbol(for: identifier.name) == nil {
                                context.define(identifier.name,
                                               as: .constant(try expression.evaluate(in: context)))
                            }
                        } else {
                            try statement.evaluate(in: context)
                        }
                    }
                    let children = context.children
                    if children.count == 1, let value = children.first {
                        guard let path = value.value as? Path else {
                            let geometry = value.value as! Geometry
                            return .mesh(Geometry(
                                type: geometry.type,
                                name: context.name,
                                transform: geometry.transform * context.transform,
                                material: geometry.material,
                                children: geometry.children,
                                sourceLocation: context.sourceLocation
                            ))
                        }
                        if let name = context.name {
                            return .mesh(Geometry(
                                type: .path(path),
                                name: name,
                                transform: context.transform,
                                material: .default,
                                children: [],
                                sourceLocation: context.sourceLocation
                            ))
                        }
                        return .path(path.transformed(by: context.transform))
                    } else if context.name == nil, !children.isEmpty, !children.contains(where: {
                        if case .path = $0 { return false } else { return true }
                    }) {
                        return .paths(children.map {
                            ($0.value as! Path).transformed(by: context.transform)
                        })
                    }
                    return .mesh(Geometry(
                        type: .none,
                        name: context.name,
                        transform: context.transform,
                        material: .default,
                        children: children.map {
                            guard let path = $0.value as? Path else {
                                return $0.value as! Geometry
                            }
                            return Geometry(
                                type: .path(path),
                                name: nil,
                                transform: .identity,
                                material: .default,
                                children: [],
                                sourceLocation: context.sourceLocation
                            )
                        },
                        sourceLocation: context.sourceLocation
                    ))
                } catch {
                    if baseURL == context.baseURL {
                        throw error
                    }
                    // TODO: improve this error by mentioning thre symbol that failed
                    // and showing the context of the failure not just the call site
                    throw RuntimeErrorType.importError(
                        ImportError(error),
                        for: baseURL?.lastPathComponent ?? "",
                        in: source
                    )
                }
            }
        }
    }
}

extension Statement {
    func evaluate(in context: EvaluationContext) throws {
        let value: Value
        switch type {
        case let .command(identifier, parameter):
            let (name, range) = (identifier.name, identifier.range)
            guard let symbol = context.symbol(for: name) else {
                throw RuntimeError(
                    .unknownSymbol(name, options: context.commandSymbols),
                    at: range
                )
            }
            switch symbol {
            case let .command(type, fn):
                let argument = try evaluateParameter(parameter,
                                                     as: type,
                                                     for: identifier,
                                                     in: context)
                do {
                    value = try fn(argument, context)
                } catch let error as RuntimeErrorType {
                    throw RuntimeError(error, at: range)
                }
            case let .property(type, setter, _):
                let argument = try evaluateParameter(parameter,
                                                     as: type,
                                                     for: identifier,
                                                     in: context)
                do {
                    try setter(argument, context)
                    value = .void
                } catch let error as RuntimeErrorType {
                    throw RuntimeError(error, at: range)
                }
            case let .block(type, fn):
                context.sourceIndex = range.lowerBound
                if let parameter = parameter {
                    // TODO: is this the right way to handle range?
                    let type = try parameter.evaluate(in: context).type
                    throw RuntimeError(
                        .typeMismatch(for: name, index: 0, expected: "block", got: type.rawValue),
                        at: parameter.range
                    )
                } else if !type.childTypes.isEmpty {
                    throw RuntimeError(
                        .missingArgument(for: name, index: 0, type: "block"),
                        at: range
                    )
                }
                do {
                    value = try fn(context.push(type))
                } catch let error as RuntimeErrorType {
                    throw RuntimeError(error, at: range)
                }
            case let .constant(v):
                value = v
            }
        case let .node(identifier, block):
            // TODO: better solution
            // This only works correctly if node was not imported from another file
            context.sourceIndex = range.lowerBound
            let p = Expression(type: .node(identifier, block), range: range)
            value = try p.evaluate(in: context)
        case let .expression(expression):
            value = try expression.evaluate(in: context)
        case let .define(identifier, definition):
            context.define(identifier.name, as: try definition.evaluate(in: context))
            return
        case .option:
            throw RuntimeError(.unknownSymbol("option", options: []), at: range)
        case let .forloop(index, start, end, block):
            let startValue = try start.evaluate(in: context)
            guard case let .number(startIndex) = startValue else {
                throw RuntimeError(
                    .typeMismatch(
                        for: "start index",
                        index: 0,
                        expected: ValueType.number.rawValue,
                        got: startValue.type.rawValue
                    ),
                    at: start.range
                )
            }
            let endValue = try end.evaluate(in: context)
            guard case let .number(endIndex) = endValue else {
                throw RuntimeError(
                    .typeMismatch(
                        for: "end index",
                        index: 0,
                        expected: ValueType.number.rawValue,
                        got: startValue.type.rawValue
                    ),
                    at: start.range
                )
            }
            // TODO: handle case where endIndex < startIndex
            // TODO: throw error if indexes are out of range
            for i in Int(startIndex) ... Int(endIndex) {
                try context.pushScope { context in
                    if let name = index?.name {
                        context.define(name, as: .constant(.number(Double(i))))
                    }
                    for statement in block.statements {
                        try statement.evaluate(in: context)
                    }
                }
            }
            return
        case let .import(expression):
            let pathValue = try expression.evaluate(in: context)
            guard let path = pathValue.value as? String else {
                let got = (pathValue.type == .string) ? "nil" : pathValue.type.rawValue
                throw RuntimeError(
                    .typeMismatch(
                        for: Keyword.import.rawValue, index: 0,
                        expected: ValueType.string.rawValue, got: got
                    ),
                    at: expression.range
                )
            }
            do {
                context.sourceIndex = expression.range.lowerBound
                try context.importModel(at: path)
                return
            } catch let error as RuntimeErrorType {
                throw RuntimeError(error, at: expression.range)
            }
        }
        switch value {
        case .void:
            break
        case _ where context.childTypes.contains(value.type):
            switch value {
            case let .mesh(m):
                context.children.append(.mesh(m.transformed(by: context.childTransform)))
            case let .vector(v):
                context.children.append(.vector(v.transformed(by: context.childTransform)))
            case let .point(v):
                context.children.append(.point(v.transformed(by: context.childTransform)))
            case let .path(path):
                context.children.append(.path(path.transformed(by: context.childTransform)))
            case let .paths(paths):
                for path in paths {
                    context.children.append(.path(path.transformed(by: context.childTransform)))
                }
            default:
                context.children.append(value)
            }
        case let .path(path) where context.childTypes.contains(.mesh):
            context.children.append(.mesh(Geometry(
                type: .path(path),
                name: context.name,
                transform: context.childTransform,
                material: .default, // not used for paths
                children: [],
                sourceLocation: context.sourceLocation
            )))
        case let .paths(paths) where context.childTypes.contains(.mesh):
            for path in paths {
                context.children.append(.mesh(Geometry(
                    type: .path(path),
                    name: context.name,
                    transform: context.childTransform,
                    material: .default, // not used for paths
                    children: [],
                    sourceLocation: context.sourceLocation
                )))
            }
        default:
            throw RuntimeError(.unusedValue(type: value.type.rawValue), at: range)
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
        case let .identifier(identifier):
            let (name, range) = (identifier.name, identifier.range)
            guard let symbol = context.symbol(for: name) else {
                throw RuntimeError(
                    .unknownSymbol(name, options: context.expressionSymbols),
                    at: range
                )
            }
            do {
                switch symbol {
                case let .command(parameterType, fn):
                    guard parameterType == .void else {
                        // commands can't be used as expressions
                        // TODO: make this possible
                        throw RuntimeErrorType.unknownSymbol(name, options: context.expressionSymbols)
                    }
                    return try fn(.void, context)
                case let .property(_, _, getter):
                    return try getter(context)
                case let .block(type, fn):
                    guard type.childTypes.isEmpty else {
                        // blocks that require children can't be used as expressions
                        // TODO: allow this if child matches next argument
                        throw RuntimeErrorType.unknownSymbol(name, options: context.expressionSymbols)
                    }
                    return try fn(context.push(type))
                case let .constant(value):
                    return value
                }
            } catch let error as RuntimeErrorType {
                throw RuntimeError(error, at: range)
            }
        case let .node(identifier, block):
            let (name, range) = (identifier.name, identifier.range)
            guard let symbol = context.symbol(for: name) else {
                throw RuntimeError(.unknownSymbol(name, options: context.expressionSymbols), at: range)
            }
            switch symbol {
            case let .block(type, fn):
                let sourceIndex = context.sourceIndex
                let context = context.push(type)
                for statement in block.statements {
                    switch statement.type {
                    case let .command(identifier, parameter):
                        let name = identifier.name
                        guard let type = type.options[name] else {
                            fallthrough
                        }
                        context.define(name, as: try .constant(
                            evaluateParameter(parameter,
                                              as: type,
                                              for: identifier,
                                              in: context)
                        ))
                    case .node, .define, .forloop, .expression, .import:
                        try statement.evaluate(in: context)
                    case .option:
                        throw RuntimeError(.unknownSymbol("option", options: []), at: statement.range)
                    }
                }
                context.sourceIndex = sourceIndex
                do {
                    return try fn(context)
                } catch let error as RuntimeErrorType {
                    throw RuntimeError(error, at: range)
                }
            case let .command(type, _):
                throw RuntimeError(
                    .typeMismatch(for: name, index: 0, expected: type.rawValue, got: "block"),
                    at: block.range
                )
            case .property, .constant:
                throw RuntimeError(
                    .unexpectedArgument(for: name, max: 0),
                    at: block.range
                )
            }
        case let .tuple(expressions):
            var values = [Value]()
            for (i, param) in expressions.enumerated() {
                if i < expressions.count - 1, case let .identifier(identifier) = param.type {
                    if case let .command(parameterType, fn)? = context.symbol(for: identifier.name), parameterType != .void {
                        let range = expressions[i + 1].range.lowerBound ..< expressions.last!.range.upperBound
                        let param = Expression(type: .tuple(Array(expressions[(i + 1)...])), range: range)
                        let arg = try evaluateParameter(param, as: parameterType, for: identifier, in: context)
                        try values.append(fn(arg, context))
                        break
                    }
                }
                try values.append(param.evaluate(in: context))
            }
            return values.count == 1 ? values[0] : .tuple(values)
        case let .prefix(op, expression):
            let value = try expression.evaluate(in: context)
            guard let number = value.value as? Double else {
                throw RuntimeError(
                    .typeMismatch(
                        for: String(op.rawValue),
                        index: 0,
                        expected: ValueType.number.rawValue,
                        got: value.type.rawValue
                    ),
                    at: expression.range
                )
            }
            switch op {
            case .minus:
                return .number(-number)
            case .plus:
                return .number(number)
            }
        case let .infix(lhs, op, rhs):
            let lvalue = try lhs.evaluate(in: context)
            guard let lnum = lvalue.value as? Double else {
                throw RuntimeError(
                    .typeMismatch(
                        for: String(op.rawValue),
                        index: 0,
                        expected: ValueType.number.rawValue,
                        got: lvalue.type.rawValue
                    ),
                    at: lhs.range
                )
            }
            let rvalue = try rhs.evaluate(in: context)
            guard let rnum = rvalue.value as? Double else {
                throw RuntimeError(
                    .typeMismatch(
                        for: String(op.rawValue),
                        index: 1,
                        expected: ValueType.number.rawValue,
                        got: rvalue.type.rawValue
                    ),
                    at: rhs.range
                )
            }
            switch op {
            case .minus:
                return .number(lnum - rnum)
            case .plus:
                return .number(lnum + rnum)
            case .times:
                return .number(lnum * rnum)
            case .divide:
                return .number(lnum / rnum)
            }
        case let .member(expression, member):
            let value = try expression.evaluate(in: context)
            if let value = value[member.name] {
                return value
            }
            throw RuntimeError(
                .unknownSymbol(member.name, options: value.members),
                at: member.range
            )
        case let .subexpression(expression):
            return try expression.evaluate(in: context)
        }
    }
}
