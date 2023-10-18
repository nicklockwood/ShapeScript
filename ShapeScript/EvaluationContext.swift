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

    public func range(in source: String) -> SourceRange {
        source.range(ofLine: line)
    }
}

final class EvaluationContext {
    private final class ImportCache {
        var store = [URL: Program]()
    }

    private weak var delegate: EvaluationDelegate?
    private var symbols: Symbols = .root
    var userSymbols: Symbols = [:]
    var options: Options = [:]
    private let importCache: ImportCache
    private var importStack: [URL]
    let isCancelled: Mesh.CancellationHandler

    var source: String
    var sourceIndex: String.Index?
    var baseURL: URL?

    var material: Material = .default
    var background: MaterialProperty?
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

    var sourceLocation: () -> SourceLocation? {
        { [sourceIndex, source, baseURL] in
            sourceIndex.map {
                SourceLocation(at: source.line(at: $0), in: baseURL)
            }
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
        self.importCache = ImportCache()
        self.importStack = []
        self.random = RandomSequence(seed: 0)
    }

    private init(parent: EvaluationContext) {
        // preserve
        self.source = parent.source
        self.sourceIndex = parent.sourceIndex
        self.baseURL = parent.baseURL
        self.delegate = parent.delegate
        self.isCancelled = parent.isCancelled
        self.symbols = parent.symbols
        self.userSymbols = parent.userSymbols
        self.importCache = parent.importCache
        self.importStack = parent.importStack
        self.material = parent.material
        self.childTypes = parent.childTypes
        self.namedObjects = parent.namedObjects
        self.random = parent.random
        self.detail = parent.detail
        self.smoothing = parent.smoothing
        self.font = parent.font
        // root-only
        self.background = parent.background
        // opacity is cumulative
        self.opacity = parent.material.opacity
        // reset
        self.transform = .identity
        self.childTransform = .identity
        self.children = []
        // stack
        self.stackDepth = parent.stackDepth + 1
    }

    func push(_ type: BlockType) -> EvaluationContext {
        let new = EvaluationContext(parent: self)
        new.childTypes = type.childTypes
        new.symbols = type.symbols
        new.options = type.options
        for (name, symbol) in type.symbols where Symbols.global[name] == nil {
            if case .placeholder = symbol {
                continue
            }
            new.userSymbols[name] = nil
        }
        return new
    }

    func pushScope(_ block: (EvaluationContext) throws -> Void) rethrows {
        let oldSourceIndex = sourceIndex
        let oldSymbols = userSymbols
        defer {
            sourceIndex = oldSourceIndex
            userSymbols = oldSymbols.merging(userSymbols.filter {
                if case .option = $0.value, options[$0.key] != nil {
                    return true
                }
                return false
            }) { $1 }
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
        if let symbol = userSymbols[name] ?? symbols[name] ?? Symbols.global[name] {
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

    var allSymbols: Symbols {
        Symbols.global.merging(symbols) { $1 }.merging(userSymbols) { $1 }
    }

    /// Symbols that can be used in an expression (i.e. that return a value)
    var expressionSymbols: [String] {
        Array(allSymbols.filter {
            switch $1 {
            case let .function(type, _) where type.returnType == .void:
                return false
            case .function, .property, .block, .constant, .option, .placeholder:
                return true
            }
        }.keys)
    }

    /// Symbols that can be used as a command (i.e. that accept an argument)
    var commandSymbols: [String] {
        Array(allSymbols.filter {
            switch $1 {
            case .function, .property, .block, .placeholder:
                return true
            case .constant, .option:
                return false
            }
        }.keys) + Keyword.allCases.map { $0.rawValue }
    }

    /// Return the value of the specified symbol in the current context
    func value(for name: String) -> Value? {
        switch symbol(for: name) {
        case let .constant(value), let .option(value):
            return value
        case .function, .property, .block, .placeholder, nil:
            return nil
        }
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
    private func isUndownloadedUbiquitousFile(_ url: URL) -> Bool {
        #if os(macOS) || os(iOS)
        return (try? url.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey,
        ]).ubiquitousItemDownloadingStatus) == .notDownloaded
        #else
        return false
        #endif
    }

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
        let fileManager = FileManager.default
//        try? fileManager.evictUbiquitousItem(at: url) // Handy for testing
        // TODO: move this logic out of EvaluationContext into delegate
        // so we can more easily mock the filesystem for testing purposes
        let isRemote = isUndownloadedUbiquitousFile(url)
        #if os(macOS)
        // macOS can check for existence of files even without access permission
        guard isRemote || fileManager.fileExists(atPath: url.path) else {
            throw RuntimeErrorType.fileNotFound(for: path, at: url)
        }
        #endif
        let directory = url.deletingLastPathComponent()
        guard isRemote || fileManager.isReadableFile(atPath: url.path) ||
            fileManager.isReadableFile(atPath: directory.path)
        else {
            throw RuntimeErrorType.fileAccessRestricted(for: path, at: directory)
        }
        guard isRemote || fileManager.fileExists(atPath: url.path) else {
            throw RuntimeErrorType.fileNotFound(for: path, at: url)
        }
        #if os(macOS) || os(iOS)
        // TODO: Make this interface asynchronous instead of blocking
        if isRemote {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            var url = url
            let start = CFAbsoluteTimeGetCurrent()
            let timeout: TimeInterval = 30
            while isUndownloadedUbiquitousFile(url), !isCancelled() {
                if CFAbsoluteTimeGetCurrent() - start > timeout {
                    throw RuntimeErrorType.fileTimedOut(for: path, at: url)
                }
                Thread.sleep(forTimeInterval: 0.1)
                url.removeAllCachedResourceValues()
            }
        }
        #endif
        return url
    }

    func resolveFont(_ name: String) throws -> String {
        let name = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        #if canImport(CoreGraphics) && canImport(CoreText)
        guard [".otf", ".ttf", ".ttc"].contains(where: {
            name.lowercased().hasSuffix($0)
        }) else {
            guard CGFont(name as CFString) != nil else {
                var options = [String]()
                options += CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
                options += CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
                // TODO: Work around silly race condition where font may have
                // been imported by another file in the meantime
                throw RuntimeErrorType.unknownFont(name, options: options)
            }
            return name
        }
        let url = try resolveURL(for: name)
        guard let dataProvider = CGDataProvider(url: url as CFURL) else {
            throw RuntimeErrorType.fileNotFound(for: name, at: url)
        }
        guard let cgFont = CGFont(dataProvider),
              CTFontManagerRegisterGraphicsFont(cgFont, nil)
        else {
            throw RuntimeErrorType.fileParsingError(for: name, at: url, message: "")
        }
        return cgFont.fullName as String? ?? ""
        #else
        return name
        #endif
    }

    func importFile(at path: String) throws -> Value {
        let url = try resolveURL(for: path)
        if importStack.contains(url) {
            throw RuntimeErrorType.circularImport(for: url)
        }
        switch url.pathExtension.lowercased() {
        case "shape":
            let program: Program
            if let entry = importCache.store[url] {
                program = entry
            } else {
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
                    throw RuntimeErrorType.importError(
                        ProgramError(error),
                        for: url,
                        in: source
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
                return .void
            } catch {
                throw RuntimeErrorType.importError(
                    ProgramError(error),
                    for: url,
                    in: program.source
                )
            }
        case "txt":
            do {
                return try .string(String(contentsOf: url))
            } catch {
                throw RuntimeErrorType.fileParsingError(
                    for: path,
                    at: url,
                    message: error.localizedDescription
                )
            }
        case "json":
            do {
                return try Value(jsonData: Data(contentsOf: url))
            } catch let error as ParserError {
                let source = try String(contentsOf: url)
                throw RuntimeErrorType.importError(
                    .parserError(error),
                    for: url,
                    in: source
                )
            } catch {
                throw RuntimeErrorType.fileParsingError(
                    for: path,
                    at: url,
                    message: error.localizedDescription
                )
            }
        default:
            do {
                if let geometry = try delegate?.importGeometry(for: url)?.with(
                    transform: childTransform,
                    material: material,
                    sourceLocation: sourceLocation
                ) {
                    return .mesh(geometry)
                }
            } catch let error as ProgramError {
                guard let source = try? String(contentsOf: url) else {
                    throw RuntimeErrorType.fileParsingError(
                        for: path, at: url, message: error.message
                    )
                }
                throw RuntimeErrorType.importError(error, for: url, in: source)
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
}
