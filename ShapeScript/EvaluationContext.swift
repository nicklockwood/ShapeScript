//
//  EvaluationContext.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 18/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(CoreText)
import CoreText
#endif

// MARK: Implementation

public struct SourceLocation: Hashable {
    public let line: Int
    public let file: URL?

    public init(at line: Int, in file: URL?) {
        self.line = line
        self.file = file
    }
}

final class EvaluationContext {
    private final class ImportCache {
        var store = [URL: Program]()
    }

    private weak var delegate: EvaluationDelegate?
    private var symbols = Symbols.root
    var userSymbols = Symbols()
    private let importCache: ImportCache
    private var importStack: [URL]
    private let linebreakIndices: [String.Index]
    let isCancelled: () -> Bool

    var source: String
    var sourceIndex: String.Index?
    var baseURL: URL?

    var material: Material = .default
    var background: MaterialProperty? {
        get { value(for: #function)?.colorOrTextureValue }
        set { define(#function, as: newValue.map {
            .constant(.colorOrTexture($0))
        }) }
    }

    var transform = Transform.identity
    var childTransform = Transform.identity
    var childTypes: ValueType = .mesh
    var name: String = ""
    var namedObjects: [String: Geometry] = [:]
    var children = [Value]() {
        didSet {
            for case let .mesh(geometry) in children {
                geometry.gatherNamedObjects(&namedObjects)
            }
        }
    }

    var random: RandomSequence
    var detail = 16
    var smoothing: Angle?
    var font: String = ""
    var opacity = 1.0

    var stackDepth = 1

    var sourceLocation: SourceLocation? {
        sourceIndex.map {
            SourceLocation(
                at: source.lineAndColumn(
                    at: $0,
                    withLinebreakIndices: linebreakIndices
                ).line,
                in: baseURL
            )
        }
    }

    init(
        source: String,
        delegate: EvaluationDelegate?,
        isCancelled: @escaping () -> Bool = { false }
    ) {
        self.source = source
        self.delegate = delegate
        self.isCancelled = isCancelled
        importCache = ImportCache()
        importStack = []
        random = RandomSequence(seed: 0)
        linebreakIndices = source.linebreakIndices
    }

    private init(parent: EvaluationContext) {
        // preserve
        source = parent.source
        linebreakIndices = parent.linebreakIndices
        sourceIndex = parent.sourceIndex
        baseURL = parent.baseURL
        delegate = parent.delegate
        isCancelled = parent.isCancelled
        symbols = parent.symbols
        userSymbols = parent.userSymbols
        importCache = parent.importCache
        importStack = parent.importStack
        material = parent.material
        childTypes = parent.childTypes
        namedObjects = parent.namedObjects
        random = parent.random
        detail = parent.detail
        smoothing = parent.smoothing
        font = parent.font
        // opacity is cumulative
        opacity = parent.material.opacity
        // reset
        transform = .identity
        childTransform = .identity
        children = []
        // stack
        stackDepth = parent.stackDepth + 1
    }

    func push(_ type: BlockType) -> EvaluationContext {
        let new = EvaluationContext(parent: self)
        new.childTypes = type.childTypes
        new.symbols = Symbols.global.merging(type.symbols) { $1 }
        for name in type.symbols.keys {
            new.userSymbols[name] = nil
        }
        return new
    }

    func pushScope(_ block: (EvaluationContext) throws -> Void) rethrows {
        let oldSourceIndex = sourceIndex
        let oldSymbols = userSymbols
        defer {
            sourceIndex = oldSourceIndex
            userSymbols = oldSymbols
        }
        try block(self)
    }

    func pushDefinition() -> EvaluationContext {
        let new = EvaluationContext(parent: self)
        new.name = name
        new.namedObjects = namedObjects
        new.transform = transform
        new.opacity = opacity
        new.childTypes = ValueType.any
        new.symbols = .definition
        return new
    }
}

extension EvaluationContext {
    func symbol(for name: String) -> Symbol? {
        if let symbol = userSymbols[name] ?? symbols[name] {
            return symbol
        }
        switch name {
        case "colour":
            return symbol(for: "color")
        default:
            return nil
        }
    }

    func define(_ name: String, as symbol: Symbol?) {
        userSymbols[name] = symbol
    }

    var expressionSymbols: [String] {
        Array(symbols.merging(userSymbols) { $1 }.filter {
            switch $1 {
            case let .function(type, _) where type.returnType == .void:
                return false
            case .function, .property, .block, .constant, .placeholder:
                return true
            }
        }.keys)
    }

    var commandSymbols: [String] {
        Array(symbols.merging(userSymbols) { $1 }.filter {
            switch $1 {
            case .function, .property, .block:
                return true
            case .constant, .placeholder:
                return false
            }
        }.keys) + Keyword.allCases.map { $0.rawValue }
    }

    func value(for name: String) -> Value? {
        if case let .constant(value)? = symbol(for: name) {
            return value
        }
        return nil
    }
}

// MARK: Debugging

extension EvaluationContext {
    func debugLog(_ values: [AnyHashable]) {
        delegate?.debugLog(values)
    }
}

// MARK: External file access

extension EvaluationContext {
    func resolveURL(for path: String) throws -> URL {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            // TODO: should this be a different error type, like "empty path not allowed"?
            throw RuntimeErrorType.fileNotFound(for: path, at: nil)
        }
        let documentRelativePath = baseURL.map {
            URL(fileURLWithPath: path, relativeTo: $0).path
        } ?? path
        guard let url = delegate?.resolveURL(for: documentRelativePath) else {
            // TODO: should this be a different error type, like "delegate not available"?
            throw RuntimeErrorType.fileNotFound(for: path, at: nil)
        }
        // TODO: move this logic out of EvaluationContext into delegate
        // so we can more easily mock the filesystem for testing purposes
        #if os(macOS)
        // macOS can check for existence of files even without access permission
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RuntimeErrorType.fileNotFound(for: path, at: url)
        }
        #endif
        let directory = url.deletingLastPathComponent()
        guard FileManager.default.isReadableFile(atPath: url.path) ||
            FileManager.default.isReadableFile(atPath: directory.path)
        else {
            throw RuntimeErrorType.fileAccessRestricted(for: path, at: directory)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RuntimeErrorType.fileNotFound(for: path, at: url)
        }
        return url
    }

    func resolveFont(_ name: String) throws -> String {
        let name = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        #if canImport(CoreGraphics)
        guard [".otf", ".ttf", ".ttc"].contains(where: {
            name.lowercased().hasSuffix($0)
        }) else {
            guard let cgFont = CGFont(name as CFString) else {
                var options = [String]()
                #if canImport(CoreText)
                options += CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
                options += CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
                #endif
                // TODO: Work around silly race condition where font may have
                // been imported by another file in the meantime
                throw RuntimeErrorType.unknownFont(name, options: options)
            }
            return cgFont.postScriptName as String? ?? name
        }
        let url = try resolveURL(for: name)
        guard let dataProvider = CGDataProvider(url: url as CFURL) else {
            throw RuntimeErrorType.fileNotFound(for: name, at: url)
        }
        #if canImport(CoreText)
        guard let cgFont = CGFont(dataProvider),
              CTFontManagerRegisterGraphicsFont(cgFont, nil)
        else {
            throw RuntimeErrorType.fileParsingError(for: name, at: url, message: "")
        }
        return cgFont.postScriptName as String? ?? name
        #endif
        #else
        return name
        #endif
    }

    func importFile(at path: String) throws {
        let url = try resolveURL(for: path)
        if importStack.contains(url) {
            throw RuntimeErrorType.assertionFailure("Files cannot import themselves")
        }
        let program: Program
        if let entry = importCache.store[url] {
            program = entry
        } else {
            switch url.pathExtension.lowercased() {
            case "shape":
                let source: String
                do {
                    source = try String(contentsOf: url)
                } catch {
                    throw RuntimeErrorType.fileParsingError(
                        for: path,
                        at: url,
                        message: error.localizedDescription
                    )
                }
                do {
                    // TODO: async source loading?
                    program = try parse(source)
                    importCache.store[url] = program
                } catch {
                    throw RuntimeErrorType
                        .importError(ImportError(error), for: path, in: source)
                }
            default:
                do {
                    if let geometry = try delegate?.importGeometry(for: url)?.with(
                        transform: childTransform,
                        material: material,
                        sourceLocation: sourceLocation
                    ) {
                        children.append(.mesh(geometry))
                        return
                    }
                } catch let error as ImportError {
                    throw RuntimeErrorType.fileParsingError(
                        for: path, at: url, message: error.message
                    )
                } catch {
                    var error: Error? = error
                    while let nsError = error as NSError? {
                        if nsError.domain == NSCocoaErrorDomain, nsError.code == 259 {
                            // Not a recognized model file format
                            break
                        }
                        if let description = (
                            nsError.userInfo[NSLocalizedRecoverySuggestionErrorKey] ??
                                nsError.userInfo[NSLocalizedDescriptionKey]
                        ) as? String {
                            throw RuntimeErrorType.fileParsingError(
                                for: path, at: url, message: description
                            )
                        }
                        error = nsError.userInfo[NSUnderlyingErrorKey] as? Error
                    }
                }
                throw RuntimeErrorType.fileTypeMismatch(
                    for: path, at: url, expected: nil
                )
            }
        }
        let oldURL = baseURL
        baseURL = url
        importStack.append(url)
        defer {
            baseURL = oldURL
            importStack.removeLast()
        }
        do {
            try program.evaluate(in: self)
        } catch {
            throw RuntimeErrorType
                .importError(ImportError(error), for: path, in: program.source)
        }
    }
}
