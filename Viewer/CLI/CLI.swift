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

class CLI {
    let inputURL: URL
    let outputURL: URL?

    init?(in directory: String, with arguments: [String]) {
        guard arguments.count > 1 else {
            print("Usage: shapescript <input_path> [<output_path>]")
            return nil
        }

        inputURL = expandPath(arguments[1], in: directory)
        guard inputURL.pathExtension == "shape" else {
            print("Error: Unsupported file type '\(inputURL.pathExtension)'")
            return nil
        }

        if arguments.count > 2 {
            let outputURL = expandPath(arguments[2], in: directory)
            guard outputURL.pathExtension == "stl" else {
                print("Error: Unsupported export file type '\(outputURL.pathExtension)'")
                return nil
            }
            self.outputURL = outputURL
        } else {
            outputURL = nil
        }
    }

    func run() -> Int32 {
        let input: String
        do {
            input = try String(contentsOf: inputURL)
        } catch {
            print("Error: \(error.localizedDescription)")
            return -1
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
                children: scene.children,
                sourceLocation: nil
            )
            guard let outputURL = outputURL else {
                // Show model info
                print(geometry.modelInfo)
                return 0
            }
            // Export model
            print("Exporting to '\(outputURL.lastPathComponent)' ...")
            let mesh = geometry.merged()
            let name = inputURL.deletingPathExtension().lastPathComponent
            let stl = mesh.stlString(name: name)
            try stl.write(to: outputURL, atomically: true, encoding: .utf8)
            print("Export complete")
            return 0
        } catch {
            let error = ProgramError(error)
            print(error.message(with: input))
            return -1
        }
    }
}

extension CLI: EvaluationDelegate {
    func resolveURL(for path: String) -> URL {
        URL(fileURLWithPath: path, relativeTo: inputURL)
    }

    func importGeometry(for url: URL) throws -> Geometry? {
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
            ])
            return try Geometry(scene.rootNode)
        #else
            return nil
        #endif
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
