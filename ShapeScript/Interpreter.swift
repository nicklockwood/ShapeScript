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

public let version = "1.4.5"

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
        background: context.background,
        children: context.children.compactMap { $0.value as? Geometry },
        cache: cache
    )
}

public enum ImportError: Error, Equatable {
    case lexerError(LexerError)
    case parserError(ParserError)
    case runtimeError(RuntimeError)
    case unknownError
}

public extension ImportError {
    init(_ error: Error) {
        switch error {
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
        default: return "Unknown error"
        }
    }

    var range: SourceRange {
        switch self {
        case let .lexerError(error): return error.range
        case let .parserError(error): return error.range
        case let .runtimeError(error): return error.range
        default: return "".startIndex ..< "".endIndex
        }
    }

    var hint: String? {
        switch self {
        case let .lexerError(error): return error.hint
        case let .parserError(error): return error.hint
        case let .runtimeError(error): return error.hint
        default: return nil
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
    indirect case importError(ImportError, for: String, in: String)
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
            if Keyword(rawValue: name) == nil, Symbols.all[name] == nil {
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
        default:
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
            var hint = Keyword(rawValue: name) == nil && Symbols.all[name] == nil ? "" :
                "The \(name) command is not available in this context."
            if let suggestion = suggestion {
                hint = (hint.isEmpty ? "" : "\(hint) ") + "Did you mean '\(suggestion)'?"
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

private extension RuntimeErrorType {
    static func typeMismatch(
        for symbol: String,
        index: Int,
        expected types: [String],
        got: String
    ) -> RuntimeErrorType {
        var types = Set(types).sorted()
        if let index = types.firstIndex(of: "block") {
            types.append(types.remove(at: index))
        }
        let expected: String
        switch types.count {
        case 1:
            expected = types[0]
        case 2:
            expected = "\(types[0]) or \(types[1])"
        default:
            expected = "\(types.dropLast().joined(separator: ", ")), or \(types.last!)"
        }
        return .typeMismatch(for: symbol, index: index, expected: expected, got: got)
    }
}

enum ValueType: CaseIterable {
    case color
    case texture
    case boolean
    case colorOrTexture // Hack to support either types
    case font
    case number
    case vector
    case size
    case rotation
    case string
    case text
    case path
    case paths // Hack to support multiple paths
    case mesh
    case tuple
    case point
    case pair // Hack to support common math functions
    case range
    case void
    case bounds
}

extension ValueType {
    static let any = Set(Self.allCases)

    var errorDescription: String {
        switch self {
        case .color: return "color"
        case .texture: return "texture"
        case .colorOrTexture: return "color or texture"
        case .font: return "font"
        case .boolean: return "boolean"
        case .number: return "number"
        case .vector: return "vector"
        case .size: return "size"
        case .rotation: return "rotation"
        case .string: return "text"
        case .text: return "text"
        case .path: return "path"
        case .paths: return "path"
        case .mesh: return "mesh"
        case .tuple: return "tuple"
        case .point: return "point"
        case .pair: return "pair"
        case .range: return "range"
        case .void: return "void"
        case .bounds: return "bounds"
        }
    }
}

enum Value {
    case color(Color)
    case texture(Texture?)
    case boolean(Bool)
    case number(Double)
    case vector(Vector)
    case size(Vector)
    case rotation(Rotation)
    case string(String)
    case text(TextValue)
    case path(Path)
    case mesh(Geometry)
    case point(PathPoint)
    case tuple([Value])
    case range(RangeValue)
    case bounds(Bounds)

    static let void: Value = .tuple([])

    static func colorOrTexture(_ value: MaterialProperty) -> Value {
        switch value {
        case let .color(color):
            return .color(color)
        case let .texture(texture):
            return .texture(texture)
        }
    }

    var value: AnyHashable {
        switch self {
        case let .color(color): return color
        case let .texture(texture):
            return texture.map { $0 as AnyHashable } ?? texture as AnyHashable
        case let .boolean(boolean): return boolean
        case let .number(number): return number
        case let .vector(vector): return vector
        case let .size(size): return size
        case let .rotation(rotation): return rotation
        case let .string(string): return string
        case let .text(text): return text
        case let .path(path): return path
        case let .mesh(mesh): return mesh
        case let .point(point): return point
        case let .tuple(values) where values.count == 1: return values[0].value
        case let .tuple(values): return values.map { $0.value }
        case let .range(range): return range
        case let .bounds(bounds): return bounds
        }
    }

    var doubleValue: Double {
        assert(value is Double)
        return value as? Double ?? 0
    }

    var intValue: Int {
        Int(truncating: doubleValue as NSNumber)
    }

    var boolValue: Bool {
        assert(value is Bool)
        return value as? Bool ?? false
    }

    var stringValue: String {
        switch self {
        case let .tuple(values):
            var spaceNeeded = false
            return values.map {
                switch $0 {
                case let .string(string):
                    spaceNeeded = false
                    return string
                case let value:
                    defer { spaceNeeded = true }
                    let string = value.stringValue
                    return spaceNeeded ? " \(string)" : string
                }
            }.joined()
        default:
            return (value as? Loggable)?.logDescription ?? ""
        }
    }

    var textValue: TextValue {
        switch self {
        case let .text(text):
            return text
        default:
            return TextValue(
                string: stringValue,
                font: nil,
                color: nil,
                linespacing: nil
            )
        }
    }

    var tupleValue: [AnyHashable] {
        if case let .tuple(values) = self {
            return values.map { $0.value }
        }
        return [value]
    }

    var type: ValueType {
        switch self {
        case .color: return .color
        case .texture: return .texture
        case .boolean: return .boolean
        case .number: return .number
        case .vector: return .vector
        case .size: return .size
        case .rotation: return .rotation
        case .string: return .string
        case .text: return .text
        case .path: return .path
        case .mesh: return .mesh
        case .point: return .point
        case let .tuple(values) where values.count == 1:
            // TODO: find better solution for this.
            return values[0].type
        case .tuple: return .tuple
        case .range: return .range
        case .bounds: return .bounds
        }
    }

    func isConvertible(to type: ValueType) -> Bool {
        switch (self, type) {
        case (.boolean, .string),
             (.boolean, .text),
             (.number, .string),
             (.number, .text),
             (.number, .color),
             (.string, .text):
            return true
        case let (.tuple(values), .string):
            return values.allSatisfy { $0.isConvertible(to: .string) }
        case let (.tuple(values), .text):
            return values.allSatisfy { $0.isConvertible(to: .text) }
        case let (.tuple(values), .color):
            if values.count == 1 {
                return values[0].isConvertible(to: .color)
            }
            return values.allSatisfy { $0.type == .number }
        default:
            return self.type == type
        }
    }

    var members: [String] {
        switch self {
        case .vector, .point:
            return ["x", "y", "z"]
        case .size:
            return ["width", "height", "depth"]
        case .rotation:
            return ["roll", "yaw", "pitch"]
        case .color:
            return ["red", "green", "blue", "alpha"]
        case let .tuple(values):
            var members = Array(String.ordinals(upTo: values.count))
            guard values.allSatisfy({ $0.type == .number }) else {
                guard values.allSatisfy({ $0.type == .path }) else {
                    if values.count == 1 {
                        members += values[0].members
                    }
                    return members
                }
                return members + ["bounds"]
            }
            if values.count < 5 {
                members += ["red", "green", "blue", "alpha"]
                if values.count < 4 {
                    members += [
                        "x", "y", "z",
                        "width", "height", "depth",
                        "roll", "yaw", "pitch",
                    ]
                }
            }
            return members
        case .range:
            return ["start", "end", "step"]
        case .path, .mesh:
            return ["bounds"]
        case .bounds:
            return ["min", "max", "size", "center", "width", "height", "depth"]
        case .text:
            return ["color", "font"]
        case .texture, .boolean, .number, .string:
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
        case let .point(point):
            return Value.vector(point.position)[name]
        case let .size(size):
            switch name {
            case "width": return .number(size.x)
            case "height": return .number(size.y)
            case "depth": return .number(size.z)
            default: return nil
            }
        case let .rotation(rotation):
            switch name {
            case "roll": return .number(rotation.roll.radians / .pi)
            case "yaw": return .number(rotation.yaw.radians / .pi)
            case "pitch": return .number(rotation.pitch.radians / .pi)
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
            if let index = name.ordinalIndex {
                return index < values.count ? values[index] : nil
            }
            guard values.allSatisfy({ $0.type == .number }) else {
                guard values.allSatisfy({ $0.type == .path }) else {
                    if values.count == 1 {
                        return values[0][name]
                    }
                    return nil
                }
                let values = values.compactMap { $0.value as? Path }
                switch name {
                case "bounds":
                    return .bounds(values.bounds)
                default:
                    return nil
                }
            }
            let values = values.map { $0.doubleValue }
            switch name {
            case "x", "y", "z":
                return values.count < 4 ? Value.vector(Vector(values))[name] : nil
            case "width", "height", "depth":
                return values.count < 4 ? Value.size(Vector(size: values))[name] : nil
            case "roll", "yaw", "pitch":
                return Rotation(rollYawPitchInHalfTurns: values).map(Value.rotation)?[name]
            case "red", "green", "blue", "alpha":
                return Color(values).map(Value.color)?[name]
            default:
                return nil
            }
        case let .range(range):
            switch name {
            case "start": return .number(range.start)
            case "end": return .number(range.end)
            case "step": return .number(range.step)
            default: return nil
            }
        case let .path(path):
            switch name {
            case "bounds": return .bounds(path.bounds)
            default: return nil
            }
        case let .mesh(mesh):
            switch name {
            case "bounds": return .bounds(mesh.bounds)
            default: return nil
            }
        case let .bounds(bounds):
            switch name {
            case "min": return .vector(bounds.min)
            case "max": return .vector(bounds.max)
            case "size": return .size(bounds.size)
            case "center": return .vector(bounds.center)
            case "width": return .number(bounds.size.x)
            case "height": return .number(bounds.size.y)
            case "depth": return .number(bounds.size.z)
            default: return nil
            }
        case let .text(text):
            switch name {
            case "color": return .color(text.color ?? .white)
            case "font": return .string(text.font ?? "")
            default: return nil
            }
        case .boolean, .texture, .number, .string:
            return nil
        }
    }
}

struct RangeValue: Hashable, Sequence {
    var start, end, step: Double

    init(from start: Double, to end: Double) {
        self.init(from: start, to: end, step: 1)!
    }

    init?(from start: Double, to end: Double, step: Double) {
        guard step != 0 else {
            return nil
        }
        self.start = start
        self.end = end
        self.step = step
    }

    func makeIterator() -> StrideThrough<Double>.Iterator {
        stride(from: start, through: end, by: step).makeIterator()
    }
}

struct TextValue: Hashable {
    var string: String
    var font: String?
    var color: Color?
    var linespacing: Double?
}

typealias Options = [String: ValueType]

enum BlockType {
    case builder
    case shape
    case group
    case path
    case pathShape
    case text
    indirect case custom(BlockType?, Options)

    var options: Options {
        switch self {
        case let .custom(baseType, options):
            return (baseType?.options ?? [:]).merging(options) { $1 }
        case .text:
            return [
                "wrapwidth": .number,
                "linespacing": .number,
            ]
        case .builder, .group, .path, .shape, .pathShape:
            return [:]
        }
    }

    var childTypes: Set<ValueType> {
        switch self {
        case .builder: return [.path]
        case .group: return [.mesh]
        case .path: return [.point, .path]
        case .text: return [.text]
        case .shape, .pathShape: return []
        case let .custom(baseType, _):
            return baseType?.childTypes ?? []
        }
    }

    var symbols: Symbols {
        switch self {
        case .shape: return .shape
        case .group: return .group
        case .builder: return .builder
        case .path: return .path
        case .pathShape: return .pathShape
        case .text: return .text
        case let .custom(baseType, _):
            return baseType?.symbols ?? .node
        }
    }
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
        if i < parameters.count - 1, case let .identifier(name) = param.type {
            switch context.symbol(for: name) {
            case let .command(parameterType, fn)? where parameterType != .void:
                let identifier = Identifier(name: name, range: param.range)
                let range = parameters[i + 1].range.lowerBound ..< parameters.last!.range.upperBound
                let param = Expression(type: .tuple(Array(parameters[(i + 1)...])), range: range)
                let arg = try evaluateParameter(param, as: parameterType, for: identifier, in: context)
                try RuntimeError.wrap(values.append(fn(arg, context)), at: range)
                break loop
            case let .block(type, fn) where !type.childTypes.isEmpty:
                let childContext = context.push(type)
                let children = try evaluateParameters(Array(parameters[(i + 1)...]), in: context)
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
                                for: name,
                                index: j,
                                expected: types,
                                got: child.type.errorDescription
                            ),
                            at: parameters[i + 1 + j].range
                        )
                    }
                }
                try RuntimeError.wrap(values.append(fn(childContext)), at: param.range)
                break loop
            default:
                break
            }
        }
        try values.append(param.evaluate(in: context))
    }
    return values
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
            .missingArgument(for: name, index: 0, type: type.errorDescription),
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
            return .block(.custom(nil, options)) { _context in
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
                    context.transform = _context.transform
                    context.opacity = _context.opacity
                    context.detail = _context.detail
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
                        children: try children.map {
                            switch $0 {
                            case let .path(path):
                                return Geometry(
                                    type: .path(path),
                                    name: nil,
                                    transform: .identity,
                                    material: .default,
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
                        ImportError(error),
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
                    font: font,
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
                children: [],
                sourceLocation: sourceLocation
            )))
        case let .tuple(values):
            try values.forEach(addValue)
        default:
            throw RuntimeErrorType.unusedValue(type: value.type.errorDescription)
        }
    }
}

extension Statement {
    func evaluate(in context: EvaluationContext) throws {
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
                try RuntimeError.wrap(context.addValue(fn(argument, context)), at: range)
            case let .property(type, setter, _):
                let argument = try evaluateParameter(parameter,
                                                     as: type,
                                                     for: identifier,
                                                     in: context)
                try RuntimeError.wrap(setter(argument, context), at: range)
            case let .block(type, fn):
                context.sourceIndex = range.lowerBound
                if let parameter = parameter {
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
                    let parameters: [Expression]
                    if case let .tuple(expressions) = parameter.type {
                        parameters = expressions
                    } else {
                        parameters = [parameter]
                    }
                    var children = try evaluateParameters(
                        parameters,
                        in: context
                    ).map(unwrap)
                    if children.count == 1, case let .tuple(values) = children[0] {
                        children = values
                    }
                    for child in children where !type.childTypes
                        .contains(where: child.isConvertible)
                    {
                        // TODO: can we highlight specific argument?
                        throw RuntimeError(.typeMismatch(
                            for: name,
                            index: 0,
                            expected: type.childTypes.map { $0.errorDescription } + ["block"],
                            got: child.type.errorDescription
                        ), at: parameter.range)
                    }
                    try RuntimeError.wrap({
                        let childContext = context.push(type)
                        childContext.userSymbols.removeAll()
                        try children.forEach(childContext.addValue)
                        try context.addValue(fn(childContext))
                    }(), at: range)
                } else if !type.childTypes.isEmpty {
                    throw RuntimeError(
                        .missingArgument(for: name, index: 0, type: "block"),
                        at: range
                    )
                } else {
                    let childContext = context.push(type)
                    childContext.userSymbols.removeAll()
                    try RuntimeError.wrap(context.addValue(fn(childContext)), at: range)
                }
            case let .constant(v):
                try RuntimeError.wrap(context.addValue(v), at: range)
            }
        case let .block(identifier, block):
            // TODO: better solution
            // This only works correctly if node was not imported from another file
            context.sourceIndex = range.lowerBound
            let expression = Expression(type: .block(identifier, block), range: range)
            try RuntimeError.wrap(context.addValue(expression.evaluate(in: context)), at: range)
        case let .expression(expression):
            try RuntimeError.wrap(context.addValue(expression.evaluate(in: context)), at: range)
        case let .define(identifier, definition):
            context.define(identifier.name, as: try definition.evaluate(in: context))
        case .option:
            throw RuntimeError(.unknownSymbol("option", options: []), at: range)
        case let .forloop(identifier, in: expression, block):
            let value = try expression.evaluate(in: context)
            let sequence: AnySequence<Value>
            switch value {
            case let .range(range):
                sequence = AnySequence(range.lazy.map { .number($0) })
            case let .tuple(values):
                // TODO: find less hacky way to do this unwrap
                if values.count == 1, case let .range(range) = values[0] {
                    sequence = AnySequence(range.lazy.map { .number($0) })
                } else {
                    sequence = AnySequence(values)
                }
            case .boolean, .vector, .size, .rotation, .color, .texture,
                 .number, .string, .text, .path, .mesh, .point, .bounds:
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
                    for statement in block.statements {
                        try statement.evaluate(in: context)
                    }
                }
            }
        case let .ifelse(condition, body, else: elseBody):
            let value = try condition.evaluate(as: .boolean, for: "condition", index: 0, in: context)
            try context.pushScope { context in
                if value.boolValue {
                    for statement in body.statements {
                        try statement.evaluate(in: context)
                    }
                } else if let elseBody = elseBody {
                    for statement in elseBody.statements {
                        try statement.evaluate(in: context)
                    }
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
            case let .command(parameterType, fn):
                guard parameterType == .void else {
                    // Commands with parameters can't be used in expressions without parens
                    // TODO: allow this if child matches next argument
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
                    // Blocks that require children can't be used in expressions without parens
                    // TODO: allow this if child matches next argument
                    throw RuntimeError(.missingArgument(
                        for: name,
                        index: 0,
                        type: "block"
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
                    case .block, .define, .forloop, .ifelse, .expression, .import:
                        try statement.evaluate(in: context)
                    case .option:
                        throw RuntimeError(.unknownSymbol("option", options: []), at: statement.range)
                    }
                }
                context.sourceIndex = sourceIndex
                return try RuntimeError.wrap(fn(context), at: range)
            case let .command(type, _):
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
            let lhs = try lhs.evaluate(as: .boolean, for: InfixOperator.and.rawValue, index: 0, in: context)
            let rhs = try rhs.evaluate(as: .boolean, for: InfixOperator.and.rawValue, index: 1, in: context)
            return .boolean(lhs.boolValue && rhs.boolValue)
        case let .infix(lhs, .or, rhs):
            let lhs = try lhs.evaluate(as: .boolean, for: InfixOperator.or.rawValue, index: 0, in: context)
            let rhs = try rhs.evaluate(as: .boolean, for: InfixOperator.or.rawValue, index: 1, in: context)
            return .boolean(lhs.boolValue || rhs.boolValue)
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
                    .missingArgument(for: name, index: min - 1, type: ValueType.number.errorDescription),
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
                            expected: (i == 0 ? type : .number).errorDescription,
                            got: value.type.errorDescription
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
                    type: type.errorDescription
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
                return .color((color.value as! Color).withAlpha(alpha.doubleValue))
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
            return .text(Value.tuple(values).textValue)
        case .texture where Value.tuple(values).isConvertible(to: .string):
            let name = Value.tuple(values).stringValue
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
                                expected: ValueType.path.errorDescription,
                                got: value.type.errorDescription
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
                            expected: ValueType.path.errorDescription,
                            got: value.type.errorDescription
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
                        expected: type.errorDescription,
                        got: value.type.errorDescription
                    ),
                    at: range
                )
            }
            // TODO: work out when/why this fallback is needed
            throw RuntimeError(
                .typeMismatch(
                    for: name,
                    index: index,
                    expected: type.errorDescription,
                    got: values[0].type.errorDescription
                ),
                at: parameters[0].range
            )
        case .void:
            throw RuntimeError(
                .unexpectedArgument(for: name, max: 0),
                at: parameters[0].range
            )
        }
    }
}
