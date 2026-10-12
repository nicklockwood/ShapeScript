//
//  CLI.swift
//  CLI
//
//  Created by Nick Lockwood on 13/04/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import ArgumentParser
import Euclid
import Foundation
import ShapeScript

#if canImport(SceneKit)
import SceneKit
#endif

struct CLIError: Error, CustomNSError, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorUserInfo: [String: Any] {
        if message.hasPrefix("Error") {
            return [NSLocalizedDescriptionKey: message]
        }
        return [NSLocalizedDescriptionKey: "Error: \(message)"]
    }

    var errorDescription: String? {
        if message.hasPrefix("Error: ") {
            return String(message.dropFirst("Error: ".count))
        }
        return message
    }
}

func printStatus(_ string: String) {
    FileHandle.standardError.write(Data("\(string)\n".utf8))
}

public struct ShapeScriptCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "shapescript",
        abstract: "Check, inspect, and export ShapeScript documents.",
        version: version.rawValue,
        subcommands: [Check.self, Info.self, Export.self]
    )

    public init() {}

    public mutating func run() throws {
        print("""
        ShapeScript, version \(version)
        Copyright (c) 2023-2026 Nick Lockwood

        """)
        print(Self.helpMessage())
    }
}

public extension ShapeScriptCommand {
    static func runCLI(_ arguments: [String] = Array(CommandLine.arguments.dropFirst())) {
        main(normalizedArguments(arguments))
    }

    static func normalizedArguments(_ arguments: [String]) -> [String] {
        guard let first = arguments.first, !knownCommandNames.contains(first) else {
            return arguments
        }
        if arguments.contains("--help") || arguments.contains("-h") || arguments.contains("--version") {
            return arguments
        }
        let valueOptions = exportValueOptions
        var positionals: [(index: Int, value: String)] = []
        var hasOutputOption = false
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            if argument == "--" {
                break
            }
            if argument == "--output" || argument == "-o" {
                hasOutputOption = true
            }
            if valueOptions.contains(argument) {
                index += 2
                continue
            } else if valueOptions.contains(where: { argument.hasPrefix("\($0)=") }) {
                hasOutputOption = hasOutputOption || argument.hasPrefix("--output=")
            } else if argument.hasPrefix("-") {
                index += 1
                continue
            } else {
                positionals.append((index, argument))
            }
            index += 1
        }
        guard !positionals.isEmpty || hasOutputOption, let input = positionals.first else {
            return arguments
        }
        guard isLegacyInputPath(input.value) else {
            guard input.index == arguments.startIndex || hasOutputOption else {
                return arguments
            }
            return [input.value]
        }
        if positionals.count > 1 {
            let output = positionals[1]
            var normalizedArguments = arguments
            normalizedArguments.remove(at: output.index)
            normalizedArguments.insert(["--output", output.value], beforeTerminator: "--")
            return ["export"] + normalizedArguments
        }
        let subcommand = hasOutputOption ? "export" : "info"
        return [subcommand] + arguments
    }

    private static var knownCommandNames: Set<String> {
        Set(
            configuration.subcommands.flatMap { command in
                [command._commandName] + command.configuration.aliases
            } + ["help"]
        )
    }
}

private func isLegacyInputPath(_ path: String) -> Bool {
    let url = expandPath(path, in: FileManager.default.currentDirectoryPath)
    return !url.pathExtension.isEmpty || FileManager.default.fileExists(atPath: url.path)
}

private extension Array where Element: Equatable {
    mutating func insert(_ elements: [Element], beforeTerminator terminator: Element) {
        if let index = firstIndex(of: terminator) {
            insert(contentsOf: elements, at: index)
        } else {
            append(contentsOf: elements)
        }
    }
}

private func parseScriptOptions(_ arguments: [String]) throws -> [String: Any] {
    guard arguments.count.isMultiple(of: 2) else {
        throw CLIError("Expected script option values after '\(arguments.last ?? "")'")
    }
    return try stride(from: 0, to: arguments.count, by: 2).reduce(into: [:]) { options, index in
        let argument = arguments[index]
        guard argument.hasPrefix("--"), argument.count > 2 else {
            throw CLIError("Invalid script option '\(argument)'")
        }
        let name = String(argument.dropFirst(2))
        guard !name.isEmpty else {
            throw CLIError("Invalid script option '\(argument)'")
        }
        options[name] = arguments[index + 1]
    }
}

struct CacheOptions: ParsableArguments {
    @Flag(help: "Run without reading or writing cached geometry from disk.")
    var noCache = false
}

extension ShapeScriptCommand {
    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check a ShapeScript document for errors."
        )

        @Flag(help: "Evaluate the document in preview mode.")
        var preview = false

        @OptionGroup
        var cacheOptions: CacheOptions

        @Argument(help: "Input .shape file.")
        var inputPath: String

        @Argument(parsing: .postTerminator, help: "Top-level script options as --name value pairs.")
        var scriptOptions: [String] = []

        init() {}

        mutating func run() throws {
            let runner = try CLIRunner(
                directory: FileManager.default.currentDirectoryPath,
                inputPath: inputPath,
                preview: preview,
                scriptOptions: scriptOptions,
                cacheOptions: cacheOptions
            )
            try runner.check()
        }
    }

    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print scene information for a ShapeScript document."
        )

        @Flag(help: "Evaluate the document in preview mode.")
        var preview = false

        @OptionGroup
        var cacheOptions: CacheOptions

        @Argument(help: "Input .shape file.")
        var inputPath: String

        @Argument(parsing: .postTerminator, help: "Top-level script options as --name value pairs.")
        var scriptOptions: [String] = []

        init() {}

        mutating func run() throws {
            let runner = try CLIRunner(
                directory: FileManager.default.currentDirectoryPath,
                inputPath: inputPath,
                preview: preview,
                scriptOptions: scriptOptions,
                cacheOptions: cacheOptions
            )
            try runner.info()
        }
    }
}

final class CLIRunner {
    let inputURL: URL
    let preview: Bool
    let scriptOptions: [String: Any]
    let cacheOptions: CacheOptions

    func defaultExportURL(with options: ExportOptions) -> URL {
        let fileExtension = options.width != nil || options.height != nil ? "bmp" : "stl"
        return inputURL.deletingPathExtension().appendingPathExtension(fileExtension)
    }

    init(
        directory: String,
        inputPath: String,
        preview: Bool = false,
        scriptOptions: [String] = [],
        cacheOptions: CacheOptions = .init()
    ) throws {
        let inputURL = expandPath(inputPath, in: directory)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            guard !inputURL.pathExtension.isEmpty else {
                throw CLIError("Unexpected argument '\(inputPath)'")
            }
            throw CLIError("File '\(inputPath)' not found")
        }
        guard inputURL.pathExtension == "shape" else {
            throw CLIError("Unsupported file type '\(inputURL.pathExtension)'")
        }
        self.inputURL = inputURL
        self.scriptOptions = try parseScriptOptions(scriptOptions)
        self.cacheOptions = cacheOptions
        self.preview = preview
    }

    func check() throws {
        _ = try loadScene(buildGeometry: false)
    }

    func info() throws {
        let scene = try loadScene()
        print(scene.geometry.modelInfo)
    }

    func loadScene(buildGeometry: Bool = true) throws -> Scene {
        let input: String
        do {
            input = try String(contentsOf: inputURL)
        } catch {
            throw CLIError("\(error.localizedDescription)")
        }
        do {
            printStatus("Loading file '\(inputURL.lastPathComponent)' ...")
            let program = try parse(input)
            let cache = GeometryCache(diskCache: cacheOptions.noCache ? nil : .shared)
            printStatus("Running script ...")
            let scene = try evaluate(
                program,
                preview: preview,
                options: scriptOptions,
                delegate: self,
                cache: cache
            )
            if buildGeometry {
                printStatus("Building geometry ...")
                _ = scene.build { false }
            }
            return scene
        } catch let error as CLIError {
            throw error
        } catch {
            let error = ProgramError(error)
            throw CLIError(error.message(with: input))
        }
    }
}

extension CLIRunner: EvaluationDelegate {
    func resolveURL(for path: String) -> URL {
        URL(fileURLWithPath: path, relativeTo: inputURL)
    }

    func debugLog(_ values: [AnyHashable]) {
        var spaceNeeded = false
        print(values.compactMap {
            switch $0 {
            case let string as String:
                spaceNeeded = false
                return string
            case let value:
                let string = String(logDescriptionFor: value as Any)
                defer { spaceNeeded = true }
                return spaceNeeded ? " \(string)" : string
            }
        }.joined())
    }
}

func expandPath(_ path: String, in directory: String) -> URL {
    if path.hasPrefix("/") {
        URL(fileURLWithPath: path).standardized
    } else if path.hasPrefix("~") {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardized
    } else {
        URL(fileURLWithPath: directory).appendingPathComponent(path).standardized
    }
}
