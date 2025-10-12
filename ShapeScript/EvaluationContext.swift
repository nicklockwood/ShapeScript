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

#if canImport(SceneKit)
import SceneKit
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
        enum Import {
            case program(Program)
            case geometry(Geometry)
            case value(Value)
        }

        var fonts: [String] {
            store.values.compactMap {
                switch $0 {
                case let .value(.font(name)): name
                default: nil
                }
            }
        }

        var store = [URL: Import]()
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
    var detail: Int = 16
    var smoothing: Angle?
    var font: String = ""
    var opacity: Double = 1

    var stackDepth = 1
    var isFunctionScope = false

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
        self.opacity = parent.material.opacity?.color?.a ?? parent.opacity
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
    static let altNames = ["colour": "color", "centre": "center", "grey": "gray"]

    func symbol(for name: String) -> Symbol? {
        if let symbol = userSymbols[name] ?? symbols[name] ?? Symbols.global[name] {
            return symbol
        }
        if let name = Self.altNames[name] {
            return symbol(for: name)
        }
        return nil
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
        }.keys) + Keyword.allCases.map(\.rawValue)
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
        #if targetEnvironment(simulator) || !os(iOS)
        // macOS/Linux/Windows can check for existence of files even without access permission
        guard isRemote || fileManager.fileExists(atPath: url.path) else {
            throw RuntimeErrorType.fileNotFound(for: path, at: url)
        }
        #endif
        let directory = url.deletingLastPathComponent()
        guard isRemote || fileManager.isReadableFile(atPath: url.path) else {
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

    var fontNames: [String] {
        var options = [String]()
        #if canImport(CoreGraphics) && canImport(CoreText)
        options += CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []
        options += CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        options = options.map { CGFont($0 as CFString)?.fullName as String? ?? $0 } + importCache.fonts
        #endif
        return Array(Set(options)).sorted()
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
            if importCache.fonts.contains(name) {
                return name
            }
            let font = CTFontCreateWithName(name as CFString, 1, nil)
            let fullName = CTFontCopyFullName(font) as String
            // CTFontCreateWithName always returns a value even for an empty string
            // so use a basic heuristic to make sure we got the font that we requested
            let lowercasedFullName = fullName.lowercased()
            let lowercasedName = name.lowercased()
            guard lowercasedFullName == lowercasedName ||
                lowercasedFullName.hasPrefix("\(lowercasedName) ")
            else {
                throw RuntimeErrorType.unknownFont(name, options: fontNames)
            }
            return fullName
        }
        let url = try resolveURL(for: name)
        if case let .value(.font(fullName)) = importCache.store[url] {
            return fullName
        }
        guard let dataProvider = CGDataProvider(url: url as CFURL) else {
            throw RuntimeErrorType.fileNotFound(for: name, at: url)
        }
        guard let cgFont = CGFont(dataProvider), let fullName = cgFont.fullName as? String,
              CGFont(fullName as CFString) != nil || CTFontManagerRegisterGraphicsFont(cgFont, nil)
        else {
            throw RuntimeErrorType.fileParsingError(for: name, at: url, message: "")
        }
        importCache.store[url] = .value(.font(fullName))
        return fullName
        #else
        return name
        #endif
    }

    func importGeometry(at url: URL) throws -> Geometry? {
        if let geometry = try delegate?.importGeometry(for: url) {
            // Allow delegate to implement alternative loading mechanism, e.g. hard-coded geometry for testing
            return geometry
        }
        switch url.pathExtension.lowercased() {
        case "stl", "stla", "obj", "off":
            let mesh = try Mesh(url: url) {
                switch $0 {
                case let color as Color:
                    return Material(color: color)
                #if canImport(SceneKit)
                case let scnMaterial as SCNMaterial:
                    return Material(scnMaterial)
                #endif
                default:
                    return nil
                }
            }
            return Geometry(
                type: .mesh(mesh),
                name: nil,
                transform: .identity,
                material: .default,
                smoothing: nil,
                children: [],
                sourceLocation: nil
            )
        default:
            break
        }
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        var url = url
        if isDirectory.boolValue {
            let newURL = url.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: newURL.path) {
                url = newURL
            }
        }
        #if canImport(SceneKit)
        let scene = try SCNScene(url: url, options: [
            .flattenScene: false,
            .createNormalsIfAbsent: true,
            .convertToYUp: true,
            .preserveOriginalTopology: true,
        ])
        return try Geometry(scene.rootNode)
        #else
        return nil
        #endif
    }

    func importFile(at path: String) throws -> Value {
        let url = try resolveURL(for: path)
        switch url.pathExtension.lowercased() {
        case "shape":
            if importStack.contains(url) {
                throw RuntimeErrorType.circularImport(for: url)
            }
            let program: Program
            if case let .program(entry) = importCache.store[url] {
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
                    program = try parse(source, at: url)
                    importCache.store[url] = .program(program)
                } catch {
                    throw RuntimeErrorType.importError(
                        ProgramError(error),
                        for: url,
                        in: source
                    )
                }
            }
            importStack.append(url)
            defer {
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
            if case let .value(value) = importCache.store[url] {
                return value
            }
            do {
                let value = try Value.string(String(contentsOf: url))
                importCache.store[url] = .value(value)
                return value
            } catch {
                throw RuntimeErrorType.fileParsingError(
                    for: path,
                    at: url,
                    message: error.localizedDescription
                )
            }
        case "json":
            if case let .value(value) = importCache.store[url] {
                return value
            }
            do {
                let value = try Value(jsonData: Data(contentsOf: url))
                importCache.store[url] = .value(value)
                return value
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
                let geometry: Geometry
                if case let .geometry(entry) = importCache.store[url] {
                    geometry = entry
                } else if let entry = try importGeometry(at: url) {
                    geometry = entry
                    importCache.store[url] = .geometry(geometry)
                } else {
                    throw RuntimeErrorType.fileTypeMismatch(
                        for: path,
                        at: url,
                        expected: nil
                    )
                }
                return .mesh(geometry.with(
                    transform: .identity,
                    material: material,
                    smoothing: smoothing,
                    sourceLocation: sourceLocation
                ))
            } catch let error as ProgramError {
                guard let source = try? String(contentsOf: url) else {
                    throw RuntimeErrorType.fileParsingError(
                        for: path, at: url, message: error.message
                    )
                }
                throw RuntimeErrorType.importError(error, for: url, in: source)
            } catch {
                throw RuntimeErrorType.fileError(error, for: path, at: url)
            }
        }
    }
}
