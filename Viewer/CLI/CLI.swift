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

public struct ShapeScriptCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "shapescript",
        abstract: "Check, inspect, and export ShapeScript documents.",
        version: version,
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
        guard !positionals.isEmpty || hasOutputOption else {
            return arguments
        }
        if positionals.count > 1 {
            let output = positionals[1]
            var normalizedArguments = arguments
            normalizedArguments.remove(at: output.index)
            return ["export"] + normalizedArguments + ["--output", output.value]
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

extension ShapeScriptCommand {
    struct Check: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check a ShapeScript document for errors."
        )

        @Argument(help: "Input .shape file.")
        var inputPath: String

        init() {}

        mutating func run() throws {
            let runner = try CLIRunner(
                directory: FileManager.default.currentDirectoryPath,
                inputPath: inputPath
            )
            try runner.check()
        }
    }

    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print scene information for a ShapeScript document."
        )

        @Argument(help: "Input .shape file.")
        var inputPath: String

        init() {}

        mutating func run() throws {
            let runner = try CLIRunner(
                directory: FileManager.default.currentDirectoryPath,
                inputPath: inputPath
            )
            try runner.info()
        }
    }
}

final class CLIRunner {
    let inputURL: URL

    init(directory: String, inputPath: String) throws {
        let inputURL = expandPath(inputPath, in: directory)
        guard inputURL.pathExtension == "shape" else {
            throw CLIError("Unsupported file type '\(inputURL.pathExtension)'")
        }
        self.inputURL = inputURL
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
            print("Loading file '\(inputURL.lastPathComponent)' ...")
            let program = try parse(input)
            let cache = GeometryCache()
            print("Running script ...")
            let scene = try evaluate(program, delegate: self, cache: cache) { false }
            if buildGeometry {
                print("Building geometry ...")
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
        return URL(fileURLWithPath: path).standardized
    }
    if path.hasPrefix("~") {
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardized
    }
    return URL(fileURLWithPath: directory).appendingPathComponent(path).standardized
}
