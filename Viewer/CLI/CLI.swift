//
//  CLI.swift
//  CLI
//
//  Created by Nick Lockwood on 13/04/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation
import ShapeScript

#if canImport(SceneKit)
import SceneKit
#endif

struct CLIError: Error, CustomNSError {
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
}

class CLI {
    let inputURL: URL?
    let outputURL: URL?
    let exportOptions: ExportOptions

    init(in directory: String, with arguments: [String]) throws {
        let argNames = ExportOptions.arguments.map { $0.name }
        let args = try preprocessArguments(arguments, argNames)
        self.inputURL = try args["1"].map {
            let url = expandPath($0, in: directory)
            guard url.pathExtension == "shape" else {
                throw CLIError("Unsupported file type '\(url.pathExtension)'")
            }
            return url
        }
        self.outputURL = try args["2"].map {
            let url = expandPath($0, in: directory)
            guard Self.exportTypes.contains(url.pathExtension) else {
                throw CLIError("Unsupported export file type '\(url.pathExtension)'")
            }
            return url
        }
        self.exportOptions = try ExportOptions(arguments: args)
    }

    func run() throws {
        let args = ExportOptions.arguments
        let indent = args.map { $0.name.count }.max() ?? 0
        let help = args.map { name, help -> String in
            let indent = String(repeating: " ", count: indent - name.count)
            return "  --\(name)\(indent)  \(help)"
        }
        guard let inputURL = inputURL else {
            print("""
            ShapeScript, version \(version)
            Copyright (c) 2023 Nick Lockwood

            USAGE:
              shapescript <input_path> [<output_path>] [<options>]

            OPTIONS:
            \(help.joined(separator: "\n"))
            """)
            return
        }
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
            print("Building geometry ...")
            _ = scene.build { true }
            let geometry = Geometry(
                type: .group,
                name: nil,
                transform: .identity,
                material: .default,
                smoothing: nil,
                wrapMode: nil,
                children: scene.children,
                sourceLocation: nil
            )
            guard let outputURL = outputURL else {
                // Show model info
                print(geometry.modelInfo)
                return
            }
            // Export model
            print("Exporting to '\(outputURL.lastPathComponent)' ...")
            try export(geometry, to: outputURL, with: exportOptions)
            print("Export complete")
        } catch let error as CLIError {
            throw error
        } catch {
            let error = ProgramError(error)
            throw CLIError(error.message(with: input))
        }
    }
}

extension CLI: EvaluationDelegate {
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

private func expandPath(_ path: String, in directory: String) -> URL {
    if path.hasPrefix("/") {
        return URL(fileURLWithPath: path).standardized
    }
    if path.hasPrefix("~") {
        return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardized
    }
    return URL(fileURLWithPath: directory).appendingPathComponent(path).standardized
}

private func preprocessArguments(
    _ args: [String],
    _ names: [String]
) throws -> [String: String] {
    var anonymousArgs = 0
    var namedArgs: [String: String] = [:]
    var name = ""
    for arg in args {
        if arg.hasPrefix("--") {
            // Long argument names
            let key = String(arg.unicodeScalars.dropFirst(2))
            guard names.contains(key) else {
                guard let match = key.bestMatches(in: names).first else {
                    throw CLIError("Unknown option --\(key)")
                }
                throw CLIError("Unknown option --\(key). Did you mean --\(match)?")
            }
            name = key
            namedArgs[name] = namedArgs[name] ?? ""
            continue
        } else if arg.hasPrefix("-") {
            // Short argument names
            let flag = String(arg.unicodeScalars.dropFirst())
            guard let match = names.first(where: { $0.hasPrefix(flag) }) else {
                guard let match = flag.bestMatches(in: names).first else {
                    throw CLIError("Unknown flag -\(flag)")
                }
                throw CLIError("Unknown flag -\(flag). Did you mean -\(match)?")
            }
            name = match
            namedArgs[name] = namedArgs[name] ?? ""
            continue
        }
        if name == "" {
            // Argument is anonymous
            name = String(anonymousArgs)
            anonymousArgs += 1
        } else if namedArgs[name] != "" {
            throw CLIError("Duplicate option --\(name)")
        }
        namedArgs[name] = arg
        name = ""
    }
    return namedArgs
}
