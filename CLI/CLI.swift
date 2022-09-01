//
//  CLI.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 31/08/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Foundation
import SceneKit
import ShapeScript

#if canImport(SceneKit)
import SceneKit
#endif

class CLI {
    let inputURL: URL
    let outputURL: URL

    init?(in directory: String, with arguments: [String]) {
        guard arguments.count > 1 else {
            print("Usage: shapescript <input_path> [<output_path>]")
            return nil
        }

        inputURL = expandPath(arguments[1], in: directory)
        outputURL = arguments.count > 2 ?
            expandPath(arguments[2], in: directory) :
            inputURL.deletingPathExtension().appendingPathExtension("dae")
    }

    func run() -> Int32 {
        do {
            let input = try String(contentsOf: inputURL)
            let program = try parse(input)
            let cache = GeometryCache()
            let scene = try evaluate(program, delegate: self, cache: cache) { false }
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
            #if canImport(SceneKit)
            let scnScene = SCNScene()
            let scnNode = SCNNode(merged: geometry)
            scnScene.rootNode.addChildNode(scnNode)
            if scnScene.write(
                to: outputURL,
                options: [:],
                delegate: nil,
                progressHandler: nil
            ) {
                return 0
            }
            #endif
            print("Error: Unable to export \(outputURL.lastPathComponent)")
            return -1
        } catch {
            print("Error: \(error)")
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
