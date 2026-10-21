//
//  Geometry+OBJImport.swift
//  ShapeScript
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

extension Geometry {
    /// Preserve OBJ object/group boundaries that platform mesh loaders may merge.
    static func namedOBJ(
        _ source: String,
        materials: @autoclosure () -> [String: Material],
        isCancelled: CancellationHandler
    ) throws -> Geometry? {
        let sourceLines = source.components(separatedBy: .newlines)
        guard sourceLines.contains(where: {
            let parts = $0.split(whereSeparator: \.isWhitespace)
            return parts.count > 1 && (parts[0] == "o" || parts[0] == "g")
        }) else { return nil }
        let materials = materials()
        final class Node {
            var name: String?
            var children = [Node]()
            var meshes = [Mesh]()

            init(_ name: String? = nil) { self.name = name }

            func geometry() -> Geometry? {
                let children = children.compactMap { $0.geometry() }
                guard !meshes.isEmpty || !children.isEmpty else { return nil }
                return Geometry(
                    type: meshes.isEmpty ? .group : .mesh(Mesh.merge(meshes)),
                    name: name, transform: .identity, material: .default, smoothing: nil,
                    children: children, sourceLocation: nil
                )
            }
        }
        let root = Node()
        var object = root
        var group = root
        var vertices = [[String]](repeating: [], count: 3)
        var indices = [[Int: Int]](repeating: [:], count: 3)
        var lines = [String]()
        var material: Material?
        var hasNames = false
        func flush() {
            if let mesh = Mesh(objString: lines.joined(separator: "\n")), !mesh.isEmpty {
                group.meshes.append(mesh.replacing(nil, with: material))
            }
            lines.removeAll(keepingCapacity: true)
            indices = [[Int: Int]](repeating: [:], count: 3)
        }
        for line in sourceLines {
            if isCancelled() { throw CancellationError() }
            let parts = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .split(whereSeparator: \.isWhitespace)
            guard let command = parts.first else { continue }
            let name = parts.dropFirst().joined(separator: " ")
            switch command {
            case "v", "vt", "vn":
                let kind = command == "v" ? 0 : command == "vt" ? 1 : 2
                vertices[kind].append(parts.joined(separator: " "))
            case "o":
                flush()
                object = Node(name.isEmpty ? nil : name)
                root.children.append(object)
                group = object
                hasNames = hasNames || !name.isEmpty
            case "g":
                flush()
                if name.isEmpty || name == "off" {
                    group = object
                } else if let existing = object.children.first(where: { $0.name == name }) {
                    group = existing
                } else {
                    group = Node(name)
                    object.children.append(group)
                }
                hasNames = hasNames || group !== object
            case "usemtl":
                flush()
                material = materials[name]
            case "f":
                var face = [String]()
                for vertex in parts.dropFirst() {
                    let components = vertex.split(separator: "/", omittingEmptySubsequences: false)
                    var remapped = [String]()
                    for (kind, component) in components.prefix(3).enumerated() {
                        guard let raw = Int(component), raw != 0 else {
                            remapped.append("")
                            continue
                        }
                        let index = raw > 0 ? raw - 1 : vertices[kind].count + raw
                        guard vertices[kind].indices.contains(index) else {
                            remapped.append("0")
                            continue
                        }
                        if indices[kind][index] == nil {
                            indices[kind][index] = indices[kind].count + 1
                            lines.append(vertices[kind][index])
                        }
                        remapped.append(String(indices[kind][index] ?? 0))
                    }
                    face.append(remapped.joined(separator: "/"))
                }
                lines.append("f " + face.joined(separator: " "))
            default:
                break
            }
        }
        flush()
        return hasNames ? root.geometry() : nil
    }
}
